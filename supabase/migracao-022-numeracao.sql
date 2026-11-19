-- =====================================================================
-- SIGO — Migração 022: Numeração oficial dos documentos
-- * Pedido de compra: PC-0001, PC-0002... (sequência única da construtora).
--   Ao emitir, os itens em aberto daquele fornecedor/obra ficam presos ao
--   pedido; um item novo depois gera outro pedido.
-- * RDO e inspeções (FVS/FVM): número sequencial por obra, gravado no
--   registro (não muda se um dia anterior for apagado).
-- =====================================================================
create table if not exists public.pedidos (
  id            uuid primary key default gen_random_uuid(),
  numero        int not null unique,
  obra_id       uuid not null references public.obras(id) on delete cascade,
  fornecedor_id uuid not null references public.fornecedores(id) on delete restrict,
  emitido_por   text,
  criado_em     timestamptz not null default now()
);
alter table public.compras add column if not exists pedido_id uuid references public.pedidos(id) on delete set null;
alter table public.pedidos enable row level security;
create policy leitura on public.pedidos for select to authenticated using (public.meu_perfil() is not null);

create or replace function public.emitir_pedido(p_obra uuid, p_forn uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_num int; v_nome text;
begin
  if not tem_perfil('Engenheiro', 'Almoxarife') then raise exception 'Sem permissão.'; end if;
  if not exists (select 1 from compras where obra_id = p_obra and fornecedor_id = p_forn
                 and status in ('Solicitado', 'Comprado') and pedido_id is null) then
    raise exception 'Não há itens em aberto sem pedido para este fornecedor nesta obra.';
  end if;
  perform pg_advisory_xact_lock(hashtext('sigo_pedidos'));
  select coalesce(max(numero), 0) + 1 into v_num from pedidos;
  select nome into v_nome from perfis where id = auth.uid();
  insert into pedidos (numero, obra_id, fornecedor_id, emitido_por) values (v_num, p_obra, p_forn, coalesce(v_nome, 'Sistema'))
  returning id into v_id;
  update compras set pedido_id = v_id
   where obra_id = p_obra and fornecedor_id = p_forn and status in ('Solicitado', 'Comprado') and pedido_id is null;
  return v_id;
end $$;
revoke all on function public.emitir_pedido(uuid, uuid) from public, anon;
grant execute on function public.emitir_pedido(uuid, uuid) to authenticated;

-- RDO e inspeções: número por obra
alter table public.diarios   add column if not exists numero int;
alter table public.inspecoes add column if not exists numero int;

with n as (select id, row_number() over (partition by obra_id order by dia, criado_em) r from diarios)
update diarios d set numero = n.r from n where n.id = d.id and d.numero is null;
with n as (select id, row_number() over (partition by obra_id order by dia, criado_em) r from inspecoes)
update inspecoes i set numero = n.r from n where n.id = i.id and i.numero is null;

create or replace function public._numerar_por_obra()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.numero is null then
    perform pg_advisory_xact_lock(hashtext(tg_table_name || new.obra_id::text));
    execute format('select coalesce(max(numero), 0) + 1 from %I where obra_id = $1', tg_table_name) into new.numero using new.obra_id;
  end if;
  return new;
end $$;
drop trigger if exists numerar on public.diarios;
create trigger numerar before insert on public.diarios for each row execute function public._numerar_por_obra();
drop trigger if exists numerar on public.inspecoes;
create trigger numerar before insert on public.inspecoes for each row execute function public._numerar_por_obra();

alter publication supabase_realtime add table public.pedidos;
