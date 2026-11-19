-- =====================================================================
-- SIGO — Migração 007: medição de empreiteiro
-- Rode DEPOIS da migração anterior (só aditiva).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 3. Medição de empreiteiro (só Engenheiro)
--    Contrato com itens (quantidade x preço) → medições por período.
--    Aprovar a medição lança a despesa (valor medido − retenção).
-- ---------------------------------------------------------------------
create table if not exists public.contratos (
  id           uuid primary key default gen_random_uuid(),
  obra_id      uuid not null references public.obras(id) on delete restrict,
  empreiteiro  text not null,
  objeto       text not null default '',
  retencao_pct numeric(5,2) not null default 0 check (retencao_pct between 0 and 100),
  status       text not null default 'Ativo' check (status in ('Ativo', 'Encerrado')),
  criado_em    timestamptz not null default now()
);
create table if not exists public.contrato_itens (
  id          uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.contratos(id) on delete cascade,
  descricao   text not null,
  unidade     text not null default 'un',
  qtd         numeric(14,3) not null check (qtd > 0),
  preco_unit  numeric(14,2) not null default 0 check (preco_unit >= 0),
  ordem       int not null default 0
);
create table if not exists public.medicoes (
  id            uuid primary key default gen_random_uuid(),
  contrato_id   uuid not null references public.contratos(id) on delete restrict,
  numero        int not null,
  periodo_ini   date not null,
  periodo_fim   date not null,
  status        text not null default 'Rascunho' check (status in ('Rascunho', 'Aprovada')),
  obs           text not null default '',
  valor_bruto   numeric(14,2) not null default 0,
  retencao      numeric(14,2) not null default 0,
  valor_liquido numeric(14,2) not null default 0,
  despesa_id    uuid references public.despesas(id) on delete set null,
  aprovada_em   timestamptz,
  unique (contrato_id, numero),
  check (periodo_fim >= periodo_ini)
);
create table if not exists public.medicao_itens (
  medicao_id uuid not null references public.medicoes(id) on delete cascade,
  item_id    uuid not null references public.contrato_itens(id) on delete restrict,
  qtd        numeric(14,3) not null default 0 check (qtd >= 0),
  primary key (medicao_id, item_id)
);

alter table public.contratos      enable row level security;
alter table public.contrato_itens enable row level security;
alter table public.medicoes       enable row level security;
alter table public.medicao_itens  enable row level security;

create policy so_engenheiro on public.contratos for all to authenticated
  using (public.tem_perfil('Engenheiro')) with check (public.tem_perfil('Engenheiro'));
create policy so_engenheiro on public.contrato_itens for all to authenticated
  using (public.tem_perfil('Engenheiro')) with check (public.tem_perfil('Engenheiro'));
create policy leitura on public.medicoes for select to authenticated using (public.tem_perfil('Engenheiro'));
create policy criar on public.medicoes for insert to authenticated
  with check (public.tem_perfil('Engenheiro') and status = 'Rascunho');
create policy editar_rascunho on public.medicoes for update to authenticated
  using (public.tem_perfil('Engenheiro') and status = 'Rascunho')
  with check (public.tem_perfil('Engenheiro') and status = 'Rascunho');
create policy excluir_rascunho on public.medicoes for delete to authenticated
  using (public.tem_perfil('Engenheiro') and status = 'Rascunho');
create policy leitura on public.medicao_itens for select to authenticated using (public.tem_perfil('Engenheiro'));
create policy escrita_rascunho on public.medicao_itens for all to authenticated
  using (public.tem_perfil('Engenheiro') and exists (select 1 from public.medicoes m where m.id = medicao_id and m.status = 'Rascunho'))
  with check (public.tem_perfil('Engenheiro') and exists (select 1 from public.medicoes m where m.id = medicao_id and m.status = 'Rascunho'));

create or replace function public.aprovar_medicao(p_id uuid)
returns numeric language plpgsql security definer set search_path = public as $$
declare m medicoes%rowtype; c contratos%rowtype; v_bruto numeric; v_ret numeric; v_desp uuid; v_excesso text;
begin
  if not tem_perfil('Engenheiro') then raise exception 'Sem permissão.'; end if;
  select * into m from medicoes where id = p_id for update;
  if not found then raise exception 'Medição não encontrada.'; end if;
  if m.status <> 'Rascunho' then raise exception 'Esta medição já foi aprovada.'; end if;
  select * into c from contratos where id = m.contrato_id;

  -- nenhum item pode passar do contratado (acumulado das aprovadas + esta)
  select string_agg(ci.descricao, ', ') into v_excesso
  from contrato_itens ci
  where ci.contrato_id = c.id and
        coalesce((select sum(mi.qtd) from medicao_itens mi join medicoes mm on mm.id = mi.medicao_id
                  where mi.item_id = ci.id and (mm.status = 'Aprovada' or mm.id = m.id)), 0) > ci.qtd;
  if v_excesso is not null then
    raise exception 'A quantidade acumulada passa do contratado em: %.', v_excesso;
  end if;

  select coalesce(sum(round(mi.qtd * ci.preco_unit, 2)), 0) into v_bruto
  from medicao_itens mi join contrato_itens ci on ci.id = mi.item_id where mi.medicao_id = m.id;
  if v_bruto <= 0 then raise exception 'A medição está zerada.'; end if;
  v_ret := round(v_bruto * c.retencao_pct / 100, 2);

  insert into despesas (obra_id, descricao, categoria, valor, vencimento, status)
  values (c.obra_id, 'Medição nº ' || m.numero || ' — ' || c.empreiteiro ||
                     case when c.objeto <> '' then ' (' || c.objeto || ')' else '' end,
          'Mão de Obra', v_bruto - v_ret, m.periodo_fim + 10, 'A pagar')
  returning id into v_desp;

  update medicoes set status = 'Aprovada', valor_bruto = v_bruto, retencao = v_ret,
         valor_liquido = v_bruto - v_ret, despesa_id = v_desp, aprovada_em = now()
  where id = m.id;
  return v_bruto - v_ret;
end $$;

create or replace function public.reabrir_medicao(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare m medicoes%rowtype;
begin
  if not tem_perfil('Engenheiro') then raise exception 'Sem permissão.'; end if;
  select * into m from medicoes where id = p_id for update;
  if not found or m.status <> 'Aprovada' then raise exception 'Esta medição não está aprovada.'; end if;
  if exists (select 1 from medicoes where contrato_id = m.contrato_id and status = 'Aprovada' and numero > m.numero) then
    raise exception 'Reabra primeiro as medições posteriores deste contrato.';
  end if;
  if exists (select 1 from despesas where id = m.despesa_id and status = 'Pago') then
    raise exception 'A despesa desta medição já está paga. Volte-a para "A pagar" no Financeiro antes.';
  end if;
  delete from despesas where id = m.despesa_id;
  update medicoes set status = 'Rascunho', valor_bruto = 0, retencao = 0, valor_liquido = 0, despesa_id = null, aprovada_em = null
  where id = m.id;
end $$;

revoke all on function public.aprovar_medicao(uuid) from public, anon;
revoke all on function public.reabrir_medicao(uuid) from public, anon;
grant execute on function public.aprovar_medicao(uuid) to authenticated;
grant execute on function public.reabrir_medicao(uuid) to authenticated;

alter publication supabase_realtime add table public.contratos, public.contrato_itens, public.medicoes, public.medicao_itens;
