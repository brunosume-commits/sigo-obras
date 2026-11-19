-- =====================================================================
-- SIGO — Migração 021: Dados da construtora (cabeçalho dos documentos)
-- Uma linha só. A logo fica guardada como imagem pequena (data URL).
-- Todos os perfis leem (inclusive Cliente, para o cabeçalho dos documentos);
-- só o Engenheiro altera. Cada obra ganha o nº da ART para o RDO.
-- =====================================================================
create table if not exists public.empresa (
  id                  int primary key default 1 check (id = 1),
  razao_social        text not null default '',
  nome_fantasia       text not null default '',
  cnpj                text not null default '',
  endereco            text not null default '',
  cidade_uf           text not null default '',
  telefone            text not null default '',
  email               text not null default '',
  site                text not null default '',
  responsavel_tecnico text not null default '',
  registro_crea       text not null default '',
  logo                text not null default '' check (length(logo) <= 400000),
  atualizado_em       timestamptz not null default now()
);
insert into public.empresa (id) values (1) on conflict do nothing;

alter table public.empresa enable row level security;
create policy leitura on public.empresa for select to authenticated using (true);
create policy alterar on public.empresa for update to authenticated
  using (public.tem_perfil('Engenheiro')) with check (public.tem_perfil('Engenheiro'));

alter table public.obras add column if not exists art text not null default '';
