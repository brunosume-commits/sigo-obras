-- =====================================================================
-- SIGO — Apaga a obra FICTÍCIA de exemplo e tudo que foi criado com ela.
-- Não mexe em nenhum dado real.
-- =====================================================================
do $$
declare o uuid; fs uuid[];
begin
  select id into o from obras where nome = 'Residencial Vista do Cabo (exemplo)';
  if o is null then raise notice 'Obra de exemplo não encontrada.'; return; end if;
  select array_agg(id) into fs from funcionarios where obra_id = o;

  delete from cotacoes where obra_id = o;
  delete from medicoes where contrato_id in (select id from contratos where obra_id = o);
  delete from contratos where obra_id = o;
  delete from receitas where obra_id = o;
  delete from despesas where obra_id = o;
  delete from compras where obra_id = o;
  delete from epi_entregas where obra_id = o;
  delete from movimentacoes where obra_id = o;
  delete from estoques where obra_id = o;
  delete from diarios where obra_id = o;
  delete from etapas where obra_id = o;
  delete from documentos where funcionario_id = any(fs) or empresa like '%(exemplo)%';
  delete from folha_itens where funcionario_id = any(fs);
  delete from folhas f where not exists (select 1 from folha_itens i where i.mes = f.mes);
  update folhas f set total = (select coalesce(sum(total), 0) from folha_itens i where i.mes = f.mes);
  delete from funcionarios where obra_id = o;
  delete from obras where id = o;
  delete from materiais m where codigo like 'EX-%'
    and not exists (select 1 from movimentacoes x where x.material_id = m.id)
    and not exists (select 1 from compras x where x.material_id = m.id)
    and not exists (select 1 from estoques x where x.material_id = m.id);
  delete from fornecedores f where nome like '%(exemplo)%'
    and not exists (select 1 from compras x where x.fornecedor_id = f.id);
  update caixa set saldo_inicial = 0, atualizado_em = now() where id = 1 and saldo_inicial = 120000 and data_saldo = date '2026-08-24';
end $$;
