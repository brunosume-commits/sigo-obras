-- =====================================================================
-- SIGO — Migração 003: folha de pagamento simples (diaristas e mensalistas)
-- Rode no SQL Editor DEPOIS da migração 002 (só aditiva).
--
-- Regras de cálculo (feitas no banco, no fechamento):
--   Diária : valor da diária × dias marcados como "Presente" no mês.
--   Mensal : salário − (salário ÷ 30 × faltas do mês). Atestado não desconta.
--   Ajuste : valor livre (+ ou −) por funcionário, informado no fechamento
--            (hora extra, adiantamento, vale etc.).
-- Não calcula encargos (INSS, FGTS, IRRF), férias nem 13º.
-- Valores de pagamento: só o Engenheiro vê e altera.
-- =====================================================================

-- Remuneração de cada funcionário (separada do cadastro, que todos veem)
create table if not exists public.remuneracoes (
  funcionario_id uuid primary key references public.funcionarios(id) on delete cascade,
  tipo           text not null default 'Diária' check (tipo in ('Diária', 'Mensal')),
  valor          numeric(12,2) not null default 0 check (valor >= 0),
  atualizado_em  timestamptz not null default now()
);
alter table public.remuneracoes enable row level security;
create policy so_engenheiro on public.remuneracoes for all to authenticated
  using (public.tem_perfil('Engenheiro')) with check (public.tem_perfil('Engenheiro'));

-- Folha fechada de um mês
create table if not exists public.folhas (
  mes         text primary key check (mes ~ '^\d{4}-\d{2}$'),
  fechada_em  timestamptz not null default now(),
  fechada_por uuid references auth.users(id),
  total       numeric(14,2) not null default 0
);
alter table public.folhas enable row level security;
create policy so_engenheiro on public.folhas for select to authenticated
  using (public.tem_perfil('Engenheiro'));

-- Itens da folha (foto dos valores no momento do fechamento)
create table if not exists public.folha_itens (
  mes            text not null references public.folhas(mes) on delete cascade,
  funcionario_id uuid not null references public.funcionarios(id) on delete restrict,
  nome           text not null,
  funcao         text not null default '',
  obra_id        uuid references public.obras(id) on delete restrict,
  tipo           text not null,
  valor_base     numeric(12,2) not null,
  presentes      int not null default 0,
  faltas         int not null default 0,
  atestados      int not null default 0,
  valor_calculado numeric(14,2) not null,
  ajuste         numeric(14,2) not null default 0,
  ajuste_obs     text not null default '',
  total          numeric(14,2) not null,
  despesa_id     uuid references public.despesas(id) on delete set null,
  primary key (mes, funcionario_id)
);
alter table public.folha_itens enable row level security;
create policy so_engenheiro on public.folha_itens for select to authenticated
  using (public.tem_perfil('Engenheiro'));
-- Escrita de folhas e itens: só pelas funções abaixo.

-- Fecha a folha do mês: calcula, grava os itens e lança uma despesa por obra
create or replace function public.fechar_folha(p_mes text, p_ajustes jsonb default '{}'::jsonb)
returns numeric language plpgsql security definer set search_path = public as $$
declare
  v_ini date; v_fim date; v_total numeric := 0; v_venc date; r record; v_desp uuid;
  v_meses text[] := array['jan','fev','mar','abr','mai','jun','jul','ago','set','out','nov','dez'];
  v_rotulo text;
begin
  if not tem_perfil('Engenheiro') then raise exception 'Sem permissão.'; end if;
  if p_mes !~ '^\d{4}-\d{2}$' then raise exception 'Mês inválido.'; end if;
  perform pg_advisory_xact_lock(hashtext('sigo_folha_' || p_mes));
  if exists (select 1 from folhas where mes = p_mes) then
    raise exception 'A folha de % já está fechada. Reabra para refazer.', p_mes;
  end if;
  v_ini := (p_mes || '-01')::date;
  v_fim := (v_ini + interval '1 month' - interval '1 day')::date;
  v_venc := (v_ini + interval '1 month' + interval '4 days')::date;   -- dia 5 do mês seguinte
  v_rotulo := v_meses[extract(month from v_ini)::int] || '/' || extract(year from v_ini)::int;

  insert into folhas (mes, fechada_por) values (p_mes, auth.uid());

  insert into folha_itens (mes, funcionario_id, nome, funcao, obra_id, tipo, valor_base,
                           presentes, faltas, atestados, valor_calculado, ajuste, ajuste_obs, total)
  select p_mes, fu.id, fu.nome, fu.funcao, fu.obra_id, rm.tipo, rm.valor,
         coalesce(c.n_pres, 0), coalesce(c.n_falta, 0), coalesce(c.n_atest, 0),
         calc.v,
         coalesce((p_ajustes -> fu.id::text ->> 'valor')::numeric, 0),
         coalesce(p_ajustes -> fu.id::text ->> 'obs', ''),
         round(calc.v + coalesce((p_ajustes -> fu.id::text ->> 'valor')::numeric, 0), 2)
  from funcionarios fu
  join remuneracoes rm on rm.funcionario_id = fu.id
  left join lateral (
    select count(*) filter (where pr.status = 'Presente') n_pres,
           count(*) filter (where pr.status = 'Falta') n_falta,
           count(*) filter (where pr.status = 'Atestado') n_atest
    from presencas pr where pr.funcionario_id = fu.id and pr.dia between v_ini and v_fim
  ) c on true
  cross join lateral (
    select case when rm.tipo = 'Diária' then round(rm.valor * coalesce(c.n_pres, 0), 2)
                else greatest(0, round(rm.valor - rm.valor / 30 * coalesce(c.n_falta, 0), 2)) end v
  ) calc
  where rm.valor > 0;

  if not exists (select 1 from folha_itens where mes = p_mes) then
    raise exception 'Nenhum funcionário com diária ou salário cadastrado.';
  end if;

  -- uma despesa "Mão de Obra" por obra
  for r in
    select obra_id, sum(total) as soma, count(*) as qtd from folha_itens fi
    where mes = p_mes and obra_id is not null group by obra_id having sum(total) > 0
  loop
    insert into despesas (obra_id, descricao, categoria, valor, vencimento, status)
    values (r.obra_id, 'Folha de pagamento ' || v_rotulo || ' (' || r.qtd || ' funcionário(s))',
            'Mão de Obra', r.soma, v_venc, 'A pagar')
    returning id into v_desp;
    update folha_itens set despesa_id = v_desp where mes = p_mes and obra_id = r.obra_id;
  end loop;

  select coalesce(sum(total), 0) into v_total from folha_itens where mes = p_mes;
  update folhas set total = v_total where mes = p_mes;
  return v_total;
end $$;

-- Reabre a folha: apaga os itens e as despesas lançadas (se ainda não pagas)
create or replace function public.reabrir_folha(p_mes text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not tem_perfil('Engenheiro') then raise exception 'Sem permissão.'; end if;
  if not exists (select 1 from folhas where mes = p_mes) then raise exception 'Esta folha não está fechada.'; end if;
  if exists (select 1 from despesas d join folha_itens i on i.despesa_id = d.id
             where i.mes = p_mes and d.status = 'Pago') then
    raise exception 'Há despesa desta folha já marcada como Paga. Volte-a para "A pagar" no Financeiro antes de reabrir.';
  end if;
  delete from despesas where id in (select despesa_id from folha_itens where mes = p_mes and despesa_id is not null);
  delete from folhas where mes = p_mes;   -- itens saem em cascata
end $$;

revoke all on function public.fechar_folha(text, jsonb) from public, anon;
revoke all on function public.reabrir_folha(text) from public, anon;
grant execute on function public.fechar_folha(text, jsonb) to authenticated;
grant execute on function public.reabrir_folha(text) to authenticated;

alter publication supabase_realtime add table public.remuneracoes, public.folhas, public.folha_itens;
