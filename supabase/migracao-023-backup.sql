-- =====================================================================
-- SIGO — Migração 023: Backup semanal automático
-- Todo domingo às 03:17 (Brasília) a Edge Function backup-semanal:
--   * exporta todas as tabelas do SIGO num arquivo .json.gz;
--   * guarda no Storage (bucket privado "backups", mantém os 12 últimos);
--   * envia o arquivo por e-mail aos administradores (fica guardado no Gmail).
-- As fotos e anexos continuam no Storage e não entram no arquivo.
-- =====================================================================
create or replace function public.exportar_backup()
returns jsonb language plpgsql security definer set search_path = public as $$
declare t record; r jsonb := '{}'::jsonb; v jsonb;
begin
  if coalesce(auth.role(), '') <> 'service_role' and current_user not in ('postgres', 'supabase_admin') then
    raise exception 'Sem permissão.';
  end if;
  for t in select table_name from information_schema.tables
           where table_schema = 'public' and table_type = 'BASE TABLE' order by table_name loop
    execute format('select coalesce(jsonb_agg(x), ''[]''::jsonb) from public.%I x', t.table_name) into v;
    r := r || jsonb_build_object(t.table_name, v);
  end loop;
  return jsonb_build_object('sistema', 'SIGO', 'gerado_em', now(), 'tabelas', r);
end $$;
revoke all on function public.exportar_backup() from public, anon, authenticated;
grant execute on function public.exportar_backup() to service_role;

create table if not exists public.backups (
  id          bigint generated always as identity primary key,
  feito_em    timestamptz not null default now(),
  arquivo     text,
  bytes       int,
  linhas      int,
  enviado_para text[],
  erro        text
);
alter table public.backups enable row level security;
create policy leitura on public.backups for select to authenticated using (public.tem_perfil('Engenheiro'));

insert into storage.buckets (id, name, public) values ('backups', 'backups', false) on conflict (id) do nothing;

select cron.schedule('sigo-backup-semanal', '17 6 * * 0', $cron$
  select net.http_post(
    url := 'https://jaigqruhrslgttzqbmom.supabase.co/functions/v1/backup-semanal',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImphaWdxcnVocnNsZ3R0enFibW9tIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQ1MDk1NDIsImV4cCI6MjExMDA4NTU0Mn0.-ixqR8w68yJP34zDy32jtHWcRyVR699CFLgUU6DH7BM'),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000)
$cron$);
