-- =====================================================================
-- SIGO — Migração 002: categorias de material e presença diária
-- Rode no SQL Editor DEPOIS do schema.sql (só aditiva: não apaga dados).
-- =====================================================================

-- Categoria de material
alter table public.materiais add column if not exists categoria text not null default 'Geral';

-- Presença por dia (histórico)
create table if not exists public.presencas (
  funcionario_id  uuid not null references public.funcionarios(id) on delete cascade,
  dia             date not null,
  status          text not null check (status in ('Presente', 'Falta', 'Atestado')),
  registrado_por  uuid references auth.users(id),
  registrado_em   timestamptz not null default now(),
  primary key (funcionario_id, dia)
);
create index if not exists presencas_dia_idx on public.presencas (dia);

alter table public.presencas enable row level security;
create policy leitura on public.presencas for select to authenticated
  using (public.meu_perfil() is not null);
-- Escrita só pela função marcar_presenca.

-- Nova versão de marcar_presenca, com a data do registro.
drop function if exists public.marcar_presenca(uuid, text);

create or replace function public.marcar_presenca(p_funcionario uuid, p_presenca text, p_dia date)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not tem_perfil('Engenheiro', 'Mestre de Obras') then raise exception 'Sem permissão.'; end if;
  if p_dia is null then raise exception 'Informe a data.'; end if;
  if p_dia > (now() at time zone 'America/Sao_Paulo')::date then
    raise exception 'Não é possível registrar presença em data futura.';
  end if;
  if p_presenca is null or p_presenca = '' then
    delete from presencas where funcionario_id = p_funcionario and dia = p_dia;
  else
    insert into presencas (funcionario_id, dia, status, registrado_por)
    values (p_funcionario, p_dia, p_presenca, auth.uid())
    on conflict (funcionario_id, dia)
    do update set status = excluded.status, registrado_por = excluded.registrado_por, registrado_em = now();
  end if;
  -- mantém o campo "presença de hoje" do cadastro em dia
  if p_dia = (now() at time zone 'America/Sao_Paulo')::date and coalesce(p_presenca, '') <> '' then
    update funcionarios set presenca = p_presenca where id = p_funcionario;
  end if;
end $$;

revoke all on function public.marcar_presenca(uuid, text, date) from public, anon;
grant execute on function public.marcar_presenca(uuid, text, date) to authenticated;

alter publication supabase_realtime add table public.presencas;
