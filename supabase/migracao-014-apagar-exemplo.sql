-- =====================================================================
-- SIGO — Migração 014: botão "Apagar exemplo" (só administradores)
-- Rode DEPOIS da migração 013.
-- Apaga uma obra cujo nome termina em "(exemplo)" e tudo que foi criado
-- com ela. Só funciona para e-mails da tabela administradores.
-- =====================================================================

create or replace function public.sou_administrador()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.perfis p join public.administradores a on lower(a.email) = lower(p.email)
                 where p.id = auth.uid() and p.ativo)
$$;
revoke all on function public.sou_administrador() from public, anon;
grant execute on function public.sou_administrador() to authenticated;

create or replace function public.apagar_obra_exemplo(p_obra uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_nome text; fs uuid[];
begin
  if not sou_administrador() then raise exception 'Só um administrador pode apagar a obra de exemplo.'; end if;
  select nome into v_nome from obras where id = p_obra;
  if v_nome is null then raise exception 'Obra não encontrada.'; end if;
  if v_nome not like '%(exemplo)' then raise exception 'Só obras de exemplo podem ser apagadas por aqui.'; end if;
  select array_agg(id) into fs from funcionarios where obra_id = p_obra;

  delete from pendencias where obra_id = p_obra;
  delete from inspecoes where obra_id = p_obra;
  delete from cotacoes where obra_id = p_obra;
  delete from medicoes where contrato_id in (select id from contratos where obra_id = p_obra);
  delete from contratos where obra_id = p_obra;
  delete from receitas where obra_id = p_obra;
  delete from despesas where obra_id = p_obra;
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
    and not exists (select 1 from cotacao_itens x where x.material_id = m.id);
  delete from fornecedores f where nome like '%(exemplo)%'
    and not exists (select 1 from compras x where x.fornecedor_id = f.id)
    and not exists (select 1 from cotacao_fornecedores x where x.fornecedor_id = f.id);
  update caixa set saldo_inicial = 0, atualizado_em = now() where id = 1 and saldo_inicial = 120000 and data_saldo = date '2026-08-24';
end $$;
revoke all on function public.apagar_obra_exemplo(uuid) from public, anon;
grant execute on function public.apagar_obra_exemplo(uuid) to authenticated;
