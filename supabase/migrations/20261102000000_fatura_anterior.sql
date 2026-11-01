-- A fatura informa o total da fatura anterior: ele é o valor real do lançamento do mês anterior
-- (mais confiável que somar os débitos "CARTAO CX" do extrato, que podem incluir outros pagamentos).

alter table importacoes add column total_anterior numeric(14, 2);

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
		-- a fatura nova reprojeta todas as parcelas pendentes
		delete from transacoes
		where conta_id = cta.id and projetada and importacao_id <> p_imp and competencia >= imp.competencia;

		if cta.recorrencia_id is not null then
			update lancamentos set valor_real = imp.total
			where recorrencia_id = cta.recorrencia_id and competencia = imp.competencia
			returning id into lanc;

			update transacoes set lancamento_id = lanc
			where importacao_id = p_imp and not projetada and lanc is not null;

			if imp.total_anterior is not null then
				perform gerar_mes(imp.residencia_id, (imp.competencia - interval '1 month')::date);
				update lancamentos set valor_real = imp.total_anterior
				where recorrencia_id = cta.recorrencia_id and competencia = (imp.competencia - interval '1 month')::date;
			end if;

			update lancamentos l set valor_previsto = greatest(l.valor_previsto, p.total)
			from (
				select competencia, -sum(valor) as total from transacoes
				where conta_id = cta.id and projetada group by 1
			) p
			where l.recorrencia_id = cta.recorrencia_id and l.competencia = p.competencia and l.valor_real is null;
		end if;
	end if;

	-- pagamento de fatura → lançamento da fatura de cartão do mesmo mês com valor mais próximo
	update transacoes t set lancamento_id = (
		select l.id from lancamentos l
		join contas c on c.recorrencia_id = l.recorrencia_id and c.tipo = 'cartao'
		where l.residencia_id = t.residencia_id and l.competencia = t.competencia
		order by abs(coalesce(l.valor_real, l.valor_previsto) + t.valor)
		limit 1
	)
	where t.importacao_id = p_imp and t.natureza = 'pagamento_fatura' and t.lancamento_id is null;

	-- lançamentos ligados a transações de conta corrente viram pagos com o valor real
	update lancamentos l set
		status = 'pago',
		pago_em = s.data,
		valor_real = case when s.fatura then coalesce(l.valor_real, s.total) else s.total end
	from (
		select t.lancamento_id, abs(sum(t.valor)) as total, max(t.data) as data, bool_or(t.natureza = 'pagamento_fatura') as fatura
		from transacoes t join contas c on c.id = t.conta_id and c.tipo = 'corrente'
		where t.lancamento_id in (select lancamento_id from transacoes where importacao_id = p_imp)
		group by 1
	) s
	where l.id = s.lancamento_id;
end $$;
