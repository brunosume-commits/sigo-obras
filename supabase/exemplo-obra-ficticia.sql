-- =====================================================================
-- SIGO — Obra FICTÍCIA de exemplo, com 3 meses de uso (24/08 a 19/11/2026)
-- Serve para conhecer o sistema. Tudo que ela cria tem "(exemplo)" no nome
-- ou código começando por "EX-". Para apagar: supabase/remover-exemplo.sql
-- Rode no SQL Editor do Supabase (precisa existir um Engenheiro ativo).
-- =====================================================================
do $$
declare
  eng uuid; eng_nome text;
  o uuid := gen_random_uuid();
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  ini date := date '2026-08-24';
  d date; w date; r record; v uuid; v2 uuid; q numeric; s numeric; k int;
  mestre text := 'Severino Alves da Silva';
  f1 uuid := gen_random_uuid(); f2 uuid := gen_random_uuid(); f3 uuid := gen_random_uuid(); f4 uuid := gen_random_uuid(); f5 uuid := gen_random_uuid();
  e1 uuid := gen_random_uuid(); e2 uuid := gen_random_uuid(); e3 uuid := gen_random_uuid(); e4 uuid := gen_random_uuid();
  e5 uuid := gen_random_uuid(); e6 uuid := gen_random_uuid(); e7 uuid := gen_random_uuid(); e8 uuid := gen_random_uuid();
  c1 uuid := gen_random_uuid(); c2 uuid := gen_random_uuid(); md uuid; ci1 uuid; ci2 uuid; ci3 uuid; ci4 uuid;
  cot1 uuid := gen_random_uuid(); cot2 uuid := gen_random_uuid(); it uuid;
  hora time := time '09:00';
begin
  select id, nome into eng, eng_nome from perfis where perfil = 'Engenheiro' and ativo order by criado_em limit 1;
  if eng is null then raise exception 'É preciso ter um Engenheiro ativo para criar o exemplo.'; end if;
  if exists (select 1 from obras where nome like '%(exemplo)%') then raise exception 'A obra de exemplo já existe. Rode remover-exemplo.sql antes.'; end if;
  perform set_config('request.jwt.claim.sub', eng::text, true);

  -- ---------------- Obra ----------------
  insert into obras (id, nome, endereco, responsavel, inicio, previsao, orcamento, status)
  values (o, 'Residencial Vista do Cabo (exemplo)', 'Rua das Acácias, 100 — Altiplano Cabo Branco, João Pessoa/PB', eng_nome,
          ini, date '2027-08-31', 0, 'Em andamento');

  -- ---------------- Fornecedores ----------------
  insert into fornecedores (id, nome, contato, categoria) values
    (f1, 'Depósito Litoral Materiais (exemplo)', '(83) 3000-1001 · vendas@litoral.exemplo', 'Básicos'),
    (f2, 'Aço Forte Distribuidora (exemplo)', '(83) 3000-1002 · aco@acoforte.exemplo', 'Aço'),
    (f3, 'Concreteira Atlântica (exemplo)', '(83) 3000-1003', 'Concreto'),
    (f4, 'Hidrolar Elétrica e Hidráulica (exemplo)', '(83) 3000-1004', 'Instalações'),
    (f5, 'Madeireira e EPI Cabo Branco (exemplo)', '(83) 3000-1005', 'Madeira e EPI');

  -- ---------------- Materiais ----------------
  create temp table _m (cod text primary key, id uuid, consumo numeric) on commit drop;
  insert into _m values
    ('cim', gen_random_uuid(), 85), ('arg', gen_random_uuid(), 10), ('are', gen_random_uuid(), 6), ('bri', gen_random_uuid(), 5),
    ('blo', gen_random_uuid(), 0),  ('a10', gen_random_uuid(), 45), ('a08', gen_random_uuid(), 32), ('ara', gen_random_uuid(), 9),
    ('pvc', gen_random_uuid(), 2),  ('ele', gen_random_uuid(), 1),  ('tab', gen_random_uuid(), 28), ('cap', gen_random_uuid(), 0),
    ('bot', gen_random_uuid(), 0),  ('luv', gen_random_uuid(), 0),  ('cin', gen_random_uuid(), 0);
  insert into materiais (id, codigo, nome, unidade, estoque_minimo, categoria)
  select id, c, n, u, mn, cat from _m join (values
    ('cim','EX-001','Cimento CP-II 50kg','sc',80,'Cimentos e argamassas'),
    ('arg','EX-002','Argamassa AC-II 20kg','sc',30,'Cimentos e argamassas'),
    ('are','EX-003','Areia média lavada','m³',12,'Agregados'),
    ('bri','EX-004','Brita 1','m³',12,'Agregados'),
    ('blo','EX-005','Bloco cerâmico 14x19x29','un',2000,'Alvenaria'),
    ('a10','EX-006','Vergalhão CA-50 10mm (12m)','br',120,'Aço e ferragens'),
    ('a08','EX-007','Vergalhão CA-50 8mm (12m)','br',100,'Aço e ferragens'),
    ('ara','EX-008','Arame recozido nº 18','kg',25,'Aço e ferragens'),
    ('pvc','EX-009','Tubo PVC esgoto 100mm (6m)','br',15,'Hidráulica'),
    ('ele','EX-010','Eletroduto corrugado 25mm (rolo 50m)','rl',6,'Elétrica'),
    ('tab','EX-011','Tábua de pinus 30cm x 3m','un',60,'Madeiras'),
    ('cap','EX-012','Capacete de segurança classe B','un',4,'Ferramentas e EPI'),
    ('bot','EX-013','Bota de segurança','par',3,'Ferramentas e EPI'),
    ('luv','EX-014','Luva de vaqueta','par',10,'Ferramentas e EPI'),
    ('cin','EX-015','Cinto de segurança paraquedista','un',2,'Ferramentas e EPI')
  ) x(k, c, n, u, mn, cat) on x.k = _m.cod;
  create temp table _e (mat uuid primary key, saldo numeric not null default 0) on commit drop;
  insert into _e select id, 0 from _m;

  -- ---------------- Orçamento e cronograma ----------------
  insert into etapas (id, obra_id, ordem, nome, inicio, fim, avanco, avanco_em, avanco_por) values
    (e1, o, 1, 'Serviços preliminares', ini, date '2026-09-11', 100, '2026-09-30 17:00-03', mestre),
    (e2, o, 2, 'Fundações', date '2026-09-01', date '2026-10-23', 100, '2026-10-30 17:00-03', mestre),
    (e3, o, 3, 'Estrutura', date '2026-10-12', date '2027-03-26', 18, '2026-11-18 17:00-03', mestre),
    (e4, o, 4, 'Alvenaria', date '2027-01-11', date '2027-05-28', 0, null, null),
    (e5, o, 5, 'Instalações elétricas', date '2027-02-01', date '2027-07-16', 0, null, null),
    (e6, o, 6, 'Instalações hidrossanitárias', date '2027-02-01', date '2027-07-16', 0, null, null),
    (e7, o, 7, 'Cobertura e impermeabilização', date '2027-05-03', date '2027-07-02', 0, null, null),
    (e8, o, 8, 'Revestimentos e acabamento', date '2027-04-05', date '2027-08-27', 0, null, null);
  insert into etapa_itens (etapa_id, descricao, unidade, qtd, preco_unit, ordem) values
    (e1,'Canteiro de obras (barracões, ligações provisórias)','vb',1,38000,1),(e1,'Tapume em chapa','m',180,95,2),(e1,'Locação da obra','vb',1,6500,3),(e1,'Alvará, ART e taxas','vb',1,9500,4),
    (e2,'Estaca hélice contínua Ø40cm','m',960,98,1),(e2,'Blocos e vigas baldrame (concreto)','m³',85,1250,2),(e2,'Aço para fundações','kg',7800,8.6,3),(e2,'Impermeabilização de baldrames','m²',320,42,4),
    (e3,'Concreto fck 30 MPa','m³',620,640,1),(e3,'Aço CA-50/CA-60','kg',52000,8.6,2),(e3,'Formas','m²',4800,52,3),(e3,'Mão de obra de armação e formas','vb',1,218000,4),
    (e4,'Alvenaria de bloco cerâmico 14cm','m²',6200,64,1),
    (e5,'Instalações elétricas e SPDA','vb',1,185000,1),
    (e6,'Instalações hidrossanitárias','vb',1,152000,1),
    (e7,'Cobertura e impermeabilização de lajes','vb',1,96000,1),
    (e8,'Reboco interno e externo','m²',12400,32,1),(e8,'Piso porcelanato','m²',2600,118,2),(e8,'Pintura','m²',14000,19,3);
  update obras set orcamento = (select sum(round(qtd * preco_unit, 2)) from etapa_itens where etapa_id in (e1,e2,e3,e4,e5,e6,e7,e8)) where id = o;
  insert into avanco_historico (etapa_id, dia, avanco, por) values
    (e1,'2026-08-31',70,mestre),(e1,'2026-09-11',100,mestre),
    (e2,'2026-09-15',15,mestre),(e2,'2026-09-30',45,mestre),(e2,'2026-10-15',80,mestre),(e2,'2026-10-30',100,mestre),
    (e3,'2026-10-30',6,mestre),(e3,'2026-11-18',18,mestre);

  -- ---------------- Equipe ----------------
  create temp table _f (n int primary key, id uuid, nome text, funcao text, tipo text, valor numeric, admissao date) on commit drop;
  insert into _f values
    (1, gen_random_uuid(), 'Severino Alves da Silva', 'Mestre de Obras', 'Mensal', 4800, ini),
    (2, gen_random_uuid(), 'José Carlos Ferreira', 'Pedreiro', 'Diária', 180, ini),
    (3, gen_random_uuid(), 'Antônio Marcos Lima', 'Pedreiro', 'Diária', 180, ini),
    (4, gen_random_uuid(), 'Francisco das Chagas Rocha', 'Carpinteiro', 'Diária', 190, date '2026-09-14'),
    (5, gen_random_uuid(), 'Raimundo Nonato Sousa', 'Armador', 'Diária', 190, date '2026-09-14'),
    (6, gen_random_uuid(), 'Luiz Henrique Costa', 'Servente', 'Diária', 110, ini),
    (7, gen_random_uuid(), 'Pedro Henrique Araújo', 'Servente', 'Diária', 110, ini),
    (8, gen_random_uuid(), 'Marcos Vinícius Oliveira', 'Eletricista', 'Diária', 200, date '2026-10-19'),
    (9, gen_random_uuid(), 'Josefa Maria Santos', 'Almoxarife', 'Mensal', 2600, ini);
  insert into funcionarios (id, nome, funcao, obra_id, presenca) select id, nome, funcao, o, 'Presente' from _f;
  insert into remuneracoes (funcionario_id, tipo, valor) select id, tipo, valor from _f;
  -- presença: dias úteis desde a admissão (≈4% falta, ≈2% atestado)
  insert into presencas (funcionario_id, dia, status, registrado_por, registrado_em)
  select f.id, g::date,
         case when abs(hashtext(f.nome || g::date)) % 100 < 4 then 'Falta' when abs(hashtext(f.nome || g::date)) % 100 < 6 then 'Atestado' else 'Presente' end,
         eng, (g::date + time '07:30') at time zone 'America/Sao_Paulo'
  from _f f, generate_series(ini, hoje, interval '1 day') g
  where extract(isodow from g) < 6 and g::date >= f.admissao;
  update funcionarios fu set presenca = p.status from presencas p where p.funcionario_id = fu.id and p.dia = hoje and fu.obra_id = o;

  -- ---------------- Compras entregues (entrada no estoque + despesa) ----------------
  create temp table _c (sol date, ent date, mat text, forn uuid, qtd numeric, preco numeric, etapa uuid) on commit drop;
  insert into _c values
    ('2026-08-18','2026-08-21','cap',f5,12,48,e1), ('2026-08-18','2026-08-21','bot',f5,10,129,e1), ('2026-08-18','2026-08-21','luv',f5,40,18.5,e1),
    ('2026-08-18','2026-08-21','cin',f5,4,289,e1), ('2026-08-26','2026-08-31','tab',f5,200,32,e1),
    ('2026-08-31','2026-09-02','cim',f1,300,36.9,e2), ('2026-08-31','2026-09-02','are',f1,30,145,e2), ('2026-08-31','2026-09-02','bri',f1,30,160,e2),
    ('2026-09-08','2026-09-11','a10',f2,320,58.9,e2), ('2026-09-08','2026-09-11','a08',f2,240,38.5,e2), ('2026-09-08','2026-09-11','ara',f2,80,14.9,e2),
    ('2026-09-21','2026-09-23','cim',f1,300,36.9,e2), ('2026-09-21','2026-09-23','pvc',f4,30,62,e2), ('2026-09-21','2026-09-23','are',f1,25,145,e2),
    ('2026-10-05','2026-10-07','cim',f1,300,37.5,e3), ('2026-10-05','2026-10-07','bri',f1,30,160,e3), ('2026-10-05','2026-10-07','tab',f5,250,32,e3),
    ('2026-10-13','2026-10-16','a10',f2,400,59.9,e3), ('2026-10-13','2026-10-16','a08',f2,320,39.2,e3), ('2026-10-13','2026-10-16','ara',f2,60,14.9,e3),
    ('2026-10-26','2026-10-28','cim',f1,250,37.5,e3), ('2026-10-26','2026-10-28','luv',f5,30,18.5,e1), ('2026-10-26','2026-10-28','are',f1,20,148,e3),
    ('2026-11-04','2026-11-06','ele',f4,12,189,e3), ('2026-11-09','2026-11-11','cim',f1,200,37.5,e3), ('2026-11-09','2026-11-11','arg',f1,80,24.9,e3);
  for r in select _c.*, _m.id mid, m.nome mnome, m.unidade from _c join _m on _m.cod = _c.mat join materiais m on m.id = _m.id order by ent loop
    insert into compras (obra_id, material_id, fornecedor_id, qtd, preco_unit, entrega, status, solicitante, data_solicitacao, criado_por)
    values (o, r.mid, r.forn, r.qtd, r.preco, r.ent, 'Entregue', case when r.mat in ('cap','bot','luv','cin') then 'Josefa Maria Santos' else mestre end, r.sol, eng)
    returning id into v;
    insert into movimentacoes (data, tipo, obra_id, material_id, qtd, responsavel, obs, criado_por)
    values ((r.ent + hora) at time zone 'America/Sao_Paulo', 'Entrada', o, r.mid, r.qtd, 'Josefa Maria Santos', 'Recebimento automático via Módulo de Compras', eng);
    update _e set saldo = saldo + r.qtd where mat = r.mid;
    insert into despesas (compra_id, obra_id, descricao, categoria, valor, vencimento, status, pago_em, etapa_id)
    values (v, o, 'Compra: ' || r.qtd || ' ' || r.unidade || ' de ' || r.mnome, 'Material', round(r.qtd * r.preco, 2), r.ent + 28,
            case when r.ent + 28 < hoje then 'Pago' else 'A pagar' end, case when r.ent + 28 < hoje then r.ent + 28 end, r.etapa);
  end loop;

  -- ---------------- EPI: kit inicial e trocas de luva ----------------
  for r in select f.*, x.mat, x.qtd, x.ca, x.dias, x.dia from _f f
           cross join lateral (values ('cap', 1, '31469', 365, f.admissao), ('bot', 1, '40377', 180, f.admissao), ('luv', 1, '12345', 30, f.admissao),
                                      ('luv', 1, '12345', 30, f.admissao + 30), ('luv', 1, '12345', 30, f.admissao + 60)) x(mat, qtd, ca, dias, dia)
           where x.dia <= hoje and f.n <> 9
           order by x.dia loop
    select id into v2 from _m where cod = r.mat;
    if (select saldo from _e where mat = v2) < r.qtd then continue; end if;
    insert into movimentacoes (data, tipo, obra_id, material_id, qtd, responsavel, obs, criado_por)
    values ((r.dia + time '07:15') at time zone 'America/Sao_Paulo', 'Saída', o, v2, r.qtd, r.nome, 'Entrega de EPI (CA ' || r.ca || ')', eng) returning id into v;
    update _e set saldo = saldo - r.qtd where mat = v2;
    insert into epi_entregas (funcionario_id, material_id, obra_id, qtd, dia, ca, troca_prevista, movimentacao_id, entregue_por, criado_por, criado_em)
    values (r.id, v2, o, r.qtd, r.dia, r.ca, r.dia + r.dias, v, 'Josefa Maria Santos', eng, (r.dia + time '07:15') at time zone 'America/Sao_Paulo');
  end loop;
  -- cinto paraquedista para carpinteiro e armador (trabalho em altura)
  for r in select * from _f where n in (4, 5) loop
    select id into v2 from _m where cod = 'cin';
    insert into movimentacoes (data, tipo, obra_id, material_id, qtd, responsavel, obs, criado_por)
    values ((r.admissao + time '07:20') at time zone 'America/Sao_Paulo', 'Saída', o, v2, 1, r.nome, 'Entrega de EPI (CA 35529)', eng) returning id into v;
    update _e set saldo = saldo - 1 where mat = v2;
    insert into epi_entregas (funcionario_id, material_id, obra_id, qtd, dia, ca, troca_prevista, movimentacao_id, entregue_por, criado_por)
    values (r.id, v2, o, 1, r.admissao, '35529', r.admissao + 365, v, 'Josefa Maria Santos', eng);
  end loop;

  -- ---------------- Saídas semanais de material (consumo da obra) ----------------
  for w in select g::date from generate_series(date '2026-09-02', hoje, interval '7 days') g loop
    for r in select _m.*, m.unidade from _m join materiais m on m.id = _m.id where consumo > 0 loop
      if r.cod = 'pvc' and w > date '2026-10-15' then continue; end if;
      if r.cod = 'ele' and w < date '2026-11-05' then continue; end if;
      if r.cod in ('arg') and w < date '2026-11-10' then continue; end if;
      -- disponível na semana: o que já chegou até aqui menos o que já saiu
      s := (select coalesce(sum(qtd), 0) from _c where mat = r.cod and ent <= w)
         - (select coalesce(sum(qtd), 0) from movimentacoes where obra_id = o and material_id = r.id and tipo = 'Saída');
      q := least(r.consumo * (0.8 + (abs(hashtext(r.cod || w)) % 40) / 100.0), s * 0.9);
      q := case when r.unidade in ('m³', 'kg') then round(q, 1) else floor(q) end;
      if q <= 0 then continue; end if;
      insert into movimentacoes (data, tipo, obra_id, material_id, qtd, responsavel, obs, criado_por)
      values ((w + time '10:30') at time zone 'America/Sao_Paulo', 'Saída', o, r.id, q, mestre,
              case when w < date '2026-10-12' then 'Fundações — blocos e baldrames' else 'Estrutura — pilares e laje do ' || (case when w < date '2026-11-02' then '1º' else '2º' end) || ' pavimento' end, eng);
      update _e set saldo = saldo - q where mat = r.id;
    end loop;
  end loop;
  insert into estoques (material_id, obra_id, saldo) select mat, o, saldo from _e;

  -- ---------------- Folha: agosto, setembro e outubro fechadas e pagas ----------------
  perform fechar_folha('2026-08', '{}'::jsonb);
  perform fechar_folha('2026-09', '{}'::jsonb);
  perform fechar_folha('2026-10', jsonb_build_object((select id from _f where n = 2)::text, jsonb_build_object('valor', 250, 'obs', 'Hora extra concretagem')));
  update despesas set status = 'Pago', pago_em = vencimento where obra_id = o and descricao like 'Folha de pagamento%' and vencimento < hoje;

  -- ---------------- Outras despesas ----------------
  insert into despesas (obra_id, descricao, categoria, valor, vencimento, status, pago_em, etapa_id) values
    (o, 'Alvará de construção, ART e taxas', 'Outros', 9200, '2026-08-25', 'Pago', '2026-08-25', e1),
    (o, 'Barracões, ligações de água e energia do canteiro', 'Outros', 31500, '2026-08-31', 'Pago', '2026-08-31', e1),
    (o, 'Tapume em chapa — 180 m', 'Material', 16900, '2026-09-04', 'Pago', '2026-09-04', e1),
    (o, 'Concreto usinado fck 30 — blocos e baldrames (52 m³)', 'Material', 33280, '2026-09-29', 'Pago', '2026-09-29', e2),
    (o, 'Concreto usinado fck 30 — blocos e baldrames (36 m³)', 'Material', 23040, '2026-10-20', 'Pago', '2026-10-20', e2),
    (o, 'Concreto usinado fck 30 — pilares e laje 1º pav. (64 m³)', 'Material', 40960, '2026-11-12', 'Pago', '2026-11-12', e3),
    (o, 'Concreto usinado fck 30 — laje 2º pav. (66 m³)', 'Material', 42240, '2026-12-03', 'A pagar', null, e3),
    (o, 'Locação de betoneira e andaimes — setembro', 'Equipamentos', 4200, '2026-09-10', 'Pago', '2026-09-10', null),
    (o, 'Locação de betoneira e andaimes — outubro', 'Equipamentos', 4200, '2026-10-10', 'Pago', '2026-10-10', null),
    (o, 'Locação de betoneira e andaimes — novembro', 'Equipamentos', 5600, '2026-11-10', 'Pago', '2026-11-10', null),
    (o, 'Locação de betoneira e andaimes — dezembro', 'Equipamentos', 5600, '2026-12-10', 'A pagar', null, null),
    (o, 'Energia e água do canteiro — outubro', 'Outros', 1380, '2026-11-08', 'Pago', '2026-11-08', null),
    (o, 'Energia e água do canteiro — novembro', 'Outros', 1450, '2026-12-08', 'A pagar', null, null);

  -- ---------------- Empreiteiros e medições ----------------
  insert into contratos (id, obra_id, empreiteiro, objeto, retencao_pct, status, etapa_id) values
    (c1, o, 'Fundações Paraíba Estacas (exemplo)', 'Estacas hélice contínua Ø40cm', 5, 'Encerrado', e2),
    (c2, o, 'Armação & Forma Silva (exemplo)', 'Formas e armação da estrutura', 5, 'Ativo', e3);
  ci1 := gen_random_uuid(); ci2 := gen_random_uuid(); ci3 := gen_random_uuid(); ci4 := gen_random_uuid();
  insert into contrato_itens (id, contrato_id, descricao, unidade, qtd, preco_unit, ordem) values
    (ci1, c1, 'Estaca hélice contínua Ø40cm', 'm', 960, 62, 1), (ci2, c1, 'Mobilização e desmobilização', 'vb', 1, 12000, 2),
    (ci3, c2, 'Formas (execução e desforma)', 'm²', 4800, 28, 1), (ci4, c2, 'Armação (corte, dobra e montagem)', 'kg', 52000, 1.6, 2);
  -- Fundações: 2 medições aprovadas e pagas
  insert into medicoes (id, contrato_id, numero, periodo_ini, periodo_fim, status, obs) values (gen_random_uuid(), c1, 1, '2026-09-01', '2026-09-30', 'Rascunho', 'Estacas dos blocos B1 a B26.') returning id into md;
  insert into medicao_itens values (md, ci1, 520), (md, ci2, 1);
  perform aprovar_medicao(md);
  insert into medicoes (id, contrato_id, numero, periodo_ini, periodo_fim, status, obs) values (gen_random_uuid(), c1, 2, '2026-10-01', '2026-10-23', 'Rascunho', 'Estacas restantes. Contrato concluído.') returning id into md;
  insert into medicao_itens values (md, ci1, 440);
  perform aprovar_medicao(md);
  -- Armação e formas: 1 aprovada (a pagar) e 1 em rascunho
  insert into medicoes (id, contrato_id, numero, periodo_ini, periodo_fim, status, obs) values (gen_random_uuid(), c2, 1, '2026-10-12', '2026-11-11', 'Rascunho', 'Pilares do térreo e laje do 1º pavimento.') returning id into md;
  insert into medicao_itens values (md, ci3, 820), (md, ci4, 9400);
  perform aprovar_medicao(md);
  insert into medicoes (id, contrato_id, numero, periodo_ini, periodo_fim, status, obs) values (gen_random_uuid(), c2, 2, '2026-11-12', '2026-11-19', 'Rascunho', 'Pilares do 1º pavimento.') returning id into md;
  insert into medicao_itens values (md, ci3, 210), (md, ci4, 2600);
  update despesas set status = 'Pago', pago_em = vencimento where obra_id = o and descricao like 'Medição nº%' and vencimento < hoje;
  update medicoes set aprovada_em = (periodo_fim + 1 + time '10:00') at time zone 'America/Sao_Paulo' where contrato_id in (c1, c2) and status = 'Aprovada';

  -- ---------------- Cotações ----------------
  insert into cotacoes (id, obra_id, titulo, status, solicitante, criado_em, aprovada_em, aprovada_por) values
    (cot1, o, 'Aço para pilares e laje do 2º pavimento', 'Aprovada', 'Josefa Maria Santos', '2026-11-13 10:00-03', '2026-11-16 15:20-03', eng_nome),
    (cot2, o, 'Blocos cerâmicos para a alvenaria', 'Aberta', 'Josefa Maria Santos', '2026-11-18 09:00-03', null, null);
  insert into cotacao_fornecedores values (cot1, f1, '2026-11-24', '28 dias'), (cot1, f2, '2026-11-23', '28/56 dias'), (cot1, f4, '2026-11-26', 'À vista'),
                                          (cot2, f1, '2026-12-15', '28 dias'), (cot2, f5, '2026-12-18', '30/60/90 dias');
  insert into cotacao_itens (id, cotacao_id, material_id, qtd, ordem) values (gen_random_uuid(), cot1, (select id from _m where cod='a10'), 380, 1) returning id into it;
  insert into cotacao_precos values (it, f1, 62.9), (it, f2, 59.4), (it, f4, 61.0);
  insert into compras (obra_id, material_id, fornecedor_id, qtd, preco_unit, entrega, status, solicitante, data_solicitacao, criado_por)
  values (o, (select id from _m where cod='a10'), f2, 380, 59.4, '2026-11-23', 'Comprado', 'Josefa Maria Santos', '2026-11-16', eng);
  insert into cotacao_itens (id, cotacao_id, material_id, qtd, ordem) values (gen_random_uuid(), cot1, (select id from _m where cod='a08'), 300, 2) returning id into it;
  insert into cotacao_precos values (it, f1, 40.5), (it, f2, 38.9), (it, f4, 41.2);
  insert into compras (obra_id, material_id, fornecedor_id, qtd, preco_unit, entrega, status, solicitante, data_solicitacao, criado_por)
  values (o, (select id from _m where cod='a08'), f2, 300, 38.9, '2026-11-23', 'Comprado', 'Josefa Maria Santos', '2026-11-16', eng);
  insert into cotacao_itens (id, cotacao_id, material_id, qtd, ordem) values (gen_random_uuid(), cot1, (select id from _m where cod='ara'), 60, 3) returning id into it;
  insert into cotacao_precos values (it, f1, 14.2), (it, f2, 14.9), (it, f4, 15.5);
  insert into compras (obra_id, material_id, fornecedor_id, qtd, preco_unit, entrega, status, solicitante, data_solicitacao, criado_por)
  values (o, (select id from _m where cod='ara'), f1, 60, 14.2, '2026-11-24', 'Comprado', 'Josefa Maria Santos', '2026-11-16', eng);
  insert into cotacao_itens (id, cotacao_id, material_id, qtd, ordem) values (gen_random_uuid(), cot2, (select id from _m where cod='blo'), 42000, 1) returning id into it;
  insert into cotacao_precos values (it, f1, 1.12), (it, f5, 1.05);
  insert into cotacao_itens (id, cotacao_id, material_id, qtd, ordem) values (gen_random_uuid(), cot2, (select id from _m where cod='arg'), 600, 2) returning id into it;
  insert into cotacao_precos values (it, f1, 24.9);
  -- pedido do Mestre aguardando aprovação
  insert into compras (obra_id, material_id, fornecedor_id, qtd, preco_unit, entrega, status, solicitante, data_solicitacao, criado_por)
  values (o, (select id from _m where cod='tab'), f5, 150, 32, '2026-11-27', 'Solicitado', mestre, '2026-11-18', eng);

  -- ---------------- Receitas e caixa ----------------
  insert into receitas (obra_id, descricao, categoria, valor, vencimento, status, recebido_em) values
    (o, 'Sinal do contrato de construção', 'Parcela de contrato', 150000, '2026-08-28', 'Recebido', '2026-08-28'),
    (o, '1ª medição do cliente (setembro)', 'Medição do cliente', 132000, '2026-10-05', 'Recebido', '2026-10-06'),
    (o, '2ª medição do cliente (outubro)', 'Medição do cliente', 168000, '2026-11-05', 'Recebido', '2026-11-05'),
    (o, '3ª medição do cliente (novembro)', 'Medição do cliente', 196000, '2026-12-07', 'A receber', null),
    (o, '4ª medição do cliente (dezembro)', 'Medição do cliente', 214000, '2027-01-06', 'A receber', null),
    (o, '5ª medição do cliente (janeiro)', 'Medição do cliente', 228000, '2027-02-05', 'A receber', null);
  update caixa set saldo_inicial = 120000, data_saldo = ini, atualizado_em = now() where id = 1;

  -- ---------------- Documentos ----------------
  insert into documentos (funcionario_id, tipo, descricao, emissao, validade, criado_por)
  select id, 'ASO (exame ocupacional)', 'Admissional', admissao - 5, admissao - 5 + 365, eng from _f where n <> 7;
  insert into documentos (funcionario_id, tipo, descricao, emissao, validade, criado_por)
  select id, 'ASO (exame ocupacional)', 'Periódico', date '2025-11-12', date '2026-11-12', eng from _f where n = 7;
  insert into documentos (funcionario_id, tipo, descricao, emissao, validade, criado_por)
  select id, 'NR-18 Construção civil', 'Treinamento admissional 6h', admissao - 3, admissao - 3 + 730, eng from _f where n <> 9;
  insert into documentos (funcionario_id, tipo, descricao, emissao, validade, criado_por)
  select id, 'NR-35 Trabalho em altura', 'Reciclagem bienal', date '2024-12-08', date '2026-12-08', eng from _f where n in (4, 5);
  insert into documentos (funcionario_id, tipo, descricao, emissao, validade, criado_por)
  select id, 'NR-10 Eletricidade', 'Básico 40h', date '2024-12-12', date '2026-12-12', eng from _f where n = 8;
  insert into documentos (empresa, tipo, descricao, emissao, validade, criado_por) values
    ('Fundações Paraíba Estacas (exemplo)', 'Seguro de vida', 'Apólice coletiva 77.104 (exemplo)', '2026-03-01', '2027-03-01', eng),
    ('Armação & Forma Silva (exemplo)', 'Contrato', 'Contrato de empreitada — formas e armação', '2026-10-09', '2027-04-30', eng),
    ('Residencial Vista do Cabo (exemplo)', 'Alvará / licença', 'Alvará de construção nº 2026/0001 (exemplo)', '2026-08-10', '2027-08-10', eng);

  -- ---------------- Diário de obra (dias úteis) ----------------
  insert into diarios (obra_id, dia, clima_manha, clima_tarde, servicos, ocorrencias, observacoes, autor_nome, criado_por, criado_em, atualizado_em)
  select o, g::date,
    case when abs(hashtext('m' || g::date)) % 10 < 7 then 'Bom' when abs(hashtext('m' || g::date)) % 10 < 9 then 'Nublado' else 'Chuva' end,
    case when abs(hashtext('t' || g::date)) % 10 < 6 then 'Bom' when abs(hashtext('t' || g::date)) % 10 < 8 then 'Nublado' when abs(hashtext('t' || g::date)) % 20 = 19 then 'Impraticável' else 'Chuva' end,
    case
      when g::date < date '2026-08-31' then (array['Montagem do barracão e do almoxarifado.','Instalação de tapumes na frente do terreno.','Ligações provisórias de água e energia.','Limpeza do terreno e retirada de entulho.','Recebimento de EPIs e integração da equipe (NR-18).'])[1 + abs(hashtext('s' || g::date)) % 5]
      when g::date < date '2026-09-14' then (array['Locação da obra com gabarito.','Conferência dos eixos com a topografia.','Escavação dos blocos B1 a B8.','Início das estacas hélice contínua (empreiteira).','Estacas dos blocos B9 a B14.'])[1 + abs(hashtext('s' || g::date)) % 5]
      when g::date < date '2026-10-12' then (array['Estacas hélice contínua — eixo C e D.','Arrasamento de estacas e preparo dos blocos.','Armação dos blocos B15 a B20.','Concretagem dos blocos B1 a B12 (concreto usinado).','Formas e armação das vigas baldrame.','Impermeabilização dos baldrames.'])[1 + abs(hashtext('s' || g::date)) % 6]
      else (array['Armação dos pilares do térreo.','Formas dos pilares P1 a P18.','Concretagem dos pilares do térreo.','Escoramento e formas da laje do 1º pavimento.','Armação da laje do 1º pavimento.','Concretagem da laje do 1º pavimento (64 m³).','Desforma dos pilares e início dos pilares do 1º pavimento.','Passagem de eletrodutos na laje.'])[1 + abs(hashtext('s' || g::date)) % 8]
    end,
    case when abs(hashtext('o' || g::date)) % 9 = 0 then 'Chuva forte entre 14h e 16h; serviços externos parados.'
         when abs(hashtext('o' || g::date)) % 13 = 0 then 'Atraso de 2h na entrega do concreto usinado.'
         when abs(hashtext('o' || g::date)) % 17 = 0 then 'Falta de energia das 9h às 10h30.' else '' end,
    case when abs(hashtext('b' || g::date)) % 11 = 0 then 'Visita do engenheiro responsável; conferência das armaduras liberada.'
         when abs(hashtext('b' || g::date)) % 15 = 0 then 'DDS sobre trabalho em altura e uso do cinto.' else '' end,
    mestre, eng, (g::date + time '17:30') at time zone 'America/Sao_Paulo', (g::date + time '17:30') at time zone 'America/Sao_Paulo'
  from generate_series(ini, hoje, interval '1 day') g
  where extract(isodow from g) < 6;
end $$;
-- ---------------- Qualidade e pendências da obra de exemplo ----------------
do $$
declare o uuid; i uuid; eng uuid; m record; et uuid;
begin
  select id into o from obras where nome = 'Residencial Vista do Cabo (exemplo)';
  if o is null or exists (select 1 from inspecoes where obra_id = o) then return; end if;
  select id into eng from perfis where perfil = 'Engenheiro' and ativo order by criado_em limit 1;
  for m in select * from (values
      ('Concretagem', 'FVS', 'Blocos B1 a B12', date '2026-09-29', 'Fundações', 'José Carlos Ferreira', null::int, '', ''),
      ('Recebimento de aço', 'FVM', 'NF 48.211 — 400 br CA-50 10mm', date '2026-10-16', 'Estrutura', 'Josefa Maria Santos', null, '', ''),
      ('Armação (antes da concretagem)', 'FVS', 'Laje do 1º pavimento', date '2026-11-04', 'Estrutura', 'Severino Alves da Silva', 3, 'Faltam espaçadores nas vigas V12 a V15', 'Resolvida'),
      ('Concretagem', 'FVS', 'Pilares e laje do 1º pavimento', date '2026-11-12', 'Estrutura', 'Severino Alves da Silva', null, '', ''),
      ('Recebimento de cimento', 'FVM', 'NF 9.872 — 200 sacos', date '2026-11-11', 'Estrutura', 'Josefa Maria Santos', 2, '6 sacos empedrados — devolver ao fornecedor', 'Aberta'),
      ('Formas e escoramento', 'FVS', 'Laje do 2º pavimento', date '2026-11-17', 'Estrutura', 'Severino Alves da Silva', 4, 'Escoras sem travamento no eixo C', 'Em andamento')
    ) v(modelo, tipo, local, dia, etapa, quem, nc, problema, st) loop
    select id into et from etapas where obra_id = o and nome = m.etapa;
    insert into inspecoes (obra_id, modelo_id, nome, tipo, local, etapa_id, dia, responsavel, criado_por, criado_em)
    values (o, (select id from checklist_modelos where nome = m.modelo), m.modelo, m.tipo, m.local, et, m.dia, m.quem, eng, (m.dia + time '16:00') at time zone 'America/Sao_Paulo')
    returning id into i;
    insert into inspecao_itens (inspecao_id, ordem, descricao, resultado, obs)
    select i, x.ord::int, x.txt, case when x.ord::int = m.nc then 'Não conforme' else 'Conforme' end, case when x.ord::int = m.nc then m.problema else '' end
    from checklist_modelos c, jsonb_array_elements_text(c.itens) with ordinality x(txt, ord) where c.nome = m.modelo;
    if m.nc is not null then
      insert into pendencias (obra_id, titulo, descricao, local, responsavel, prazo, prioridade, status, inspecao_id, item_ordem, aberta_por, criado_em, resolvida_em, resolvida_por)
      values (o, (select itens->>(m.nc - 1) from checklist_modelos where nome = m.modelo), m.problema, m.modelo || ' — ' || m.local,
              case when m.tipo = 'FVM' then 'Josefa Maria Santos' else 'Armação & Forma Silva (exemplo)' end, m.dia + 3, 'Alta', m.st, i, m.nc, m.quem,
              (m.dia + time '16:05') at time zone 'America/Sao_Paulo',
              case when m.st = 'Resolvida' then (m.dia + 1 + time '11:00') at time zone 'America/Sao_Paulo' end, case when m.st = 'Resolvida' then 'Severino Alves da Silva' end);
    end if;
  end loop;
  insert into pendencias (obra_id, titulo, descricao, local, responsavel, prazo, prioridade, status, aberta_por, criado_em, resolvida_em, resolvida_por) values
    (o, 'Instalar guarda-corpo na borda da laje', 'Exigência da NR-18 antes de liberar o pavimento', 'Laje do 1º pavimento', 'Severino Alves da Silva', '2026-11-14', 'Alta', 'Aberta', 'Sumé', '2026-11-12 17:00-03', null, null),
    (o, 'Reparar tapume danificado pela chuva', '', 'Frente do terreno', 'Luiz Henrique Costa', '2026-11-25', 'Média', 'Aberta', 'Severino Alves da Silva', '2026-11-18 08:00-03', null, null),
    (o, 'Retirar entulho do térreo', 'Caçamba agendada', 'Térreo', 'Pedro Henrique Araújo', '2026-11-08', 'Baixa', 'Resolvida', 'Severino Alves da Silva', '2026-11-05 08:00-03', '2026-11-07 15:00-03', 'Severino Alves da Silva');
end $$;
-- ---------------- Consumo e produção da obra de exemplo ----------------
do $$
declare o uuid; s1 uuid := gen_random_uuid(); s2 uuid := gen_random_uuid(); s3 uuid := gen_random_uuid(); s4 uuid := gen_random_uuid();
        et_f uuid; et_e uuid; w date; c numeric; k int := 0;
        mat_id uuid;
begin
  select id into o from obras where nome = 'Residencial Vista do Cabo (exemplo)';
  if o is null or exists (select 1 from producoes where obra_id = o) then return; end if;
  select id into et_f from etapas where obra_id = o and nome = 'Fundações';
  select id into et_e from etapas where obra_id = o and nome = 'Estrutura';
  insert into servicos_producao (id, nome, unidade) values
    (s1, 'Concreto virado na obra fck 25 (exemplo)', 'm³'), (s2, 'Armação (exemplo)', 'kg'),
    (s3, 'Formas de madeira (exemplo)', 'm²'), (s4, 'Alvenaria bloco 14x19x29 (exemplo)', 'm²');
  insert into indices_consumo (servico_id, material_id, consumo, tolerancia_pct)
  select x.s, m.id, x.c, x.t from (values
    (s1,'EX-001',7.0,5), (s1,'EX-003',0.55,10), (s1,'EX-004',0.45,5),
    (s2,'EX-006',0.075,5), (s2,'EX-007',0.045,5), (s2,'EX-008',0.013,10),
    (s3,'EX-011',0.55,15),
    (s4,'EX-005',13.5,5), (s4,'EX-002',0.4,10)) x(s, cod, c, t)
  join materiais m on m.codigo = x.cod;
  -- produção semanal coerente com o que saiu do estoque (perdas diferentes por material)
  for w in select distinct ((data at time zone 'America/Sao_Paulo')::date) from movimentacoes
           where obra_id = o and tipo = 'Saída' and obs not like 'Entrega de EPI%' order by 1 loop
    k := k + 1;
    select coalesce(sum(qtd), 0) into c from movimentacoes mv join materiais m on m.id = mv.material_id
      where mv.obra_id = o and mv.tipo = 'Saída' and m.codigo = 'EX-001' and (mv.data at time zone 'America/Sao_Paulo')::date = w;
    if c > 0 then
      insert into producoes (obra_id, servico_id, etapa_id, dia, quantidade, local, equipe, registrado_por)
      values (o, s1, case when w < '2026-10-12' then et_f else et_e end, w, round(c / 7.0 / (1.04 + (k % 4) * 0.03), 1),
              case when w < '2026-10-12' then 'Blocos e baldrames' else 'Pilares e laje' end, 'José Carlos / Antônio Marcos', 'Severino Alves da Silva');
    end if;
    select coalesce(sum(qtd), 0) into c from movimentacoes mv join materiais m on m.id = mv.material_id
      where mv.obra_id = o and mv.tipo = 'Saída' and m.codigo = 'EX-006' and (mv.data at time zone 'America/Sao_Paulo')::date = w;
    if c > 0 then
      insert into producoes (obra_id, servico_id, etapa_id, dia, quantidade, local, equipe, registrado_por)
      values (o, s2, case when w < '2026-10-12' then et_f else et_e end, w, round(c / 0.075 / (1.02 + (k % 3) * 0.02)),
              case when w < '2026-10-12' then 'Blocos e baldrames' else 'Pilares e laje' end, 'Raimundo Nonato', 'Severino Alves da Silva');
    end if;
    select coalesce(sum(qtd), 0) into c from movimentacoes mv join materiais m on m.id = mv.material_id
      where mv.obra_id = o and mv.tipo = 'Saída' and m.codigo = 'EX-011' and (mv.data at time zone 'America/Sao_Paulo')::date = w;
    if c > 0 then
      insert into producoes (obra_id, servico_id, etapa_id, dia, quantidade, local, equipe, registrado_por)
      values (o, s3, case when w < '2026-10-12' then et_f else et_e end, w, round(c / 0.55 / (1.08 + (k % 3) * 0.02)),
              case when w < '2026-10-12' then 'Baldrames' else 'Pilares e laje' end, 'Francisco das Chagas', 'Severino Alves da Silva');
    end if;
  end loop;
end $$;
