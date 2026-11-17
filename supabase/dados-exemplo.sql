-- =====================================================================
-- SIGO — dados de exemplo (OPCIONAL)
-- Rode depois do schema.sql apenas se quiser ver o sistema preenchido
-- para testes. Não rode em produção com dados reais.
-- =====================================================================

insert into public.obras (id, nome, endereco, responsavel, inicio, previsao, orcamento) values
  ('00000000-0000-0000-0000-0000000000a1', 'Residencial Jardins', 'Av. Epitácio Pessoa, 1450 - João Pessoa/PB', 'Eng. Carlos Mendes', '2026-01-15', '2026-12-20', 1200000),
  ('00000000-0000-0000-0000-0000000000a2', 'Edifício Horizonte', 'Rua das Acácias, 320 - Cabedelo/PB', 'Eng. Mariana Costa', '2026-03-01', '2027-06-30', 2500000),
  ('00000000-0000-0000-0000-0000000000a3', 'Galpão Logístico BR-230', 'Rodovia BR-230, Km 18 - Bayeux/PB', 'Mestre José Antônio', '2026-02-10', '2026-12-15', 850000);

insert into public.materiais (id, codigo, nome, unidade, estoque_minimo) values
  ('00000000-0000-0000-0000-0000000000b1', 'MAT-001', 'Cimento CP-II 50kg', 'sc', 50),
  ('00000000-0000-0000-0000-0000000000b2', 'MAT-002', 'Vergalhão CA-50 10mm (12m)', 'br', 40),
  ('00000000-0000-0000-0000-0000000000b3', 'MAT-003', 'Areia Média Lavada', 'm³', 15),
  ('00000000-0000-0000-0000-0000000000b4', 'MAT-004', 'Bloco Cerâmico 9x19x19', 'un', 1000),
  ('00000000-0000-0000-0000-0000000000b5', 'MAT-005', 'Tubo PVC Esgoto 100mm (6m)', 'un', 20);

insert into public.estoques (material_id, obra_id, saldo)
select m.id, o.id, s.saldo from (values
  ('MAT-001', 'Residencial Jardins', 35), ('MAT-001', 'Edifício Horizonte', 140), ('MAT-001', 'Galpão Logístico BR-230', 60),
  ('MAT-002', 'Residencial Jardins', 85), ('MAT-002', 'Edifício Horizonte', 22),  ('MAT-002', 'Galpão Logístico BR-230', 55),
  ('MAT-003', 'Residencial Jardins', 18), ('MAT-003', 'Edifício Horizonte', 30),  ('MAT-003', 'Galpão Logístico BR-230', 8),
  ('MAT-004', 'Residencial Jardins', 2400), ('MAT-004', 'Edifício Horizonte', 850), ('MAT-004', 'Galpão Logístico BR-230', 1500),
  ('MAT-005', 'Residencial Jardins', 25), ('MAT-005', 'Edifício Horizonte', 40),  ('MAT-005', 'Galpão Logístico BR-230', 12)
) as s(codigo, obra, saldo)
join public.materiais m on m.codigo = s.codigo
join public.obras o on o.nome = s.obra;

insert into public.fornecedores (nome, contato, categoria) values
  ('Depósito Construir Ltda', '(83) 99911-2233', 'Básicos e Estrutural'),
  ('Aço Nordeste S/A', '(83) 98822-4455', 'Ferragens e Aço'),
  ('Hidráulica & Elétrica PB', '(83) 98733-6677', 'Instalações');

insert into public.funcionarios (nome, funcao, obra_id, presenca) values
  ('José Antônio', 'Mestre de Obras', '00000000-0000-0000-0000-0000000000a1', 'Presente'),
  ('Pedro Silva', 'Pedreiro', '00000000-0000-0000-0000-0000000000a1', 'Presente'),
  ('Marcos Vinícius', 'Almoxarife', '00000000-0000-0000-0000-0000000000a2', 'Presente'),
  ('Roberto Alves', 'Servente', '00000000-0000-0000-0000-0000000000a2', 'Falta'),
  ('Lucas Ferreira', 'Armador', '00000000-0000-0000-0000-0000000000a3', 'Presente');

insert into public.despesas (obra_id, descricao, categoria, valor, vencimento, status) values
  ('00000000-0000-0000-0000-0000000000a1', 'Lote Cimento e Argamassa (NF 4510)', 'Material', 18500, '2026-11-10', 'Pago'),
  ('00000000-0000-0000-0000-0000000000a1', 'Folha Quinzenal Equipe Campo', 'Mão de Obra', 42000, '2026-11-20', 'A pagar'),
  ('00000000-0000-0000-0000-0000000000a2', 'Aço Estrutural Fundação', 'Material', 64200, '2026-11-12', 'Pago'),
  ('00000000-0000-0000-0000-0000000000a3', 'Locação Betoneira e Andaimes', 'Equipamentos', 6800, '2026-11-25', 'A pagar');
