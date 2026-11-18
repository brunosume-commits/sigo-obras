-- =====================================================================
-- SIGO — Migração 005: documentos com vencimento
-- Rode DEPOIS da migração anterior (só aditiva).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Documentos com vencimento (ASO, NRs, contratos de terceirizados…)
--    Ver: Engenheiro e Mestre de Obras. Cadastrar/alterar: Engenheiro.
-- ---------------------------------------------------------------------
create table if not exists public.documentos (
  id             uuid primary key default gen_random_uuid(),
  funcionario_id uuid references public.funcionarios(id) on delete cascade,
  empresa        text not null default '',
  tipo           text not null,
  descricao      text not null default '',
  emissao        date,
  validade       date,
  arquivo        text,
  criado_por     uuid references auth.users(id) default auth.uid(),
  criado_em      timestamptz not null default now(),
  check (funcionario_id is not null or empresa <> '')
);
create index if not exists documentos_validade_idx on public.documentos (validade);
alter table public.documentos enable row level security;
create policy leitura on public.documentos for select to authenticated using (public.tem_perfil('Engenheiro', 'Mestre de Obras'));
create policy escrita on public.documentos for all to authenticated
  using (public.tem_perfil('Engenheiro')) with check (public.tem_perfil('Engenheiro'));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('documentos', 'documentos', false, 10485760, array['application/pdf', 'image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;
create policy "documentos: ler" on storage.objects for select to authenticated
  using (bucket_id = 'documentos' and public.tem_perfil('Engenheiro', 'Mestre de Obras'));
create policy "documentos: enviar" on storage.objects for insert to authenticated
  with check (bucket_id = 'documentos' and public.tem_perfil('Engenheiro'));
create policy "documentos: apagar" on storage.objects for delete to authenticated
  using (bucket_id = 'documentos' and public.tem_perfil('Engenheiro'));

alter publication supabase_realtime add table public.documentos;
