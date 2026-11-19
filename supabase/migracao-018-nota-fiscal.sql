-- =====================================================================
-- SIGO — Migração 018: Nota fiscal automática (importação do XML da NF-e)
-- O almoxarife ou o engenheiro carrega o XML que o fornecedor envia por
-- e-mail. Numa única operação o sistema:
--   * cadastra o fornecedor pelo CNPJ (se ainda não existir);
--   * dá entrada no estoque de cada item ligado a um material;
--   * baixa o pedido de compra correspondente (status Entregue);
--   * cria as contas a pagar a partir das duplicatas da nota;
--   * lembra "código do produto no fornecedor → material do SIGO" para a próxima nota.
-- A chave de acesso (44 dígitos) impede lançar a mesma nota duas vezes.
-- Um lançamento errado pode ser estornado pelo Engenheiro.
-- =====================================================================

alter table public.fornecedores add column if not exists cnpj text not null default '';
create unique index if not exists fornecedores_cnpj_unico on public.fornecedores (cnpj) where cnpj <> '';

create table if not exists public.notas_fiscais (
  id            uuid primary key default gen_random_uuid(),
  chave         text not null check (chave ~ '^[0-9]{44}$'),
  numero        text not null,
  serie         text not null default '',
  emissao       date not null,
  fornecedor_id uuid not null references public.fornecedores(id) on delete restrict,
  obra_id       uuid not null references public.obras(id) on delete restrict,
  valor_total   numeric(14,2) not null default 0,
  frete         numeric(14,2) not null default 0,
  desconto      numeric(14,2) not null default 0,
  status        text not null default 'Lançada' check (status in ('Lançada', 'Estornada')),
  lancada_por   text,
  estornada_por text,
  criado_em     timestamptz not null default now()
);

-- A mesma nota não pode estar lançada duas vezes (depois de estornada, pode ser lançada de novo).
create unique index if not exists notas_fiscais_chave_lancada on public.notas_fiscais (chave) where status = 'Lançada';

create table if not exists public.nota_itens (
  id          uuid primary key default gen_random_uuid(),
  nota_id     uuid not null references public.notas_fiscais(id) on delete cascade,
  ordem       int not null default 0,
  codigo_forn text not null default '',
  descricao   text not null,
  ncm         text not null default '',
  unidade_nf  text not null default '',
  qtd_nf      numeric(14,4) not null default 0,
  valor_unit  numeric(16,6) not null default 0,
  valor_total numeric(14,2) not null default 0,
  material_id uuid references public.materiais(id) on delete restrict,
  fator       numeric(14,6) not null default 1 check (fator > 0),
  qtd_estoque numeric(14,3),
  compra_id   uuid references public.compras(id) on delete set null,
  mov_id      uuid references public.movimentacoes(id) on delete set null
);
create index if not exists nota_itens_nota on public.nota_itens (nota_id);

create table if not exists public.nfe_mapeamentos (
  fornecedor_id uuid not null references public.fornecedores(id) on delete cascade,
  codigo_forn   text not null,
  material_id   uuid not null references public.materiais(id) on delete cascade,
  fator         numeric(14,6) not null default 1 check (fator > 0),
  atualizado_em timestamptz not null default now(),
  primary key (fornecedor_id, codigo_forn)
);

alter table public.despesas add column if not exists nota_id uuid references public.notas_fiscais(id) on delete set null;

alter table public.notas_fiscais   enable row level security;
alter table public.nota_itens      enable row level security;
alter table public.nfe_mapeamentos enable row level security;

-- Leitura para a equipe interna (Cliente não vê); escrita só pelas funções abaixo.
create policy leitura on public.notas_fiscais   for select to authenticated using (public.meu_perfil() is not null);
create policy leitura on public.nota_itens      for select to authenticated using (public.meu_perfil() is not null);
create policy leitura on public.nfe_mapeamentos for select to authenticated using (public.meu_perfil() is not null);

-- ---------------------------------------------------------------------
-- lancar_nota_fiscal(p jsonb)
-- p = { chave, numero, serie, emissao, emitente_cnpj, emitente_nome, fornecedor_id?,
--       obra_id, etapa_id?, valor_total, frete, desconto,
--       itens: [{ codigo, descricao, ncm, unidade, qtd, valor_unit, valor_total,
--                 material_id?, fator?, compra_id? }],
--       parcelas: [{ numero, vencimento, valor }] }
-- ---------------------------------------------------------------------
create or replace function public.lancar_nota_fiscal(p jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_nome text; v_chave text; v_forn uuid; v_cnpj text; v_obra uuid; v_nota uuid; v_etapa uuid;
  v_existente notas_fiscais%rowtype; it jsonb; pa jsonb; k int := 0; v_mat uuid; v_fator numeric;
  v_qtd numeric; v_mov uuid; v_compra uuid; c compras%rowtype; v_total numeric; v_parc int; n_parc int;
  v_fnome text; v_desc text;
begin
  if not tem_perfil('Engenheiro', 'Almoxarife') then raise exception 'Sem permissão.'; end if;
  select nome into v_nome from perfis where id = auth.uid();

  v_chave := regexp_replace(coalesce(p->>'chave', ''), '\D', '', 'g');
  if length(v_chave) <> 44 then raise exception 'Chave de acesso inválida (precisa ter 44 dígitos).'; end if;
  select * into v_existente from notas_fiscais where chave = v_chave and status = 'Lançada';
  if found then
    raise exception 'Esta nota (nº %) já foi lançada em % por %.', v_existente.numero,
      to_char(v_existente.criado_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY'), coalesce(v_existente.lancada_por, '—');
  end if;

  v_obra := nullif(p->>'obra_id', '')::uuid;
  if v_obra is null or not exists (select 1 from obras where id = v_obra) then raise exception 'Escolha a obra que recebeu o material.'; end if;
  v_etapa := nullif(p->>'etapa_id', '')::uuid;

  -- Fornecedor: o escolhido, ou pelo CNPJ, ou cadastra um novo.
  v_cnpj := regexp_replace(coalesce(p->>'emitente_cnpj', ''), '\D', '', 'g');
  v_forn := nullif(p->>'fornecedor_id', '')::uuid;
  if v_forn is null and v_cnpj <> '' then select id into v_forn from fornecedores where cnpj = v_cnpj; end if;
  if v_forn is null then
    if coalesce(trim(p->>'emitente_nome'), '') = '' then raise exception 'Nota sem o nome do fornecedor.'; end if;
    insert into fornecedores (nome, contato, categoria, cnpj)
    values (trim(p->>'emitente_nome'), '', 'Material', v_cnpj) returning id into v_forn;
  elsif v_cnpj <> '' then
    update fornecedores set cnpj = v_cnpj where id = v_forn and cnpj = ''
      and not exists (select 1 from fornecedores x where x.cnpj = v_cnpj and x.id <> v_forn);
  end if;
  select nome into v_fnome from fornecedores where id = v_forn;

  insert into notas_fiscais (chave, numero, serie, emissao, fornecedor_id, obra_id, valor_total, frete, desconto, lancada_por)
  values (v_chave, coalesce(nullif(trim(p->>'numero'), ''), '?'), coalesce(trim(p->>'serie'), ''),
          coalesce(nullif(p->>'emissao', '')::date, current_date), v_forn, v_obra,
          round(coalesce((p->>'valor_total')::numeric, 0), 2), round(coalesce((p->>'frete')::numeric, 0), 2),
          round(coalesce((p->>'desconto')::numeric, 0), 2), coalesce(v_nome, 'Sistema'))
  returning id into v_nota;

  for it in select * from jsonb_array_elements(coalesce(p->'itens', '[]'::jsonb)) loop
    k := k + 1;
    v_mat := nullif(it->>'material_id', '')::uuid;
    v_fator := coalesce(nullif(it->>'fator', '')::numeric, 1);
    if v_fator <= 0 then raise exception 'Fator de conversão inválido no item %.', k; end if;
    v_qtd := null; v_mov := null; v_compra := null;
    if v_mat is not null then
      v_qtd := round(coalesce((it->>'qtd')::numeric, 0) * v_fator, 3);
      if v_qtd <= 0 then raise exception 'Quantidade inválida no item "%".', it->>'descricao'; end if;
      perform _somar_estoque(v_mat, v_obra, v_qtd);
      insert into movimentacoes (tipo, obra_id, material_id, qtd, responsavel, obs, criado_por)
      values ('Entrada', v_obra, v_mat, v_qtd, coalesce(v_nome, 'Sistema'),
              'NF-e nº ' || coalesce(nullif(trim(p->>'numero'), ''), '?') || ' — ' || v_fnome, auth.uid())
      returning id into v_mov;
      if coalesce(trim(it->>'codigo'), '') <> '' then
        insert into nfe_mapeamentos (fornecedor_id, codigo_forn, material_id, fator)
        values (v_forn, trim(it->>'codigo'), v_mat, v_fator)
        on conflict (fornecedor_id, codigo_forn) do update set material_id = excluded.material_id, fator = excluded.fator, atualizado_em = now();
      end if;
      -- Pedido de compra atendido por esta nota: vira Entregue (sem nova entrada nem nova despesa).
      v_compra := nullif(it->>'compra_id', '')::uuid;
      if v_compra is not null then
        select * into c from compras where id = v_compra for update;
        if not found or c.status in ('Entregue', 'Cancelado') or c.material_id <> v_mat or c.obra_id <> v_obra then
          v_compra := null;
        else
          update compras set status = 'Entregue', fornecedor_id = coalesce(fornecedor_id, v_forn) where id = v_compra;
        end if;
      end if;
    end if;
    insert into nota_itens (nota_id, ordem, codigo_forn, descricao, ncm, unidade_nf, qtd_nf, valor_unit, valor_total,
                            material_id, fator, qtd_estoque, compra_id, mov_id)
    values (v_nota, k, coalesce(trim(it->>'codigo'), ''), coalesce(nullif(trim(it->>'descricao'), ''), 'Item ' || k),
            coalesce(it->>'ncm', ''), coalesce(it->>'unidade', ''), coalesce((it->>'qtd')::numeric, 0),
            coalesce((it->>'valor_unit')::numeric, 0), round(coalesce((it->>'valor_total')::numeric, 0), 2),
            v_mat, v_fator, v_qtd, v_compra, v_mov);
  end loop;
  if k = 0 then raise exception 'A nota não tem itens.'; end if;

  -- Contas a pagar: uma por duplicata; sem duplicatas, uma só no valor da nota.
  v_desc := 'NF ' || coalesce(nullif(trim(p->>'numero'), ''), '?') || ' — ' || v_fnome;
  n_parc := jsonb_array_length(coalesce(p->'parcelas', '[]'::jsonb));
  v_parc := 0;
  if n_parc > 0 then
    for pa in select * from jsonb_array_elements(p->'parcelas') loop
      v_parc := v_parc + 1;
      v_total := round(coalesce((pa->>'valor')::numeric, 0), 2);
      if v_total > 0 then
        insert into despesas (obra_id, etapa_id, nota_id, descricao, categoria, valor, vencimento, status)
        values (v_obra, v_etapa, v_nota, v_desc || case when n_parc > 1 then ' (parc. ' || v_parc || '/' || n_parc || ')' else '' end,
                'Material', v_total, coalesce(nullif(pa->>'vencimento', '')::date, current_date), 'A pagar');
      end if;
    end loop;
  else
    v_total := round(coalesce((p->>'valor_total')::numeric, 0), 2);
    if v_total > 0 then
      insert into despesas (obra_id, etapa_id, nota_id, descricao, categoria, valor, vencimento, status)
      values (v_obra, v_etapa, v_nota, v_desc, 'Material', v_total,
              coalesce(nullif(p->>'vencimento', '')::date, nullif(p->>'emissao', '')::date, current_date), 'A pagar');
    end if;
  end if;
  return v_nota;
end $$;
revoke all on function public.lancar_nota_fiscal(jsonb) from public, anon;
grant execute on function public.lancar_nota_fiscal(jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- estornar_nota_fiscal: desfaz um lançamento errado (só Engenheiro e
-- só se nenhuma parcela já foi paga). Devolve o estoque, apaga as contas
-- a pagar e reabre os pedidos de compra que a nota tinha baixado.
-- ---------------------------------------------------------------------
create or replace function public.estornar_nota_fiscal(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare n notas_fiscais%rowtype; it nota_itens%rowtype; m movimentacoes%rowtype; v_nome text;
begin
  if not tem_perfil('Engenheiro') then raise exception 'Só o Engenheiro estorna notas fiscais.'; end if;
  select * into n from notas_fiscais where id = p_id for update;
  if not found then raise exception 'Nota não encontrada.'; end if;
  if n.status = 'Estornada' then raise exception 'Esta nota já foi estornada.'; end if;
  if exists (select 1 from despesas where nota_id = p_id and status = 'Pago') then
    raise exception 'Há parcela desta nota já paga. Desfaça o pagamento no Financeiro antes de estornar.';
  end if;
  select nome into v_nome from perfis where id = auth.uid();

  for it in select * from nota_itens where nota_id = p_id loop
    if it.mov_id is not null then
      select * into m from movimentacoes where id = it.mov_id for update;
      if found and not m.estornada then
        perform _somar_estoque(m.material_id, m.obra_id, -m.qtd);
        update movimentacoes set estornada = true where id = m.id;
        insert into movimentacoes (tipo, tipo_original, estorno_de, obra_id, material_id, qtd, responsavel, obs, criado_por)
        values ('Estorno', 'Entrada', m.id, m.obra_id, m.material_id, m.qtd, coalesce(v_nome, 'Sistema'),
                'Estorno da NF-e nº ' || n.numero, auth.uid());
      end if;
    end if;
    if it.compra_id is not null then
      update compras set status = 'Comprado' where id = it.compra_id and status = 'Entregue';
    end if;
  end loop;
  delete from despesas where nota_id = p_id;
  update notas_fiscais set status = 'Estornada', estornada_por = coalesce(v_nome, 'Sistema') where id = p_id;
end $$;
revoke all on function public.estornar_nota_fiscal(uuid) from public, anon;
grant execute on function public.estornar_nota_fiscal(uuid) to authenticated;

-- Obra de exemplo: apagar também as notas fiscais.
create or replace function public.apagar_obra_exemplo(p_obra uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_nome text; fs uuid[];
begin
  if not sou_administrador() then raise exception 'Só um administrador pode apagar a obra de exemplo.'; end if;
  select nome into v_nome from obras where id = p_obra;
  if v_nome is null then raise exception 'Obra não encontrada.'; end if;
  if v_nome not like '%(exemplo)' then raise exception 'Só obras de exemplo podem ser apagadas por aqui.'; end if;
  select array_agg(id) into fs from funcionarios where obra_id = p_obra;

  delete from producoes where obra_id = p_obra;
  delete from pendencias where obra_id = p_obra;
  delete from inspecoes where obra_id = p_obra;
  delete from cotacoes where obra_id = p_obra;
  delete from medicoes where contrato_id in (select id from contratos where obra_id = p_obra);
  delete from contratos where obra_id = p_obra;
  delete from receitas where obra_id = p_obra;
  delete from despesas where obra_id = p_obra;
  delete from notas_fiscais where obra_id = p_obra;
  delete from compras where obra_id = p_obra;
  delete from epi_entregas where obra_id = p_obra;
  delete from movimentacoes where obra_id = p_obra;
  delete from estoques where obra_id = p_obra;
  delete from diarios where obra_id = p_obra;
  delete from etapas where obra_id = p_obra;
  delete from documentos where funcionario_id = any(coalesce(fs, '{}')) or empresa like '%(exemplo)%';
  delete from folha_itens where funcionario_id = any(coalesce(fs, '{}'));
  delete from folhas f where not exists (select 1 from folha_itens i where i.mes = f.mes);
  update folhas f set total = (select coalesce(sum(total), 0) from folha_itens i where i.mes = f.mes);
  delete from funcionarios where obra_id = p_obra;
  delete from obras where id = p_obra;
  delete from materiais m where codigo like 'EX-%'
    and not exists (select 1 from movimentacoes x where x.material_id = m.id)
    and not exists (select 1 from compras x where x.material_id = m.id)
    and not exists (select 1 from estoques x where x.material_id = m.id)
    and not exists (select 1 from cotacao_itens x where x.material_id = m.id)
    and not exists (select 1 from nota_itens x where x.material_id = m.id);
  delete from fornecedores f where nome like '%(exemplo)%'
    and not exists (select 1 from compras x where x.fornecedor_id = f.id)
    and not exists (select 1 from cotacao_fornecedores x where x.fornecedor_id = f.id)
    and not exists (select 1 from notas_fiscais x where x.fornecedor_id = f.id);
  delete from servicos_producao s where nome like '%(exemplo)%' and not exists (select 1 from producoes p where p.servico_id = s.id);
  update caixa set saldo_inicial = 0, atualizado_em = now() where id = 1 and saldo_inicial = 120000 and data_saldo = date '2026-08-24';
end $$;

alter publication supabase_realtime add table public.notas_fiscais, public.nota_itens;
