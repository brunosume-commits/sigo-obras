-- =====================================================================
-- SIGO — Sistema Integrado de Gestão de Obras
-- Esquema do banco (Supabase / PostgreSQL)
--
-- Como usar: no painel do Supabase, abra "SQL Editor", cole este arquivo
-- inteiro e clique em "Run". Pode ser executado uma única vez num projeto novo.
--
-- Segurança: cada tabela tem RLS (Row Level Security). O que cada perfil
-- pode ver e alterar é decidido AQUI no banco, não só na tela.
-- Estoque só muda pelas funções registrar_movimentacao, estornar_movimentacao
-- e receber_compra, que validam saldo e gravam tudo numa única transação.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Perfis de usuário
-- ---------------------------------------------------------------------
create table public.perfis (
  id      uuid primary key references auth.users(id) on delete cascade,
  nome    text not null,
  email   text,
  perfil  text not null default 'Mestre de Obras'
          check (perfil in ('Engenheiro', 'Almoxarife', 'Mestre de Obras')),
  ativo   boolean not null default true,
  criado_em timestamptz not null default now()
);

-- Perfil do usuário logado
create or replace function public.meu_perfil()
returns text language sql stable security definer set search_path = public as $$
  select perfil from public.perfis where id = auth.uid() and ativo
$$;

create or replace function public.tem_perfil(variadic perfis_permitidos text[])
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.meu_perfil() = any(perfis_permitidos), false)
$$;

-- E-mails que entram automaticamente como Engenheiro (administrador), já liberados.
-- Tabela sem políticas de RLS: invisível pela API do site.
-- Para cadastrar o seu: insert into public.administradores (email) values ('seu@email.com');
create table public.administradores (email text primary key);
alter table public.administradores enable row level security;
revoke all on public.administradores from anon, authenticated;

-- Cria o perfil automaticamente quando um usuário é cadastrado.
-- E-mail listado em "administradores" vira Engenheiro já liberado.
-- Se a lista estiver vazia, o PRIMEIRO usuário vira Engenheiro.
-- Os demais começam como Mestre de Obras, INATIVOS, até o Engenheiro
-- liberar e escolher o perfil na tela "Usuários".
create or replace function public.criar_perfil_novo_usuario()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_admin boolean; v_primeiro boolean;
begin
  perform pg_advisory_xact_lock(hashtext('sigo_primeiro_usuario'));
  v_admin := exists (select 1 from public.administradores where lower(email) = lower(new.email));
  v_primeiro := not exists (select 1 from public.perfis) and not exists (select 1 from public.administradores);
  insert into public.perfis (id, nome, email, perfil, ativo)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data->>'nome'), ''), split_part(new.email, '@', 1)),
    new.email,
    case when v_admin or v_primeiro then 'Engenheiro' else 'Mestre de Obras' end,
    v_admin or v_primeiro
  );
  return new;
end $$;
revoke all on function public.criar_perfil_novo_usuario() from public, anon, authenticated;

create trigger trg_criar_perfil
  after insert on auth.users
  for each row execute function public.criar_perfil_novo_usuario();

-- ---------------------------------------------------------------------
-- Cadastros
-- ---------------------------------------------------------------------
create table public.obras (
  id          uuid primary key default gen_random_uuid(),
  nome        text not null,
  endereco    text not null default '',
  responsavel text not null default '',
  inicio      date not null default current_date,
  previsao    date not null default current_date + 365,
  orcamento   numeric(14,2) not null default 0 check (orcamento >= 0),
  status      text not null default 'Em andamento'
              check (status in ('Em andamento', 'Paralisada', 'Concluída')),
  criado_em   timestamptz not null default now(),
  check (previsao >= inicio)
);

create table public.materiais (
  id             uuid primary key default gen_random_uuid(),
  codigo         text not null unique,
  nome           text not null,
  unidade        text not null default 'un',
  estoque_minimo numeric(14,3) not null default 0 check (estoque_minimo >= 0),
  criado_em      timestamptz not null default now()
);

create table public.fornecedores (
  id        uuid primary key default gen_random_uuid(),
  nome      text not null,
  contato   text not null default '',
  categoria text not null default '',
  criado_em timestamptz not null default now()
);

create table public.funcionarios (
  id        uuid primary key default gen_random_uuid(),
  nome      text not null,
  funcao    text not null default '',
  obra_id   uuid references public.obras(id) on delete restrict,
  presenca  text not null default 'Presente' check (presenca in ('Presente', 'Falta', 'Atestado')),
  criado_em timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Estoque e movimentações
-- ---------------------------------------------------------------------
create table public.estoques (
  material_id uuid not null references public.materiais(id) on delete cascade,
  obra_id     uuid not null references public.obras(id) on delete cascade,
  saldo       numeric(14,3) not null default 0 check (saldo >= 0),
  primary key (material_id, obra_id)
);

-- Não deixa excluir obra ou material que ainda tenha saldo
create or replace function public.bloquear_exclusao_com_saldo()
returns trigger language plpgsql set search_path = public as $$
begin
  if exists (select 1 from public.estoques where saldo > 0 and
             ((tg_table_name = 'obras' and obra_id = old.id) or (tg_table_name = 'materiais' and material_id = old.id))) then
    raise exception 'Não é possível excluir: ainda há saldo em estoque vinculado.';
  end if;
  return old;
end $$;
create trigger trg_saldo_obra before delete on public.obras for each row execute function public.bloquear_exclusao_com_saldo();
create trigger trg_saldo_material before delete on public.materiais for each row execute function public.bloquear_exclusao_com_saldo();

create table public.movimentacoes (
  id              uuid primary key default gen_random_uuid(),
  data            timestamptz not null default now(),
  tipo            text not null check (tipo in ('Entrada', 'Saída', 'Transferência', 'Estorno')),
  tipo_original   text,
  estorno_de      uuid references public.movimentacoes(id),
  estornada       boolean not null default false,
  obra_id         uuid not null references public.obras(id) on delete restrict,
  obra_destino_id uuid references public.obras(id) on delete restrict,
  material_id     uuid not null references public.materiais(id) on delete restrict,
  qtd             numeric(14,3) not null check (qtd > 0),
  responsavel     text not null,
  obs             text not null default '-',
  criado_por      uuid references auth.users(id)
);
create index on public.movimentacoes (data desc);

create table public.compras (
  id               uuid primary key default gen_random_uuid(),
  obra_id          uuid not null references public.obras(id) on delete restrict,
  material_id      uuid not null references public.materiais(id) on delete restrict,
  fornecedor_id    uuid references public.fornecedores(id) on delete restrict,
  qtd              numeric(14,3) not null check (qtd > 0),
  preco_unit       numeric(14,2) not null default 0 check (preco_unit >= 0),
  entrega          date,
  status           text not null default 'Solicitado'
                   check (status in ('Solicitado', 'Comprado', 'Entregue', 'Cancelado')),
  solicitante      text,
  data_solicitacao date not null default current_date,
  criado_por       uuid references auth.users(id) default auth.uid()
);

create table public.despesas (
  id         uuid primary key default gen_random_uuid(),
  compra_id  uuid references public.compras(id) on delete set null,
  obra_id    uuid not null references public.obras(id) on delete restrict,
  descricao  text not null,
  categoria  text not null default 'Outros',
  valor      numeric(14,2) not null check (valor > 0),
  vencimento date,
  status     text not null default 'A pagar' check (status in ('A pagar', 'Pago')),
  criado_em  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- RLS (quem pode ver / alterar o quê)
-- ---------------------------------------------------------------------
alter table public.perfis        enable row level security;
alter table public.obras         enable row level security;
alter table public.materiais     enable row level security;
alter table public.fornecedores  enable row level security;
alter table public.funcionarios  enable row level security;
alter table public.estoques      enable row level security;
alter table public.movimentacoes enable row level security;
alter table public.compras       enable row level security;
alter table public.despesas      enable row level security;

-- Leitura: qualquer usuário ativo (exceto despesas e perfis)
create policy leitura on public.obras         for select to authenticated using (public.meu_perfil() is not null);
create policy leitura on public.materiais     for select to authenticated using (public.meu_perfil() is not null);
create policy leitura on public.fornecedores  for select to authenticated using (public.meu_perfil() is not null);
create policy leitura on public.funcionarios  for select to authenticated using (public.meu_perfil() is not null);
create policy leitura on public.estoques      for select to authenticated using (public.meu_perfil() is not null);
create policy leitura on public.movimentacoes for select to authenticated using (public.meu_perfil() is not null);
create policy leitura on public.compras       for select to authenticated using (public.meu_perfil() is not null);

-- Perfis: cada um vê o próprio; o Engenheiro vê e altera todos
create policy leitura on public.perfis for select to authenticated
  using (id = auth.uid() or public.tem_perfil('Engenheiro'));
create policy alteracao on public.perfis for update to authenticated
  using (public.tem_perfil('Engenheiro'))
  with check (public.tem_perfil('Engenheiro'));

-- Obras: só Engenheiro altera
create policy escrita on public.obras for all to authenticated
  using (public.tem_perfil('Engenheiro')) with check (public.tem_perfil('Engenheiro'));

-- Materiais e fornecedores: Engenheiro e Almoxarife
create policy escrita on public.materiais for all to authenticated
  using (public.tem_perfil('Engenheiro', 'Almoxarife')) with check (public.tem_perfil('Engenheiro', 'Almoxarife'));
create policy escrita on public.fornecedores for all to authenticated
  using (public.tem_perfil('Engenheiro', 'Almoxarife')) with check (public.tem_perfil('Engenheiro', 'Almoxarife'));

-- Funcionários: Engenheiro cadastra/edita/exclui (presença pelo Mestre via função marcar_presenca)
create policy escrita on public.funcionarios for all to authenticated
  using (public.tem_perfil('Engenheiro')) with check (public.tem_perfil('Engenheiro'));

-- Compras: todos solicitam; Engenheiro e Almoxarife editam/cancelam.
-- Ninguém marca "Entregue" à mão — só pela função receber_compra.
create policy solicitar on public.compras for insert to authenticated
  with check (public.meu_perfil() is not null and status = 'Solicitado');
create policy editar on public.compras for update to authenticated
  using (public.tem_perfil('Engenheiro', 'Almoxarife') and status not in ('Entregue', 'Cancelado'))
  with check (public.tem_perfil('Engenheiro', 'Almoxarife') and status <> 'Entregue');

-- Despesas: só o Engenheiro vê e altera
create policy tudo on public.despesas for all to authenticated
  using (public.tem_perfil('Engenheiro')) with check (public.tem_perfil('Engenheiro'));

-- estoques e movimentacoes: sem política de escrita => só pelas funções abaixo.

-- ---------------------------------------------------------------------
-- Funções de estoque (transação única, validação de saldo e de perfil)
-- ---------------------------------------------------------------------
create or replace function public._somar_estoque(p_material uuid, p_obra uuid, p_qtd numeric)
returns void language plpgsql security definer set search_path = public as $$
declare v_saldo numeric;
begin
  insert into estoques (material_id, obra_id, saldo) values (p_material, p_obra, 0)
  on conflict do nothing;
  select saldo into v_saldo from estoques
   where material_id = p_material and obra_id = p_obra for update;
  if v_saldo + p_qtd < 0 then
    raise exception 'Saldo insuficiente na obra (disponível: %).', v_saldo;
  end if;
  update estoques set saldo = saldo + p_qtd
   where material_id = p_material and obra_id = p_obra;
end $$;
revoke all on function public._somar_estoque(uuid, uuid, numeric) from public, anon, authenticated;

create or replace function public.registrar_movimentacao(
  p_tipo text, p_obra uuid, p_obra_destino uuid, p_material uuid,
  p_qtd numeric, p_responsavel text, p_obs text default '-'
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if p_tipo = 'Saída' then
    if not tem_perfil('Engenheiro', 'Almoxarife', 'Mestre de Obras') then raise exception 'Sem permissão.'; end if;
  elsif p_tipo in ('Entrada', 'Transferência') then
    if not tem_perfil('Engenheiro', 'Almoxarife') then raise exception 'Sem permissão.'; end if;
  else
    raise exception 'Tipo de movimentação inválido.';
  end if;
  if coalesce(p_qtd, 0) <= 0 then raise exception 'Informe uma quantidade maior que zero.'; end if;
  if coalesce(trim(p_responsavel), '') = '' then raise exception 'Informe o responsável.'; end if;

  if p_tipo = 'Entrada' then
    perform _somar_estoque(p_material, p_obra, p_qtd);
  elsif p_tipo = 'Saída' then
    perform _somar_estoque(p_material, p_obra, -p_qtd);
  else
    if p_obra_destino is null or p_obra_destino = p_obra then
      raise exception 'A obra de destino deve ser diferente da obra de origem.';
    end if;
    perform _somar_estoque(p_material, p_obra, -p_qtd);
    perform _somar_estoque(p_material, p_obra_destino, p_qtd);
  end if;

  insert into movimentacoes (tipo, obra_id, obra_destino_id, material_id, qtd, responsavel, obs, criado_por)
  values (p_tipo, p_obra, case when p_tipo = 'Transferência' then p_obra_destino end,
          p_material, p_qtd, trim(p_responsavel), coalesce(nullif(trim(p_obs), ''), '-'), auth.uid())
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.estornar_movimentacao(p_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare m movimentacoes%rowtype; v_id uuid; v_nome text;
begin
  if not tem_perfil('Engenheiro', 'Almoxarife') then raise exception 'Sem permissão.'; end if;
  select * into m from movimentacoes where id = p_id for update;
  if not found then raise exception 'Movimentação não encontrada.'; end if;
  if m.tipo = 'Estorno' then raise exception 'Um estorno não pode ser estornado.'; end if;
  if m.estornada then raise exception 'Esta movimentação já foi estornada.'; end if;

  if m.tipo = 'Entrada' then
    perform _somar_estoque(m.material_id, m.obra_id, -m.qtd);
  elsif m.tipo = 'Saída' then
    perform _somar_estoque(m.material_id, m.obra_id, m.qtd);
  else
    perform _somar_estoque(m.material_id, m.obra_destino_id, -m.qtd);
    perform _somar_estoque(m.material_id, m.obra_id, m.qtd);
  end if;

  select nome into v_nome from perfis where id = auth.uid();
  update movimentacoes set estornada = true where id = p_id;
  insert into movimentacoes (tipo, tipo_original, estorno_de, obra_id, obra_destino_id, material_id, qtd, responsavel, obs, criado_por)
  values ('Estorno', m.tipo, m.id, m.obra_id, m.obra_destino_id, m.material_id, m.qtd, coalesce(v_nome, 'Sistema'),
          'Estorno de ' || lower(m.tipo) || ' de ' || to_char(m.data at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'),
          auth.uid())
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.receber_compra(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare c compras%rowtype; v_mat materiais%rowtype; v_nome text;
begin
  if not tem_perfil('Engenheiro', 'Almoxarife') then raise exception 'Sem permissão.'; end if;
  select * into c from compras where id = p_id for update;
  if not found then raise exception 'Compra não encontrada.'; end if;
  if c.status in ('Entregue', 'Cancelado') then raise exception 'Esta compra já está %.', lower(c.status); end if;

  select * into v_mat from materiais where id = c.material_id;
  select nome into v_nome from perfis where id = auth.uid();

  perform _somar_estoque(c.material_id, c.obra_id, c.qtd);
  insert into movimentacoes (tipo, obra_id, material_id, qtd, responsavel, obs, criado_por)
  values ('Entrada', c.obra_id, c.material_id, c.qtd, coalesce(v_nome, 'Sistema'),
          'Recebimento automático via Módulo de Compras', auth.uid());
  if c.qtd * c.preco_unit > 0 then
    insert into despesas (compra_id, obra_id, descricao, categoria, valor, vencimento, status)
    values (c.id, c.obra_id, 'Compra: ' || c.qtd || ' ' || v_mat.unidade || ' de ' || v_mat.nome,
            'Material', round(c.qtd * c.preco_unit, 2), coalesce(c.entrega, current_date), 'A pagar');
  end if;
  update compras set status = 'Entregue' where id = p_id;
end $$;

create or replace function public.marcar_presenca(p_funcionario uuid, p_presenca text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not tem_perfil('Engenheiro', 'Mestre de Obras') then raise exception 'Sem permissão.'; end if;
  update funcionarios set presenca = p_presenca where id = p_funcionario;
end $$;

-- Funções só para usuários logados
revoke all on function public.meu_perfil() from public, anon;
revoke all on function public.tem_perfil(text[]) from public, anon;
grant execute on function public.meu_perfil() to authenticated;
grant execute on function public.tem_perfil(text[]) to authenticated;
revoke all on function public.registrar_movimentacao(text, uuid, uuid, uuid, numeric, text, text) from public, anon;
revoke all on function public.estornar_movimentacao(uuid) from public, anon;
revoke all on function public.receber_compra(uuid) from public, anon;
revoke all on function public.marcar_presenca(uuid, text) from public, anon;
grant execute on function public.registrar_movimentacao(text, uuid, uuid, uuid, numeric, text, text) to authenticated;
grant execute on function public.estornar_movimentacao(uuid) to authenticated;
grant execute on function public.receber_compra(uuid) to authenticated;
grant execute on function public.marcar_presenca(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- Tempo real: avisa as telas abertas quando algo muda
-- ---------------------------------------------------------------------
alter publication supabase_realtime add table
  public.obras, public.materiais, public.fornecedores, public.funcionarios,
  public.estoques, public.movimentacoes, public.compras, public.despesas, public.perfis;
