-- =====================================================================
-- SIGO — Migração 008: envio dos lançamentos feitos sem internet
-- Rode DEPOIS da migração 007 (só aditiva).
--
-- O aparelho guarda cada lançamento feito offline com um id próprio e,
-- quando a internet volta, chama sincronizar_offline(). Esse id é gravado
-- na mesma transação do lançamento, então reenviar (por queda de conexão
-- no meio do envio) nunca duplica nada.
-- =====================================================================

create table if not exists public.sincronizacoes (
  id        uuid primary key,                       -- id gerado no aparelho
  usuario   uuid not null default auth.uid() references auth.users(id),
  tipo      text not null,
  feito_em  timestamptz not null default now()      -- quando chegou ao servidor
);
alter table public.sincronizacoes enable row level security;
create policy leitura_propria on public.sincronizacoes for select to authenticated using (usuario = auth.uid());

create or replace function public.sincronizar_offline(p_id uuid, p_tipo text, p_args jsonb, p_quando timestamptz)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_quando timestamptz := least(coalesce(p_quando, now()), now());
  v_dia    date := (least(coalesce(p_quando, now()), now()) at time zone 'America/Sao_Paulo')::date;
  v_id     uuid;
  d        diarios%rowtype;
begin
  if public.meu_perfil() is null then raise exception 'Sem permissão.'; end if;
  -- trava pelo id: dois envios simultâneos do mesmo lançamento esperam um pelo outro
  perform pg_advisory_xact_lock(hashtext(p_id::text));
  if exists (select 1 from sincronizacoes where id = p_id) then return 'já enviado'; end if;

  if p_tipo = 'movimentacao' then
    v_id := registrar_movimentacao(p_args->>'tipo', (p_args->>'obra')::uuid, nullif(p_args->>'obra_destino', '')::uuid,
                                   (p_args->>'material')::uuid, (p_args->>'qtd')::numeric,
                                   p_args->>'responsavel', coalesce(p_args->>'obs', '-'));
    update movimentacoes set data = v_quando where id = v_id;   -- mantém a hora em que foi feito na obra

  elsif p_tipo = 'presenca' then
    perform marcar_presenca((p_args->>'funcionario')::uuid, p_args->>'presenca', (p_args->>'dia')::date);

  elsif p_tipo = 'epi' then
    v_id := entregar_epi((p_args->>'funcionario')::uuid, (p_args->>'material')::uuid, (p_args->>'obra')::uuid,
                         (p_args->>'qtd')::numeric, coalesce(p_args->>'ca', ''), nullif(p_args->>'troca', '')::date);
    update epi_entregas set dia = v_dia where id = v_id;
    update movimentacoes set data = v_quando where id = (select movimentacao_id from epi_entregas where id = v_id);

  elsif p_tipo = 'diario' then
    if not tem_perfil('Engenheiro', 'Mestre de Obras') then raise exception 'Sem permissão.'; end if;
    select * into d from diarios where obra_id = (p_args->>'obra')::uuid and dia = (p_args->>'dia')::date for update;
    if found then
      -- alguém mexeu no diário pela internet depois que este texto foi escrito: não sobrescreve
      if d.atualizado_em > v_quando then
        raise exception 'O diário desse dia foi alterado por outra pessoa depois. Copie o seu texto e confira o diário antes de reenviar.';
      end if;
      update diarios set clima_manha = p_args->>'clima_manha', clima_tarde = p_args->>'clima_tarde',
             servicos = p_args->>'servicos', ocorrencias = p_args->>'ocorrencias', observacoes = p_args->>'observacoes',
             atualizado_em = v_quando
      where id = d.id;
    else
      if (p_args->>'dia')::date > (now() at time zone 'America/Sao_Paulo')::date then raise exception 'Não é possível registrar diário de data futura.'; end if;
      insert into diarios (obra_id, dia, clima_manha, clima_tarde, servicos, ocorrencias, observacoes, autor_nome, atualizado_em)
      values ((p_args->>'obra')::uuid, (p_args->>'dia')::date, p_args->>'clima_manha', p_args->>'clima_tarde',
              p_args->>'servicos', p_args->>'ocorrencias', p_args->>'observacoes',
              (select nome from perfis where id = auth.uid()), v_quando);
    end if;

  else
    raise exception 'Tipo de lançamento desconhecido: %', p_tipo;
  end if;

  insert into sincronizacoes (id, tipo) values (p_id, p_tipo);
  return 'ok';
end $$;

revoke all on function public.sincronizar_offline(uuid, text, jsonb, timestamptz) from public, anon;
grant execute on function public.sincronizar_offline(uuid, text, jsonb, timestamptz) to authenticated;
