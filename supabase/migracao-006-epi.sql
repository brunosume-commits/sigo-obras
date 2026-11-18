-- =====================================================================
-- SIGO — Migração 006: controle de EPI
-- Rode DEPOIS da migração anterior (só aditiva).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 2. Controle de EPI: a entrega dá baixa no estoque da obra (Saída)
--    Registrar: Engenheiro, Almoxarife e Mestre. Cancelar: Engenheiro e Almoxarife.
-- ---------------------------------------------------------------------
create table if not exists public.epi_entregas (
  id              uuid primary key default gen_random_uuid(),
  funcionario_id  uuid not null references public.funcionarios(id) on delete restrict,
  material_id     uuid not null references public.materiais(id) on delete restrict,
  obra_id         uuid not null references public.obras(id) on delete restrict,
  qtd             numeric(14,3) not null check (qtd > 0),
  dia             date not null default (now() at time zone 'America/Sao_Paulo')::date,
  ca              text not null default '',
  troca_prevista  date,
  movimentacao_id uuid references public.movimentacoes(id),
  entregue_por    text,
  criado_por      uuid references auth.users(id) default auth.uid(),
  criado_em       timestamptz not null default now()
);
alter table public.epi_entregas enable row level security;
create policy leitura on public.epi_entregas for select to authenticated using (public.meu_perfil() is not null);

create or replace function public.entregar_epi(
  p_funcionario uuid, p_material uuid, p_obra uuid, p_qtd numeric, p_ca text default '', p_troca date default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_nome text; v_mov uuid; v_id uuid; v_quem text;
begin
  if not tem_perfil('Engenheiro', 'Almoxarife', 'Mestre de Obras') then raise exception 'Sem permissão.'; end if;
  if coalesce(p_qtd, 0) <= 0 then raise exception 'Informe uma quantidade maior que zero.'; end if;
  select nome into v_nome from funcionarios where id = p_funcionario;
  if v_nome is null then raise exception 'Funcionário não encontrado.'; end if;
  select nome into v_quem from perfis where id = auth.uid();
  perform _somar_estoque(p_material, p_obra, -p_qtd);
  insert into movimentacoes (tipo, obra_id, material_id, qtd, responsavel, obs, criado_por)
  values ('Saída', p_obra, p_material, p_qtd, v_nome, 'Entrega de EPI' || case when coalesce(p_ca, '') <> '' then ' (CA ' || p_ca || ')' else '' end, auth.uid())
  returning id into v_mov;
  insert into epi_entregas (funcionario_id, material_id, obra_id, qtd, ca, troca_prevista, movimentacao_id, entregue_por)
  values (p_funcionario, p_material, p_obra, p_qtd, coalesce(p_ca, ''), p_troca, v_mov, v_quem)
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.cancelar_entrega_epi(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare e epi_entregas%rowtype;
begin
  if not tem_perfil('Engenheiro', 'Almoxarife') then raise exception 'Sem permissão.'; end if;
  select * into e from epi_entregas where id = p_id for update;
  if not found then raise exception 'Entrega não encontrada.'; end if;
  if e.movimentacao_id is not null and exists (select 1 from movimentacoes where id = e.movimentacao_id and not estornada) then
    perform estornar_movimentacao(e.movimentacao_id);
  end if;
  delete from epi_entregas where id = p_id;
end $$;

revoke all on function public.entregar_epi(uuid, uuid, uuid, numeric, text, date) from public, anon;
revoke all on function public.cancelar_entrega_epi(uuid) from public, anon;
grant execute on function public.entregar_epi(uuid, uuid, uuid, numeric, text, date) to authenticated;
grant execute on function public.cancelar_entrega_epi(uuid) to authenticated;

alter publication supabase_realtime add table public.epi_entregas;
