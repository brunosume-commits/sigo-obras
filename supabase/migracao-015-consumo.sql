-- =====================================================================
-- SIGO — Migração 015: consumo previsto x real (perda de material)
-- Rode DEPOIS da migração 014 (só aditiva).
-- servicos_producao + indices_consumo: quanto cada serviço gasta de cada material
-- producoes: o que foi executado (Mestre ou Engenheiro lança)
-- analise_consumo(): previsto (produção × índice) x real (saídas do estoque)
-- =====================================================================

create table if not exists public.servicos_producao (
  id        uuid primary key default gen_random_uuid(),
  nome      text not null,
  unidade   text not null default 'm²',
  ativo     boolean not null default true,
  criado_em timestamptz not null default now()
);
create table if not exists public.indices_consumo (
  servico_id     uuid not null references public.servicos_producao(id) on delete cascade,
  material_id    uuid not null references public.materiais(id) on delete cascade,
  consumo        numeric(14,4) not null check (consumo > 0),   -- unidades do material por unidade do serviço
  tolerancia_pct numeric(5,2) not null default 5 check (tolerancia_pct between 0 and 100),
  primary key (servico_id, material_id)
);
create table if not exists public.producoes (
  id           uuid primary key default gen_random_uuid(),
  obra_id      uuid not null references public.obras(id) on delete restrict,
  servico_id   uuid not null references public.servicos_producao(id) on delete restrict,
  etapa_id     uuid references public.etapas(id) on delete set null,
  dia          date not null default (now() at time zone 'America/Sao_Paulo')::date,
  quantidade   numeric(14,3) not null check (quantidade > 0),
  local        text not null default '',
  equipe       text not null default '',
  registrado_por text,
  criado_em    timestamptz not null default now()
);
create index if not exists producoes_obra_dia_idx on public.producoes (obra_id, dia);

alter table public.servicos_producao enable row level security;
alter table public.indices_consumo  enable row level security;
alter table public.producoes        enable row level security;

create policy leitura on public.servicos_producao for select to authenticated using (public.meu_perfil() is not null);
create policy gerir on public.servicos_producao for all to authenticated using (public.tem_perfil('Engenheiro')) with check (public.tem_perfil('Engenheiro'));
create policy leitura on public.indices_consumo for select to authenticated using (public.meu_perfil() is not null);
create policy gerir on public.indices_consumo for all to authenticated using (public.tem_perfil('Engenheiro')) with check (public.tem_perfil('Engenheiro'));
create policy leitura on public.producoes for select to authenticated using (public.tem_perfil('Engenheiro', 'Mestre de Obras'));
create policy lancar on public.producoes for insert to authenticated with check (public.tem_perfil('Engenheiro', 'Mestre de Obras'));
create policy editar on public.producoes for update to authenticated using (public.tem_perfil('Engenheiro', 'Mestre de Obras')) with check (public.tem_perfil('Engenheiro', 'Mestre de Obras'));
create policy excluir on public.producoes for delete to authenticated using (public.tem_perfil('Engenheiro', 'Mestre de Obras'));

-- Previsto x real por material num período (só materiais que têm índice cadastrado)
create or replace function public.analise_consumo(p_obra uuid, p_ini date, p_fim date)
returns table (material_id uuid, previsto numeric, realizado numeric, tolerancia numeric)
language sql stable security invoker set search_path = public as $$
  with prev as (
    select i.material_id, sum(p.quantidade * i.consumo) as previsto, max(i.tolerancia_pct) as tol
    from producoes p join indices_consumo i on i.servico_id = p.servico_id
    where p.obra_id = p_obra and p.dia between p_ini and p_fim
    group by i.material_id
  ), saidas as (
    select m.material_id, sum(m.qtd) as saiu
    from movimentacoes m
    where m.obra_id = p_obra and m.tipo = 'Saída' and not m.estornada
      and (m.data at time zone 'America/Sao_Paulo')::date between p_ini and p_fim
      and m.material_id in (select x.material_id from indices_consumo x)
    group by m.material_id
  )
  select coalesce(prev.material_id, saidas.material_id), round(coalesce(prev.previsto, 0), 3), round(coalesce(saidas.saiu, 0), 3),
         coalesce(prev.tol, (select max(tolerancia_pct) from indices_consumo x where x.material_id = saidas.material_id))
  from prev full join saidas on saidas.material_id = prev.material_id
$$;
grant execute on function public.analise_consumo(uuid, date, date) to authenticated;

alter publication supabase_realtime add table public.servicos_producao, public.indices_consumo, public.producoes;

-- O botão "Apagar exemplo" passa a apagar também a produção lançada
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
    and not exists (select 1 from cotacao_itens x where x.material_id = m.id);
  delete from fornecedores f where nome like '%(exemplo)%'
    and not exists (select 1 from compras x where x.fornecedor_id = f.id)
    and not exists (select 1 from cotacao_fornecedores x where x.fornecedor_id = f.id);
  delete from servicos_producao s where nome like '%(exemplo)%' and not exists (select 1 from producoes p where p.servico_id = s.id);
  update caixa set saldo_inicial = 0, atualizado_em = now() where id = 1 and saldo_inicial = 120000 and data_saldo = date '2026-08-24';
end $$;
