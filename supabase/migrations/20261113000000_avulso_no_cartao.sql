-- Despesa avulsa (lançada à mão) paga no cartão: vinculada aos itens da fatura daquele mês.
-- Os itens já apontam para o lançamento da fatura (lancamento_id), por isso o vínculo é uma coluna própria.
-- O avulso vinculado sai dos totais e da análise: o gasto real são os próprios itens.

alter table transacoes add column avulso_id uuid references lancamentos on delete set null;
create index on transacoes (avulso_id);

create or replace view v_gastos_categoria with (security_invoker = true) as
select l.residencia_id, l.competencia, l.categoria_id, 'manual'::text as meio, coalesce(l.valor_real, l.valor_previsto) as valor,
	l.membro_id
from lancamentos l
where l.tipo = 'despesa' and (l.status = 'pago' or l.valor_real is not null)
	-- fatura do cartão: representada pelos itens
	and not exists (select 1 from contas c where c.recorrencia_id = l.recorrencia_id and c.tipo = 'cartao')
	-- embutida na fatura: o gasto real está nos itens da fatura
	and not exists (select 1 from recorrencias r where r.id = l.recorrencia_id and r.cartao_conta_id is not null)
	-- avulso vinculado a itens do cartão: idem
	and not exists (select 1 from transacoes x where x.avulso_id = l.id)
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
