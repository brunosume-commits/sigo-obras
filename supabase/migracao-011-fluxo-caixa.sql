-- =====================================================================
-- SIGO — Migração 011: fluxo de caixa (só Engenheiro)
-- Rode DEPOIS da migração 010 (só aditiva).
-- receitas  → o que a construtora recebe (medição do cliente, aporte, venda…)
-- despesas.pago_em → data em que a despesa foi paga (para o caixa realizado)
-- caixa     → saldo inicial de referência (uma linha só)
-- =====================================================================

create table if not exists public.receitas (
  id          uuid primary key default gen_random_uuid(),
  obra_id     uuid references public.obras(id) on delete restrict,
  descricao   text not null,
  categoria   text not null default 'Medição do cliente',
  valor       numeric(14,2) not null check (valor > 0),
  vencimento  date not null,
  status      text not null default 'A receber' check (status in ('A receber', 'Recebido')),
  recebido_em date,
  criado_em   timestamptz not null default now()
);
alter table public.receitas enable row level security;
create policy so_engenheiro on public.receitas for all to authenticated
  using (public.tem_perfil('Engenheiro')) with check (public.tem_perfil('Engenheiro'));

alter table public.despesas add column if not exists pago_em date;
update public.despesas set pago_em = coalesce(vencimento, criado_em::date) where status = 'Pago' and pago_em is null;

create table if not exists public.caixa (
  id            int primary key default 1 check (id = 1),
  saldo_inicial numeric(14,2) not null default 0,
  data_saldo    date not null default (now() at time zone 'America/Sao_Paulo')::date,
  atualizado_em timestamptz not null default now()
);
insert into public.caixa (id) values (1) on conflict do nothing;
alter table public.caixa enable row level security;
create policy so_engenheiro on public.caixa for all to authenticated
  using (public.tem_perfil('Engenheiro')) with check (public.tem_perfil('Engenheiro'));

alter publication supabase_realtime add table public.receitas, public.caixa;
