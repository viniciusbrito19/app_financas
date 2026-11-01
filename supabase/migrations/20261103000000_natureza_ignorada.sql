-- Natureza "ignorada": transação gravada (para não reaparecer como nova em reimportações),
-- mas fora de totais, análise e fila de classificação. Ex.: resgate automático "BB Rende Fácil".

alter table transacoes drop constraint transacoes_natureza_check;
alter table transacoes add constraint transacoes_natureza_check
	check (natureza in ('gasto', 'receita', 'transferencia', 'pagamento_fatura', 'ignorada'));

alter table regras drop constraint regras_natureza_check;
alter table regras add constraint regras_natureza_check
	check (natureza in ('gasto', 'receita', 'transferencia', 'pagamento_fatura', 'ignorada'));
