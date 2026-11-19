-- =====================================================================
-- SIGO — Migração 016: produtividade (homem-hora por unidade produzida)
-- Rode DEPOIS da migração 015 (só aditiva).
-- Cada produção guarda quem fez e as horas; o serviço guarda a
-- produtividade de referência (Hh por unidade, ex.: TCPO/SINAPI).
-- =====================================================================

alter table public.producoes add column if not exists pessoas int not null default 1 check (pessoas > 0);
alter table public.producoes add column if not exists hh numeric(10,2) not null default 0 check (hh >= 0);
alter table public.servicos_producao add column if not exists rup_ref numeric(10,4) check (rup_ref is null or rup_ref > 0);

create table if not exists public.producao_funcionarios (
  producao_id    uuid not null references public.producoes(id) on delete cascade,
  funcionario_id uuid not null references public.funcionarios(id) on delete cascade,
  primary key (producao_id, funcionario_id)
);
alter table public.producao_funcionarios enable row level security;
create policy leitura on public.producao_funcionarios for select to authenticated using (public.tem_perfil('Engenheiro', 'Mestre de Obras'));
create policy escrever on public.producao_funcionarios for all to authenticated
  using (public.tem_perfil('Engenheiro', 'Mestre de Obras')) with check (public.tem_perfil('Engenheiro', 'Mestre de Obras'));

alter publication supabase_realtime add table public.producao_funcionarios;
