-- =====================================================================
-- SIGO — Migração 017: avisos do dia
-- Rode DEPOIS da migração 016.
-- resumo_alertas(): tudo que precisa de atenção hoje (Engenheiro ou o
-- envio automático). O e-mail diário é feito pela Edge Function
-- "alertas-diarios", chamada pelo agendador (pg_cron) às 06:47.
-- =====================================================================

-- Formatação brasileira independente do idioma do servidor
create or replace function public.fmt_brl(v numeric) returns text language sql immutable as $$
  select 'R$ ' || translate(to_char(coalesce(v, 0), 'FM999,999,999,990.00'), ',.', '.,')
$$;
create or replace function public.fmt_num(v numeric) returns text language sql immutable as $$
  select replace(rtrim(rtrim(to_char(coalesce(v, 0), 'FM999999999990.999'), '0'), '.'), '.', ',')
$$;

create or replace function public.resumo_alertas()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  r jsonb := '[]'::jsonb;
  x record;
  v_ini numeric; v_base date; v_saldo numeric; v_neg date; v_corr numeric;
begin
  if not (coalesce(auth.role(), '') = 'service_role' or tem_perfil('Engenheiro')) then raise exception 'Sem permissão.'; end if;

  -- Caixa: saldo atual e primeiro dia negativo previsto em 90 dias
  select coalesce(saldo_inicial, 0), coalesce(data_saldo, hoje) into v_ini, v_base from caixa where id = 1;
  v_ini := coalesce(v_ini, 0); v_base := coalesce(v_base, hoje);
  v_saldo := v_ini
    + coalesce((select sum(valor) from receitas where status = 'Recebido' and coalesce(recebido_em, vencimento) >= v_base), 0)
    - coalesce((select sum(valor) from despesas where status = 'Pago' and coalesce(pago_em, vencimento, criado_em::date) >= v_base), 0);
  v_corr := v_saldo;
  for x in
    select greatest(d, hoje) as d, sum(v) as v from (
      select vencimento d, valor v from receitas where status = 'A receber'
      union all select coalesce(vencimento, hoje), -valor from despesas where status = 'A pagar') t
    where greatest(d, hoje) <= hoje + 90 group by 1 order by 1
  loop
    v_corr := v_corr + x.v;
    if v_corr < 0 and v_neg is null then v_neg := x.d; end if;
  end loop;
  if v_neg is not null and exists (select 1 from caixa where saldo_inicial <> 0) then
    r := r || jsonb_build_object('grupo', 'Caixa', 'grav', 'alta', 'texto', 'O caixa fica negativo em ' || to_char(v_neg, 'DD/MM/YYYY') || ' pelo previsto. Saldo hoje: ' || fmt_brl(v_saldo));
  end if;

  -- Contas a pagar vencidas e dos próximos 7 dias
  for x in select d.descricao, d.valor, d.vencimento, o.nome obra from despesas d join obras o on o.id = d.obra_id
           where d.status = 'A pagar' and d.vencimento <= hoje + 7 order by d.vencimento limit 15 loop
    r := r || jsonb_build_object('grupo', 'Contas a pagar', 'grav', case when x.vencimento < hoje then 'alta' else 'media' end,
      'texto', (case when x.vencimento < hoje then 'VENCIDA ' when x.vencimento = hoje then 'HOJE ' else '' end) || to_char(x.vencimento, 'DD/MM') || ' — ' || x.descricao || ' — ' || fmt_brl(x.valor) || ' (' || x.obra || ')');
  end loop;
  -- Recebimentos atrasados
  for x in select descricao, valor, vencimento from receitas where status = 'A receber' and vencimento < hoje order by vencimento limit 10 loop
    r := r || jsonb_build_object('grupo', 'Recebimentos atrasados', 'grav', 'alta', 'texto', to_char(x.vencimento, 'DD/MM') || ' — ' || x.descricao || ' — ' || fmt_brl(x.valor));
  end loop;
  -- Documentos vencidos ou vencendo em 30 dias
  for x in select dc.tipo, dc.validade, coalesce(f.nome, dc.empresa) quem from documentos dc left join funcionarios f on f.id = dc.funcionario_id
           where dc.validade is not null and dc.validade <= hoje + 30 order by dc.validade limit 15 loop
    r := r || jsonb_build_object('grupo', 'Documentos', 'grav', case when x.validade < hoje then 'alta' else 'media' end,
      'texto', (case when x.validade < hoje then 'VENCIDO ' else 'vence ' end) || to_char(x.validade, 'DD/MM/YYYY') || ' — ' || x.tipo || ' — ' || x.quem);
  end loop;
  -- Pendências com prazo vencido
  for x in select p.titulo, p.prazo, p.responsavel, o.nome obra from pendencias p join obras o on o.id = p.obra_id
           where p.status <> 'Resolvida' and p.prazo < hoje order by p.prazo limit 15 loop
    r := r || jsonb_build_object('grupo', 'Pendências atrasadas', 'grav', 'media',
      'texto', to_char(x.prazo, 'DD/MM') || ' — ' || x.titulo || ' — ' || coalesce(nullif(x.responsavel, ''), 'sem responsável') || ' (' || x.obra || ')');
  end loop;
  -- Estoque abaixo do mínimo
  for x in select m.nome, m.unidade, e.saldo, m.estoque_minimo, o.nome obra from estoques e join materiais m on m.id = e.material_id join obras o on o.id = e.obra_id
           where o.status <> 'Concluída' and m.estoque_minimo > 0 and e.saldo <= m.estoque_minimo order by e.saldo / nullif(m.estoque_minimo, 0) limit 15 loop
    r := r || jsonb_build_object('grupo', 'Estoque baixo', 'grav', case when x.saldo <= 0 then 'alta' else 'media' end,
      'texto', x.nome || ': ' || fmt_num(x.saldo) || ' ' || x.unidade || ' (mínimo ' || fmt_num(x.estoque_minimo) || ') — ' || x.obra);
  end loop;
  -- Troca de EPI vencida ou nos próximos 7 dias (última entrega de cada EPI por funcionário)
  for x in select f.nome func, m.nome epi, e.troca_prevista from (
             select distinct on (funcionario_id, material_id) * from epi_entregas order by funcionario_id, material_id, dia desc, criado_em desc) e
           join funcionarios f on f.id = e.funcionario_id join materiais m on m.id = e.material_id
           where e.troca_prevista is not null and e.troca_prevista <= hoje + 7 order by e.troca_prevista limit 15 loop
    r := r || jsonb_build_object('grupo', 'Troca de EPI', 'grav', 'media', 'texto', to_char(x.troca_prevista, 'DD/MM') || ' — ' || x.epi || ' — ' || x.func);
  end loop;
  -- Etapas atrasadas (mais de 10 pontos atrás do previsto pela data)
  for x in select e.nome, e.avanco, o.nome obra,
             case when hoje < e.inicio then 0 when hoje >= e.fim then 100 else (hoje - e.inicio + 1)::numeric / (e.fim - e.inicio + 1) * 100 end prev
           from etapas e join obras o on o.id = e.obra_id
           where e.inicio is not null and e.fim is not null and e.avanco < 100 and o.status = 'Em andamento' loop
    if x.prev - x.avanco > 10 then
      r := r || jsonb_build_object('grupo', 'Cronograma', 'grav', 'media', 'texto', x.nome || ' — ' || round(x.avanco) || '% feito, deveria estar em ' || round(x.prev) || '% (' || x.obra || ')');
    end if;
  end loop;
  -- Perda de material acima da tolerância nos últimos 30 dias
  for x in select o.nome obra, m.nome mat, a.previsto, a.realizado, a.tolerancia from obras o
           cross join lateral analise_consumo(o.id, hoje - 30, hoje) a join materiais m on m.id = a.material_id
           where o.status = 'Em andamento' and a.previsto > 0 and (a.realizado - a.previsto) / a.previsto * 100 > a.tolerancia loop
    r := r || jsonb_build_object('grupo', 'Perda de material (30 dias)', 'grav', 'media',
      'texto', x.mat || ': perda de ' || fmt_num(round((x.realizado - x.previsto) / x.previsto * 100, 1)) || '% (tolerância ' || round(x.tolerancia) || '%) — ' || x.obra);
  end loop;
  -- Aprovações esperando o Engenheiro
  for x in select count(*) n from compras where status = 'Solicitado' loop
    if x.n > 0 then r := r || jsonb_build_object('grupo', 'Esperando sua aprovação', 'grav', 'baixa', 'texto', x.n || ' pedido(s) de compra'); end if;
  end loop;
  for x in select count(*) n from cotacoes where status = 'Aberta' and exists (select 1 from cotacao_precos p join cotacao_itens i on i.id = p.item_id where i.cotacao_id = cotacoes.id) loop
    if x.n > 0 then r := r || jsonb_build_object('grupo', 'Esperando sua aprovação', 'grav', 'baixa', 'texto', x.n || ' cotação(ões) com preços lançados'); end if;
  end loop;
  for x in select count(*) n from medicoes where status = 'Rascunho' loop
    if x.n > 0 then r := r || jsonb_build_object('grupo', 'Esperando sua aprovação', 'grav', 'baixa', 'texto', x.n || ' medição(ões) de empreiteiro em rascunho'); end if;
  end loop;

  return jsonb_build_object('dia', hoje, 'saldo_caixa', round(v_saldo, 2), 'itens', r);
end $$;
revoke all on function public.resumo_alertas() from public, anon;
grant execute on function public.resumo_alertas() to authenticated, service_role;

-- Registro dos envios (um por dia) — só a Edge Function (service_role) mexe
create table if not exists public.envios_alertas (
  dia           date primary key,
  enviado_em    timestamptz not null default now(),
  destinatarios text[] not null default '{}',
  itens         int not null default 0,
  erro          text
);
alter table public.envios_alertas enable row level security;
create policy leitura on public.envios_alertas for select to authenticated using (public.tem_perfil('Engenheiro'));

-- E-mails dos administradores (para a Edge Function)
create or replace function public.emails_administradores()
returns text[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(a.email), '{}') from public.administradores a
  join public.perfis p on lower(p.email) = lower(a.email) and p.ativo
$$;
revoke all on function public.emails_administradores() from public, anon, authenticated;
grant execute on function public.emails_administradores() to service_role;

-- Agendamento: todo dia às 09:47 UTC = 06:47 em Brasília
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;
select cron.unschedule(jobid) from cron.job where jobname = 'sigo-alertas-diarios';
select cron.schedule('sigo-alertas-diarios', '47 9 * * *', $cron$
  select net.http_post(
    url := 'https://jaigqruhrslgttzqbmom.supabase.co/functions/v1/alertas-diarios',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImphaWdxcnVocnNsZ3R0enFibW9tIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQ1MDk1NDIsImV4cCI6MjExMDA4NTU0Mn0.-ixqR8w68yJP34zDy32jtHWcRyVR699CFLgUU6DH7BM'),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000)
$cron$);
