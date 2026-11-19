-- =====================================================================
-- SIGO — Migração 013: portal do cliente
-- Rode DEPOIS da migração 012.
--
-- Novo perfil "Cliente": vê só o portal das obras ligadas a ele
-- (andamento, cronograma, diário com fotos e os pagamentos dele).
-- O cliente NÃO lê nenhuma tabela interna: meu_perfil() devolve nulo para
-- ele, e os dados chegam só pela função portal_cliente().
-- =====================================================================

alter table public.perfis drop constraint if exists perfis_perfil_check;
alter table public.perfis add constraint perfis_perfil_check
  check (perfil in ('Engenheiro', 'Almoxarife', 'Mestre de Obras', 'Cliente'));

-- Cliente não conta como equipe: todas as regras "meu_perfil() is not null" continuam fechadas para ele
create or replace function public.meu_perfil()
returns text language sql stable security definer set search_path = public as $$
  select perfil from public.perfis where id = auth.uid() and ativo and perfil <> 'Cliente'
$$;

create table if not exists public.cliente_obras (
  perfil_id uuid not null references public.perfis(id) on delete cascade,
  obra_id   uuid not null references public.obras(id) on delete cascade,
  primary key (perfil_id, obra_id)
);
alter table public.cliente_obras enable row level security;
create policy leitura on public.cliente_obras for select to authenticated
  using (perfil_id = auth.uid() or public.tem_perfil('Engenheiro'));
create policy gerir on public.cliente_obras for all to authenticated
  using (public.tem_perfil('Engenheiro')) with check (public.tem_perfil('Engenheiro'));

-- Obras que o usuário pode ver no portal (texto, para comparar com a pasta das fotos)
create or replace function public.obras_do_portal()
returns text[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(co.obra_id::text), '{}') from public.cliente_obras co
  join public.perfis p on p.id = co.perfil_id
  where co.perfil_id = auth.uid() and p.ativo and p.perfil = 'Cliente'
$$;
revoke all on function public.obras_do_portal() from public, anon;
grant execute on function public.obras_do_portal() to authenticated;

-- Fotos do diário: o cliente lê só as da pasta da obra dele (caminho = <obra_id>/<dia>/arquivo.jpg)
create policy "diario fotos: cliente" on storage.objects for select to authenticated
  using (bucket_id = 'diario' and (storage.foldername(name))[1] = any(public.obras_do_portal()));

create or replace function public.portal_cliente()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_ids uuid[]; hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if tem_perfil('Engenheiro') then
    select array_agg(id) into v_ids from obras;                     -- o Engenheiro vê como o cliente vê
  else
    select array_agg(x::uuid) into v_ids from unnest(obras_do_portal()) x;
  end if;
  if v_ids is null then return '[]'::jsonb; end if;

  return coalesce((select jsonb_agg(t.j order by t.j->>'nome') from (
    select jsonb_build_object(
      'id', o.id, 'nome', o.nome, 'endereco', o.endereco, 'responsavel', o.responsavel,
      'inicio', o.inicio, 'previsao', o.previsao, 'status', o.status,
      'avanco', av.real, 'previsto', av.prev,
      'etapas', coalesce((select jsonb_agg(jsonb_build_object('nome', e.nome, 'inicio', e.inicio, 'fim', e.fim, 'avanco', e.avanco) order by e.ordem)
                          from etapas e where e.obra_id = o.id), '[]'::jsonb),
      'diarios', coalesce((select jsonb_agg(jsonb_build_object('dia', d.dia, 'clima_manha', d.clima_manha, 'clima_tarde', d.clima_tarde, 'servicos', d.servicos,
                             'fotos', coalesce((select jsonb_agg(jsonb_build_object('caminho', f.caminho, 'legenda', f.legenda) order by f.criado_em)
                                                from diario_fotos f where f.diario_id = d.id), '[]'::jsonb)) order by d.dia desc)
                          from (select * from diarios where obra_id = o.id order by dia desc limit 30) d), '[]'::jsonb),
      'pagamentos', coalesce((select jsonb_agg(jsonb_build_object('descricao', r.descricao, 'valor', r.valor, 'vencimento', r.vencimento,
                                'status', r.status, 'recebido_em', r.recebido_em) order by r.vencimento)
                             from receitas r where r.obra_id = o.id and r.categoria in ('Medição do cliente', 'Parcela de contrato')), '[]'::jsonb),
      'equipe_hoje', (select count(*) from presencas p join funcionarios f on f.id = p.funcionario_id
                      where f.obra_id = o.id and p.dia = hoje and p.status = 'Presente'),
      'inspecoes', (select count(*) from inspecoes i where i.obra_id = o.id),
      'conformidade', (select round(100.0 * count(*) filter (where ii.resultado = 'Conforme')
                                   / nullif(count(*) filter (where ii.resultado in ('Conforme', 'Não conforme')), 0))
                       from inspecao_itens ii join inspecoes i on i.id = ii.inspecao_id where i.obra_id = o.id)
    ) j
    from obras o
    -- avanço geral ponderado pelo valor orçado de cada etapa (ou pela duração, se não houver valores)
    cross join lateral (
      select round(coalesce(sum(w.peso * e.avanco) / nullif(sum(w.peso), 0), 0), 1) as real,
             round(coalesce(sum(w.peso * pl.p) / nullif(sum(w.peso) filter (where pl.p is not null), 0), 0), 1) as prev
      from etapas e
      cross join lateral (select coalesce(nullif((select sum(i.qtd * i.preco_unit) from etapa_itens i where i.etapa_id = e.id), 0),
                                          case when e.inicio is not null and e.fim is not null then e.fim - e.inicio + 1 else 1 end) as peso) w
      cross join lateral (select case when e.inicio is null or e.fim is null then null
                                      when hoje < e.inicio then 0 when hoje >= e.fim then 100
                                      else (hoje - e.inicio + 1)::numeric / (e.fim - e.inicio + 1) * 100 end as p) pl
      where e.obra_id = o.id
    ) av
    where o.id = any(v_ids)
  ) t), '[]'::jsonb);
end $$;
revoke all on function public.portal_cliente() from public, anon;
grant execute on function public.portal_cliente() to authenticated;

alter publication supabase_realtime add table public.cliente_obras;
