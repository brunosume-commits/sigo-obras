-- =====================================================================
-- SIGO — Migração 012: qualidade (FVS/FVM) e pendências
-- Rode DEPOIS da migração 011 (só aditiva).
-- Todos os perfis registram inspeções e pendências; só o Engenheiro
-- exclui e cuida dos modelos de checklist.
-- =====================================================================

create table if not exists public.checklist_modelos (
  id        uuid primary key default gen_random_uuid(),
  nome      text not null,
  tipo      text not null default 'FVS' check (tipo in ('FVS', 'FVM')),
  itens     jsonb not null default '[]'::jsonb,
  ativo     boolean not null default true,
  criado_em timestamptz not null default now()
);
create table if not exists public.inspecoes (
  id          uuid primary key default gen_random_uuid(),
  obra_id     uuid not null references public.obras(id) on delete restrict,
  modelo_id   uuid references public.checklist_modelos(id) on delete set null,
  nome        text not null,
  tipo        text not null default 'FVS' check (tipo in ('FVS', 'FVM')),
  local       text not null default '',
  etapa_id    uuid references public.etapas(id) on delete set null,
  dia         date not null default (now() at time zone 'America/Sao_Paulo')::date,
  responsavel text,
  obs         text not null default '',
  criado_por  uuid references auth.users(id) default auth.uid(),
  criado_em   timestamptz not null default now()
);
create table if not exists public.inspecao_itens (
  inspecao_id uuid not null references public.inspecoes(id) on delete cascade,
  ordem       int not null,
  descricao   text not null,
  resultado   text check (resultado in ('Conforme', 'Não conforme', 'N/A')),
  obs         text not null default '',
  primary key (inspecao_id, ordem)
);
create table if not exists public.pendencias (
  id            uuid primary key default gen_random_uuid(),
  obra_id       uuid not null references public.obras(id) on delete restrict,
  titulo        text not null,
  descricao     text not null default '',
  local         text not null default '',
  responsavel   text not null default '',
  prazo         date,
  prioridade    text not null default 'Média' check (prioridade in ('Baixa', 'Média', 'Alta')),
  status        text not null default 'Aberta' check (status in ('Aberta', 'Em andamento', 'Resolvida')),
  inspecao_id   uuid references public.inspecoes(id) on delete set null,
  item_ordem    int,
  aberta_por    text,
  criado_em     timestamptz not null default now(),
  resolvida_em  timestamptz,
  resolvida_por text,
  unique (inspecao_id, item_ordem)
);
create index if not exists pendencias_obra_idx on public.pendencias (obra_id, status);

alter table public.checklist_modelos enable row level security;
alter table public.inspecoes         enable row level security;
alter table public.inspecao_itens    enable row level security;
alter table public.pendencias        enable row level security;

create policy leitura on public.checklist_modelos for select to authenticated using (public.meu_perfil() is not null);
create policy gerir on public.checklist_modelos for all to authenticated
  using (public.tem_perfil('Engenheiro')) with check (public.tem_perfil('Engenheiro'));

create policy leitura on public.inspecoes for select to authenticated using (public.meu_perfil() is not null);
create policy criar on public.inspecoes for insert to authenticated with check (public.meu_perfil() is not null);
create policy editar on public.inspecoes for update to authenticated using (public.meu_perfil() is not null) with check (public.meu_perfil() is not null);
create policy excluir on public.inspecoes for delete to authenticated using (public.tem_perfil('Engenheiro'));

create policy leitura on public.inspecao_itens for select to authenticated using (public.meu_perfil() is not null);
create policy escrever on public.inspecao_itens for all to authenticated using (public.meu_perfil() is not null) with check (public.meu_perfil() is not null);

create policy leitura on public.pendencias for select to authenticated using (public.meu_perfil() is not null);
create policy criar on public.pendencias for insert to authenticated with check (public.meu_perfil() is not null);
create policy editar on public.pendencias for update to authenticated using (public.meu_perfil() is not null) with check (public.meu_perfil() is not null);
create policy excluir on public.pendencias for delete to authenticated using (public.tem_perfil('Engenheiro'));

-- Modelos de checklist prontos para começar (o Engenheiro pode editar)
insert into public.checklist_modelos (nome, tipo, itens)
select * from (values
  ('Alvenaria de vedação', 'FVS', '["Marcação da primeira fiada conforme projeto","Prumo e nível das fiadas","Juntas preenchidas e com espessura de 10 mm (±3)","Amarração com a estrutura (tela ou ferro-cabelo)","Vergas e contravergas executadas","Encunhamento feito após 15 dias","Limpeza do pavimento"]'::jsonb),
  ('Armação (antes da concretagem)', 'FVS', '["Bitolas e quantidades conforme projeto","Espaçamento dos estribos","Espaçadores (cobrimento) instalados","Emendas e transpasses corretos","Armadura limpa, sem ferrugem solta","Arranques dos pilares posicionados"]'::jsonb),
  ('Formas e escoramento', 'FVS', '["Dimensões e prumo das formas","Estanqueidade (sem frestas)","Desmoldante aplicado","Escoras alinhadas, travadas e no espaçamento","Contraflecha das vigas conferida","Passagens de instalações previstas"]'::jsonb),
  ('Concretagem', 'FVS', '["Nota fiscal confere com o pedido (fck, slump, volume)","Slump test dentro do especificado","Corpos de prova moldados","Lançamento e adensamento sem segregação","Cura iniciada no mesmo dia","Horário de saída da usina x chegada (< 2h30)"]'::jsonb),
  ('Recebimento de cimento', 'FVM', '["Tipo e marca conforme pedido","Sacos íntegros, sem empedramento","Data de fabricação (validade 90 dias)","Quantidade confere com a nota","Armazenado sobre estrado, máx. 10 sacos de altura"]'::jsonb),
  ('Recebimento de aço', 'FVM', '["Bitola e categoria conforme pedido","Barras sem ferrugem excessiva","Etiqueta/certificado do fabricante","Peso ou quantidade confere com a nota","Armazenado sobre caibros, separado por bitola"]'::jsonb),
  ('Recebimento de blocos cerâmicos', 'FVM', '["Dimensões conforme pedido (amostra de 13 blocos)","Sem trincas, quebras ou empenamento","Quantidade confere com a nota","Descarga e empilhamento corretos"]'::jsonb)
) v(nome, tipo, itens)
where not exists (select 1 from public.checklist_modelos);

alter publication supabase_realtime add table public.checklist_modelos, public.inspecoes, public.inspecao_itens, public.pendencias;
