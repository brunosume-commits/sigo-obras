-- =====================================================================
-- SIGO — Migração 020: BDI por obra (taxa única)
-- Preço de venda = custo direto x (1 + BDI). Só o Engenheiro altera
-- (a política de escrita da tabela obras já é só do Engenheiro).
-- =====================================================================
alter table public.obras add column if not exists bdi_pct numeric(6,2) not null default 0 check (bdi_pct >= 0 and bdi_pct <= 100);
update public.obras set bdi_pct = 25 where nome = 'Residencial Vista do Cabo (exemplo)' and bdi_pct = 0;
