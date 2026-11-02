-- 1) Fatura com vários cartões ligados à mesma recorrência (ex.: Caixa VISA + Caixa Elo):
--    o valor real do lançamento da fatura passa a ser a SOMA das faturas de todos os cartões
--    (antes a última fatura importada sobrescrevia a outra), e ela fica paga quando os
--    pagamentos cobrem esse total.
-- 2) Lançamento 'cancelado': excluído só daquele mês; gerar_mes não o recria.

alter table lancamentos drop constraint lancamentos_status_check;
alter table lancamentos add constraint lancamentos_status_check check (status in ('previsto', 'pago', 'cancelado'));

-- Soma, entre as contas-cartão da recorrência, o total da fatura que vence em p_comp:
-- total da importação daquele vencimento ou, na falta, o "total anterior" informado pela fatura seguinte.
-- Sem nenhuma informação, mantém o valor atual (pode ter sido digitado à mão).
create function recalcular_fatura(p_rec uuid, p_comp date) returns void
language plpgsql security invoker set search_path = public as $$
declare
	total numeric;
begin
	select sum(v) into total from (
		select coalesce(
			(select i.total from importacoes i
				where i.conta_id = c.id and i.competencia = p_comp and i.total is not null
				order by i.created_at desc limit 1),
			(select i.total_anterior from importacoes i
				where i.conta_id = c.id and i.competencia = (p_comp + interval '1 month')::date and i.total_anterior is not null
				order by i.created_at desc limit 1)
		) as v
		from contas c where c.recorrencia_id = p_rec and c.tipo = 'cartao'
	) x;
	if total is null then return; end if;
	update lancamentos set valor_real = total
	where recorrencia_id = p_rec and competencia = p_comp and status <> 'cancelado';
end $$;

-- Status e valor real a partir das transações de conta corrente ligadas ao lançamento.
create or replace function recalcular_lancamento(p_lanc uuid) returns void
language plpgsql security invoker set search_path = public as $$
declare
	em_partes boolean;
	eh_fatura boolean;
	st text;
	vr numeric;
	vp numeric;
	n int;
	total numeric;
	ultima date;
	quitado boolean;
begin
	if p_lanc is null then return; end if;
	select coalesce(r.acumula, false),
		exists (select 1 from contas c where c.recorrencia_id = l.recorrencia_id and c.tipo = 'cartao'),
		l.status, l.valor_real, l.valor_previsto
	into em_partes, eh_fatura, st, vr, vp
	from lancamentos l left join recorrencias r on r.id = l.recorrencia_id
	where l.id = p_lanc;
	if not found or st = 'cancelado' then return; end if;

	select count(*), abs(sum(t.valor)), max(t.data) into n, total, ultima
	from transacoes t join contas c on c.id = t.conta_id and c.tipo = 'corrente'
	where t.lancamento_id = p_lanc;

	if eh_fatura then
		-- fatura: valor real vem dos PDFs (soma dos cartões); paga quando os pagamentos o cobrem
		quitado := n > 0 and total >= coalesce(vr, total) - 0.01;
		vr := coalesce(vr, case when n > 0 then total end);
	else
		-- paga em várias vezes: só quita ao atingir o previsto
		quitado := n > 0 and not (em_partes and total < vp);
		vr := case when n > 0 then total end;
	end if;

	update lancamentos set
		status = case when quitado then 'pago' else 'previsto' end,
		pago_em = case when quitado then ultima end,
		valor_real = vr
	where id = p_lanc;
end $$;

create or replace function conciliar_importacao(p_imp uuid) returns void
language plpgsql security invoker set search_path = public as $$
declare
	imp importacoes;
	cta contas;
	lanc uuid;
begin
	select * into imp from importacoes where id = p_imp;
	select * into cta from contas where id = imp.conta_id;

	perform gerar_mes(imp.residencia_id, m.c)
	from (select distinct competencia as c from transacoes where importacao_id = p_imp and not projetada) m;

	-- transferências: saída e entrada de mesmo valor em contas correntes distintas, até 3 dias
	if cta.tipo = 'corrente' then
		with par as (
			select a.id as a_id, b.id as b_id
			from transacoes a
			join transacoes b on b.residencia_id = a.residencia_id and b.conta_id <> a.conta_id
				and b.valor = -a.valor and abs(b.data - a.data) <= 3
			join contas cb on cb.id = b.conta_id and cb.tipo = 'corrente'
			where a.importacao_id = p_imp
				and a.natureza in ('gasto', 'receita') and b.natureza in ('gasto', 'receita')
				and a.lancamento_id is null and b.lancamento_id is null
		)
		update transacoes set natureza = 'transferencia', meio = 'transferencia', categoria_id = null
		where id in (select a_id from par union select b_id from par);
	end if;

	if imp.formato = 'pdf_fatura' then
		-- a fatura nova reprojeta todas as parcelas pendentes (itens contam no mês anterior ao vencimento)
		delete from transacoes
		where conta_id = cta.id and projetada and importacao_id <> p_imp and competencia >= (imp.competencia - interval '1 month')::date;

		if cta.recorrencia_id is not null then
			-- o lançamento da fatura fica no mês do vencimento (quando é paga)
			perform gerar_mes(imp.residencia_id, imp.competencia);
			perform gerar_mes(imp.residencia_id, (imp.competencia - interval '1 month')::date);
			select id into lanc from lancamentos
			where recorrencia_id = cta.recorrencia_id and competencia = imp.competencia and status <> 'cancelado';

			update transacoes set lancamento_id = lanc
			where importacao_id = p_imp and not projetada and lanc is not null;

			-- valor real = soma das faturas de todos os cartões ligados à recorrência (ex.: VISA + Elo)
			perform recalcular_fatura(cta.recorrencia_id, imp.competencia);
			perform recalcular_fatura(cta.recorrencia_id, (imp.competencia - interval '1 month')::date);
			perform recalcular_lancamento(x.id) from lancamentos x
			where x.recorrencia_id = cta.recorrencia_id and x.competencia in (imp.competencia, (imp.competencia - interval '1 month')::date);

			update lancamentos l set valor_previsto = greatest(l.valor_previsto, p.total)
			from (
				select competencia, -sum(valor) as total from transacoes
				where conta_id = cta.id and projetada group by 1
			) p
			-- parcelas de compras do mês M compõem a fatura que vence em M+1
			where l.recorrencia_id = cta.recorrencia_id and l.competencia = (p.competencia + interval '1 month')::date and l.valor_real is null;
		end if;
	end if;

	-- pagamento de fatura → lançamento da fatura de cartão do mesmo mês com valor mais próximo
	update transacoes t set lancamento_id = (
		select l.id from lancamentos l
		join contas c on c.recorrencia_id = l.recorrencia_id and c.tipo = 'cartao'
		where l.residencia_id = t.residencia_id and l.competencia = t.competencia and l.status <> 'cancelado'
		order by abs(coalesce(l.valor_real, l.valor_previsto) + t.valor)
		limit 1
	)
	where t.importacao_id = p_imp and t.natureza = 'pagamento_fatura' and t.lancamento_id is null;

	-- baixa dos lançamentos ligados a transações de conta corrente desta importação
	perform recalcular_lancamento(x.lancamento_id)
	from (
		select distinct t.lancamento_id from transacoes t join contas c on c.id = t.conta_id and c.tipo = 'corrente'
		where t.importacao_id = p_imp and t.lancamento_id is not null
	) x;
end $$;


-- Desfaz uma importação e recalcula os lançamentos que ela afetava.
create or replace function desfazer_importacao(p_imp uuid) returns void
language plpgsql security invoker set search_path = public as $$
declare
	imp importacoes;
	cta contas;
	afetados uuid[];
begin
	select * into imp from importacoes where id = p_imp;
	select * into cta from contas where id = imp.conta_id;
	select array_agg(distinct lancamento_id) into afetados
	from transacoes where importacao_id = p_imp and lancamento_id is not null;

	delete from importacoes where id = p_imp;

	if cta.tipo = 'cartao' and cta.recorrencia_id is not null then
		-- refaz a soma das faturas sem esta importação
		update lancamentos set valor_real = null
		where recorrencia_id = cta.recorrencia_id and status <> 'cancelado'
			and competencia in (imp.competencia, (imp.competencia - interval '1 month')::date);
		perform recalcular_fatura(cta.recorrencia_id, imp.competencia);
		perform recalcular_fatura(cta.recorrencia_id, (imp.competencia - interval '1 month')::date);
		perform recalcular_lancamento(x.id) from lancamentos x
		where x.recorrencia_id = cta.recorrencia_id
			and x.competencia in (imp.competencia, (imp.competencia - interval '1 month')::date);
	else
		perform recalcular_lancamento(x) from unnest(afetados) x;
	end if;
end $$;

revoke execute on function recalcular_fatura from public, anon;
grant execute on function recalcular_fatura to authenticated;

-- reparo: refaz valor real e status de todas as faturas de cartão já existentes
select recalcular_fatura(l.recorrencia_id, l.competencia)
from lancamentos l
where exists (select 1 from contas c where c.recorrencia_id = l.recorrencia_id and c.tipo = 'cartao');

select recalcular_lancamento(l.id)
from lancamentos l
where exists (select 1 from contas c where c.recorrencia_id = l.recorrencia_id and c.tipo = 'cartao');
