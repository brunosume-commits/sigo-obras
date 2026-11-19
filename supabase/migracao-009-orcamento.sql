-- =====================================================================
-- SIGO — Migração 009: orçamento por etapas e cronograma físico-financeiro
-- Rode DEPOIS da migração 008 (só aditiva).
--
-- etapas        → cronograma (datas e avanço físico). Engenheiro e Mestre leem;
--                 só o Engenheiro cria/edita; o avanço é atualizado por atualizar_avanco().
-- etapa_itens   → valores do orçamento (só Engenheiro).
-- avanco_historico → cada atualização do avanço físico (para a curva S).
-- despesas.etapa_id e contratos.etapa_id → ligam o custo realizado à etapa.
-- =====================================================================

create table if not exists public.etapas (
  id         uuid primary key default gen_random_uuid(),
  obra_id    uuid not null references public.obras(id) on delete restrict,
  ordem      int not null default 0,
  nome       text not null,
  inicio     date,
  fim        date,
  avanco     numeric(5,2) not null default 0 check (avanco between 0 and 100),
  avanco_em  timestamptz,
  avanco_por text,
  criado_em  timestamptz not null default now(),
  check (fim is null or inicio is null or fim >= inicio)
);
create index if not exists etapas_obra_idx on public.etapas (obra_id, ordem);

create table if not exists public.etapa_itens (
  id          uuid primary key default gen_random_uuid(),
  etapa_id    uuid not null references public.etapas(id) on delete cascade,
  descricao   text not null,
  unidade     text not null default 'vb',
  qtd         numeric(14,3) not null default 1 check (qtd >= 0),
  preco_unit  numeric(14,2) not null default 0 check (preco_unit >= 0),
  ordem       int not null default 0
);

create table if not exists public.avanco_historico (
  id        uuid primary key default gen_random_uuid(),
  etapa_id  uuid not null references public.etapas(id) on delete cascade,
  dia       date not null default (now() at time zone 'America/Sao_Paulo')::date,
  avanco    numeric(5,2) not null,
  por       text,
  criado_em timestamptz not null default now()
);

alter table public.despesas  add column if not exists etapa_id uuid references public.etapas(id) on delete set null;
alter table public.contratos add column if not exists etapa_id uuid references public.etapas(id) on delete set null;

alter table public.etapas           enable row level security;
alter table public.etapa_itens      enable row level security;
alter table public.avanco_historico enable row level security;

create policy leitura on public.etapas for select to authenticated using (public.tem_perfil('Engenheiro', 'Mestre de Obras'));
create policy escrita on public.etapas for all to authenticated
  using (public.tem_perfil('Engenheiro')) with check (public.tem_perfil('Engenheiro'));
create policy so_engenheiro on public.etapa_itens for all to authenticated
  using (public.tem_perfil('Engenheiro')) with check (public.tem_perfil('Engenheiro'));
create policy leitura on public.avanco_historico for select to authenticated using (public.tem_perfil('Engenheiro', 'Mestre de Obras'));

-- Avanço físico: Engenheiro e Mestre de Obras
create or replace function public.atualizar_avanco(p_etapa uuid, p_avanco numeric)
returns void language plpgsql security definer set search_path = public as $$
declare v_nome text;
begin
  if not tem_perfil('Engenheiro', 'Mestre de Obras') then raise exception 'Sem permissão.'; end if;
  if p_avanco is null or p_avanco < 0 or p_avanco > 100 then raise exception 'O avanço deve ficar entre 0 e 100%%.'; end if;
  select nome into v_nome from perfis where id = auth.uid();
  update etapas set avanco = round(p_avanco, 2), avanco_em = now(), avanco_por = v_nome where id = p_etapa;
  if not found then raise exception 'Etapa não encontrada.'; end if;
  -- um registro por etapa por dia (vale o último do dia)
  delete from avanco_historico where etapa_id = p_etapa and dia = (now() at time zone 'America/Sao_Paulo')::date;
  insert into avanco_historico (etapa_id, avanco, por) values (p_etapa, round(p_avanco, 2), v_nome);
end $$;
revoke all on function public.atualizar_avanco(uuid, numeric) from public, anon;
grant execute on function public.atualizar_avanco(uuid, numeric) to authenticated;

-- A medição aprovada passa a levar a etapa do contrato para a despesa
create or replace function public.aprovar_medicao(p_id uuid)
returns numeric language plpgsql security definer set search_path = public as $$
declare m medicoes%rowtype; c contratos%rowtype; v_bruto numeric; v_ret numeric; v_desp uuid; v_excesso text;
begin
  if not tem_perfil('Engenheiro') then raise exception 'Sem permissão.'; end if;
  select * into m from medicoes where id = p_id for update;
  if not found then raise exception 'Medição não encontrada.'; end if;
  if m.status <> 'Rascunho' then raise exception 'Esta medição já foi aprovada.'; end if;
  select * into c from contratos where id = m.contrato_id;

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

  insert into despesas (obra_id, descricao, categoria, valor, vencimento, status, etapa_id)
  values (c.obra_id, 'Medição nº ' || m.numero || ' — ' || c.empreiteiro ||
                     case when c.objeto <> '' then ' (' || c.objeto || ')' else '' end,
          'Mão de Obra', v_bruto - v_ret, m.periodo_fim + 10, 'A pagar', c.etapa_id)
  returning id into v_desp;

  update medicoes set status = 'Aprovada', valor_bruto = v_bruto, retencao = v_ret,
         valor_liquido = v_bruto - v_ret, despesa_id = v_desp, aprovada_em = now()
  where id = m.id;
  return v_bruto - v_ret;
end $$;

alter publication supabase_realtime add table public.etapas, public.etapa_itens, public.avanco_historico;
