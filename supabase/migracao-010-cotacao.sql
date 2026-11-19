-- =====================================================================
-- SIGO — Migração 010: cotação com fornecedores (mapa de cotação) e aprovação
-- Rode DEPOIS da migração 009 (só aditiva).
-- Montar e preencher a cotação: Engenheiro e Almoxarife.
-- Aprovar (gera as compras com o fornecedor escolhido em cada item): só Engenheiro.
-- =====================================================================

create table if not exists public.cotacoes (
  id           uuid primary key default gen_random_uuid(),
  obra_id      uuid not null references public.obras(id) on delete restrict,
  titulo       text not null,
  status       text not null default 'Aberta' check (status in ('Aberta', 'Aprovada', 'Cancelada')),
  obs          text not null default '',
  solicitante  text,
  criado_em    timestamptz not null default now(),
  aprovada_em  timestamptz,
  aprovada_por text
);
create table if not exists public.cotacao_itens (
  id          uuid primary key default gen_random_uuid(),
  cotacao_id  uuid not null references public.cotacoes(id) on delete cascade,
  material_id uuid not null references public.materiais(id) on delete restrict,
  qtd         numeric(14,3) not null check (qtd > 0),
  ordem       int not null default 0
);
create table if not exists public.cotacao_fornecedores (
  cotacao_id    uuid not null references public.cotacoes(id) on delete cascade,
  fornecedor_id uuid not null references public.fornecedores(id) on delete restrict,
  prazo_entrega date,
  condicao      text not null default '',
  primary key (cotacao_id, fornecedor_id)
);
create table if not exists public.cotacao_precos (
  item_id       uuid not null references public.cotacao_itens(id) on delete cascade,
  fornecedor_id uuid not null references public.fornecedores(id) on delete restrict,
  preco_unit    numeric(14,2) not null check (preco_unit >= 0),
  primary key (item_id, fornecedor_id)
);

alter table public.cotacoes             enable row level security;
alter table public.cotacao_itens        enable row level security;
alter table public.cotacao_fornecedores enable row level security;
alter table public.cotacao_precos       enable row level security;

create policy gerir on public.cotacoes for all to authenticated
  using (public.tem_perfil('Engenheiro', 'Almoxarife'))
  with check (public.tem_perfil('Engenheiro', 'Almoxarife') and status <> 'Aprovada');
create policy gerir on public.cotacao_itens for all to authenticated
  using (public.tem_perfil('Engenheiro', 'Almoxarife'))
  with check (public.tem_perfil('Engenheiro', 'Almoxarife') and exists (select 1 from public.cotacoes c where c.id = cotacao_id and c.status = 'Aberta'));
create policy gerir on public.cotacao_fornecedores for all to authenticated
  using (public.tem_perfil('Engenheiro', 'Almoxarife'))
  with check (public.tem_perfil('Engenheiro', 'Almoxarife') and exists (select 1 from public.cotacoes c where c.id = cotacao_id and c.status = 'Aberta'));
create policy gerir on public.cotacao_precos for all to authenticated
  using (public.tem_perfil('Engenheiro', 'Almoxarife'))
  with check (public.tem_perfil('Engenheiro', 'Almoxarife') and exists (
    select 1 from public.cotacao_itens i join public.cotacoes c on c.id = i.cotacao_id where i.id = item_id and c.status = 'Aberta'));

-- p_escolhas: {"<item_id>": "<fornecedor_id>", ...}. Item sem escolha fica com o menor preço.
create or replace function public.aprovar_cotacao(p_id uuid, p_escolhas jsonb default '{}'::jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare c cotacoes%rowtype; it record; v_forn uuid; v_preco numeric; v_prazo date; v_nome text; n int := 0;
begin
  if not tem_perfil('Engenheiro') then raise exception 'Só o Engenheiro aprova cotações.'; end if;
  select * into c from cotacoes where id = p_id for update;
  if not found then raise exception 'Cotação não encontrada.'; end if;
  if c.status <> 'Aberta' then raise exception 'Esta cotação já está %.', lower(c.status); end if;
  select nome into v_nome from perfis where id = auth.uid();

  for it in select * from cotacao_itens where cotacao_id = p_id order by ordem loop
    v_forn := nullif(p_escolhas->>(it.id::text), '')::uuid;
    if v_forn is null then
      select fornecedor_id into v_forn from cotacao_precos where item_id = it.id order by preco_unit, fornecedor_id limit 1;
    end if;
    select preco_unit into v_preco from cotacao_precos where item_id = it.id and fornecedor_id = v_forn;
    if v_preco is null then
      raise exception 'O item "%" está sem preço do fornecedor escolhido.', (select nome from materiais where id = it.material_id);
    end if;
    select prazo_entrega into v_prazo from cotacao_fornecedores where cotacao_id = p_id and fornecedor_id = v_forn;
    insert into compras (obra_id, material_id, fornecedor_id, qtd, preco_unit, entrega, status, solicitante)
    values (c.obra_id, it.material_id, v_forn, it.qtd, v_preco, v_prazo, 'Comprado', coalesce(c.solicitante, v_nome));
    n := n + 1;
  end loop;
  if n = 0 then raise exception 'A cotação não tem itens.'; end if;

  update cotacoes set status = 'Aprovada', aprovada_em = now(), aprovada_por = v_nome where id = p_id;
  return n;
end $$;
revoke all on function public.aprovar_cotacao(uuid, jsonb) from public, anon;
grant execute on function public.aprovar_cotacao(uuid, jsonb) to authenticated;

alter publication supabase_realtime add table public.cotacoes, public.cotacao_itens, public.cotacao_fornecedores, public.cotacao_precos;
