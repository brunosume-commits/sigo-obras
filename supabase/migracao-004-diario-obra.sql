-- =====================================================================
-- SIGO — Migração 004: Diário de Obra (RDO) com fotos
-- Rode no SQL Editor DEPOIS da migração 003 (só aditiva).
-- Quem escreve: Engenheiro e Mestre de Obras. Quem lê: todos os usuários ativos.
-- Fotos ficam no Storage do Supabase, no bucket privado "diario".
-- =====================================================================

create table if not exists public.diarios (
  id            uuid primary key default gen_random_uuid(),
  obra_id       uuid not null references public.obras(id) on delete restrict,
  dia           date not null,
  clima_manha   text not null default 'Bom' check (clima_manha in ('Bom', 'Nublado', 'Chuva', 'Impraticável')),
  clima_tarde   text not null default 'Bom' check (clima_tarde in ('Bom', 'Nublado', 'Chuva', 'Impraticável')),
  servicos      text not null default '',
  ocorrencias   text not null default '',
  observacoes   text not null default '',
  autor_nome    text,
  criado_por    uuid references auth.users(id) default auth.uid(),
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (obra_id, dia)
);
create index if not exists diarios_dia_idx on public.diarios (dia desc);

create table if not exists public.diario_fotos (
  id         uuid primary key default gen_random_uuid(),
  diario_id  uuid not null references public.diarios(id) on delete cascade,
  caminho    text not null unique,
  legenda    text not null default '',
  criado_por uuid references auth.users(id) default auth.uid(),
  criado_em  timestamptz not null default now()
);

alter table public.diarios      enable row level security;
alter table public.diario_fotos enable row level security;

create policy leitura on public.diarios for select to authenticated using (public.meu_perfil() is not null);
create policy criar on public.diarios for insert to authenticated
  with check (public.tem_perfil('Engenheiro', 'Mestre de Obras') and dia <= (now() at time zone 'America/Sao_Paulo')::date);
create policy editar on public.diarios for update to authenticated
  using (public.tem_perfil('Engenheiro', 'Mestre de Obras'))
  with check (public.tem_perfil('Engenheiro', 'Mestre de Obras'));
create policy excluir on public.diarios for delete to authenticated using (public.tem_perfil('Engenheiro'));

create policy leitura on public.diario_fotos for select to authenticated using (public.meu_perfil() is not null);
create policy criar on public.diario_fotos for insert to authenticated with check (public.tem_perfil('Engenheiro', 'Mestre de Obras'));
create policy editar on public.diario_fotos for update to authenticated
  using (public.tem_perfil('Engenheiro', 'Mestre de Obras')) with check (public.tem_perfil('Engenheiro', 'Mestre de Obras'));
create policy excluir on public.diario_fotos for delete to authenticated using (public.tem_perfil('Engenheiro', 'Mestre de Obras'));

-- Bucket privado para as fotos (até 5 MB por foto, só imagens)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('diario', 'diario', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy "diario fotos: ler" on storage.objects for select to authenticated
  using (bucket_id = 'diario' and public.meu_perfil() is not null);
create policy "diario fotos: enviar" on storage.objects for insert to authenticated
  with check (bucket_id = 'diario' and public.tem_perfil('Engenheiro', 'Mestre de Obras'));
create policy "diario fotos: apagar" on storage.objects for delete to authenticated
  using (bucket_id = 'diario' and public.tem_perfil('Engenheiro', 'Mestre de Obras'));

alter publication supabase_realtime add table public.diarios, public.diario_fotos;
