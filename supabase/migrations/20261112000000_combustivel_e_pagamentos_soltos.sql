-- 1) Categoria "Combustível" (para despesas embutidas no cartão como combustível não pegarem todo o "Transporte").
-- 2) Pagamentos de fatura ("CARTAO CX") importados antes de o cartão/recorrência estarem configurados ficaram
--    sem vínculo, e a fatura aparecia "atrasada" mesmo paga: liga-os agora e recalcula o status.

create or replace function seed_categorias_v2(r uuid) returns void
language sql security definer set search_path = public as $$
	insert into categorias (residencia_id, nome, tipo, cor, icone)
	select r, c.nome, 'despesa', c.cor, c.icone from (values
		('Alimentação fora', '#f43f5e', '🍽️'),
		('Dízimo/Doações', '#0891b2', '🙏'),
		('Financiamento', '#475569', '🏦'),
		('Combustível', '#d97706', '⛽')
	) as c (nome, cor, icone)
	where not exists (select 1 from categorias x where x.residencia_id = r and x.nome = c.nome)
$$;

select seed_categorias_v2(id) from residencias;

-- pagamentos de fatura soltos → lançamento da fatura do mesmo mês com valor mais próximo
update transacoes t set lancamento_id = (
	select l.id from lancamentos l
	join contas c on c.recorrencia_id = l.recorrencia_id and c.tipo = 'cartao'
	where l.residencia_id = t.residencia_id and l.competencia = t.competencia and l.status <> 'cancelado'
	order by abs(coalesce(l.valor_real, l.valor_previsto) + t.valor)
	limit 1
)
where t.natureza = 'pagamento_fatura' and t.lancamento_id is null;

select recalcular_lancamento(x.lancamento_id)
from (select distinct lancamento_id from transacoes where natureza = 'pagamento_fatura' and lancamento_id is not null) x;
