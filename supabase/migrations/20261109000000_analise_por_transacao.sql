-- Análise conta o gasto pela TRANSAÇÃO (categoria dela) sempre que existir.
-- Antes, transações de conta corrente conciliadas com um lançamento contavam pela categoria
-- do lançamento, e reclassificá-las não mudava a análise.
-- O lançamento só entra quando foi pago/informado à mão, sem transação de conta corrente ligada.

create or replace view v_gastos_categoria with (security_invoker = true) as
select l.residencia_id, l.competencia, l.categoria_id, 'manual'::text as meio, coalesce(l.valor_real, l.valor_previsto) as valor,
	l.membro_id
from lancamentos l
where l.tipo = 'despesa' and (l.status = 'pago' or l.valor_real is not null)
	-- fatura do cartão: representada pelos itens
	and not exists (select 1 from contas c where c.recorrencia_id = l.recorrencia_id and c.tipo = 'cartao')
	-- baixado por extrato: representado pelas transações
	and not exists (
		select 1 from transacoes x join contas cx on cx.id = x.conta_id and cx.tipo = 'corrente'
		where x.lancamento_id = l.id
	)
union all
select t.residencia_id, t.competencia, t.categoria_id, t.meio, -t.valor,
	coalesce(k.membro_id, c.membro_id)
from transacoes t
join contas c on c.id = t.conta_id
left join cartoes k on k.conta_id = t.conta_id and k.final = t.cartao
where t.natureza = 'gasto' and not t.projetada;
