-- =====================================================================
-- SIGO — Migração 019: Planejamento semanal (Last Planner / PPC)
-- Toda semana o engenheiro e o mestre combinam as tarefas que a obra
-- vai cumprir. No fim da semana cada tarefa é marcada como concluída ou
-- não concluída, e neste caso com a causa (material, mão de obra, chuva...).
-- PPC = % de tarefas planejadas que foram concluídas. As causas mostram
-- o que mais atrapalha a obra.
-- =====================================================================

create table if not exists public.tarefas_semana (
  id          uuid primary key default gen_random_uuid(),
  obra_id     uuid not null references public.obras(id) on delete restrict,
  semana      date not null check (extract(isodow from semana) = 1),
  ordem       int not null default 0,
  descricao   text not null check (length(trim(descricao)) > 0),
  responsavel text not null default '',
  etapa_id    uuid references public.etapas(id) on delete set null,
  quantidade  numeric(14,3),
  unidade     text not null default '',
  status      text not null default 'Planejada' check (status in ('Planejada', 'Concluída', 'Não concluída')),
  causa       text check (causa in ('Material', 'Mão de obra', 'Equipamento', 'Projeto ou definição', 'Clima', 'Serviço anterior', 'Mudança de prioridade', 'Meta irreal', 'Outros')),
  obs         text not null default '',
  origem_id   uuid references public.tarefas_semana(id) on delete set null,
  criado_por  text,
  criado_em   timestamptz not null default now(),
  fechada_em  timestamptz,
  check (status <> 'Não concluída' or causa is not null)
);
create index if not exists tarefas_semana_obra_semana on public.tarefas_semana (obra_id, semana);

alter table public.tarefas_semana enable row level security;
create policy leitura on public.tarefas_semana for select to authenticated using (public.tem_perfil('Engenheiro', 'Mestre de Obras'));
create policy planejar on public.tarefas_semana for all to authenticated
  using (public.tem_perfil('Engenheiro', 'Mestre de Obras')) with check (public.tem_perfil('Engenheiro', 'Mestre de Obras'));

-- Obra de exemplo: apagar também o planejamento semanal.
create or replace function public.apagar_obra_exemplo(p_obra uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_nome text; fs uuid[];
begin
  if not sou_administrador() then raise exception 'Só um administrador pode apagar a obra de exemplo.'; end if;
  select nome into v_nome from obras where id = p_obra;
  if v_nome is null then raise exception 'Obra não encontrada.'; end if;
  if v_nome not like '%(exemplo)' then raise exception 'Só obras de exemplo podem ser apagadas por aqui.'; end if;
  select array_agg(id) into fs from funcionarios where obra_id = p_obra;

  delete from tarefas_semana where obra_id = p_obra;
  delete from producoes where obra_id = p_obra;
  delete from pendencias where obra_id = p_obra;
  delete from inspecoes where obra_id = p_obra;
  delete from cotacoes where obra_id = p_obra;
  delete from medicoes where contrato_id in (select id from contratos where obra_id = p_obra);
  delete from contratos where obra_id = p_obra;
  delete from receitas where obra_id = p_obra;
  delete from despesas where obra_id = p_obra;
  delete from notas_fiscais where obra_id = p_obra;
  delete from compras where obra_id = p_obra;
  delete from epi_entregas where obra_id = p_obra;
  delete from movimentacoes where obra_id = p_obra;
  delete from estoques where obra_id = p_obra;
  delete from diarios where obra_id = p_obra;
  delete from etapas where obra_id = p_obra;
  delete from documentos where funcionario_id = any(coalesce(fs, '{}')) or empresa like '%(exemplo)%';
  delete from folha_itens where funcionario_id = any(coalesce(fs, '{}'));
  delete from folhas f where not exists (select 1 from folha_itens i where i.mes = f.mes);
  update folhas f set total = (select coalesce(sum(total), 0) from folha_itens i where i.mes = f.mes);
  delete from funcionarios where obra_id = p_obra;
  delete from obras where id = p_obra;
  delete from materiais m where codigo like 'EX-%'
    and not exists (select 1 from movimentacoes x where x.material_id = m.id)
    and not exists (select 1 from compras x where x.material_id = m.id)
    and not exists (select 1 from estoques x where x.material_id = m.id)
    and not exists (select 1 from cotacao_itens x where x.material_id = m.id)
    and not exists (select 1 from nota_itens x where x.material_id = m.id);
  delete from fornecedores f where nome like '%(exemplo)%'
    and not exists (select 1 from compras x where x.fornecedor_id = f.id)
    and not exists (select 1 from cotacao_fornecedores x where x.fornecedor_id = f.id)
    and not exists (select 1 from notas_fiscais x where x.fornecedor_id = f.id);
  delete from servicos_producao s where nome like '%(exemplo)%' and not exists (select 1 from producoes p where p.servico_id = s.id);
  update caixa set saldo_inicial = 0, atualizado_em = now() where id = 1 and saldo_inicial = 120000 and data_saldo = date '2026-08-24';
end $$;

alter publication supabase_realtime add table public.tarefas_semana;
