-- Compras do cartão contam como despesa do mês ANTERIOR ao vencimento da fatura
-- (fatura paga em novembro = gastos de outubro). O lançamento da fatura (pagamento) continua
-- no mês do vencimento; importacoes.competencia segue sendo o mês do vencimento.

-- dados já importados: itens e parcelas projetadas de cartão recuam um mês
update transacoes t set competencia = (t.competencia - interval '1 month')::date
from contas c
where c.id = t.conta_id and c.tipo = 'cartao';

-- previsão da fatura do mês M usa as parcelas projetadas de M-1
create or replace function gerar_mes(p_res uuid, p_comp date) returns void
language sql security invoker set search_path = public as $$
	insert into lancamentos (residencia_id, recorrencia_id, competencia, vencimento, tipo, descricao, categoria_id, membro_id, valor_previsto)
	select r.residencia_id, r.id, m.c,
		m.c + (least(r.dia_vencimento, extract(day from m.c + interval '1 month - 1 day')::int) - 1),
		r.tipo, r.descricao, r.categoria_id, r.membro_id,
		case when r.modo_valor = 'fixo' then r.valor_base else greatest(coalesce((
			select round(avg(h.valor_real), 2) from (
				select l.valor_real from lancamentos l
				where l.recorrencia_id = r.id and l.valor_real is not null and l.competencia < m.c
				order by l.competencia desc limit r.janela_media
			) h
		), r.valor_base), coalesce((
			select -sum(t.valor) from transacoes t join contas c on c.id = t.conta_id
			where c.recorrencia_id = r.id and t.projetada and t.competencia = (m.c - interval '1 month')::date
		), 0)) end
	from recorrencias r, (select date_trunc('month', p_comp)::date as c) m
	where r.residencia_id = p_res and r.ativo
		and date_trunc('month', r.inicio) <= m.c and (r.fim is null or r.fim >= m.c)
	on conflict (recorrencia_id, competencia) do nothing
$$;

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
			-- parcelas de compras do mês M compõem a fatura que vence em M+1
			where l.recorrencia_id = cta.recorrencia_id and l.competencia = (p.competencia + interval '1 month')::date and l.valor_real is null;
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

	-- baixa dos lançamentos ligados a transações de conta corrente desta importação
	perform recalcular_lancamento(x.lancamento_id)
	from (
		select distinct t.lancamento_id from transacoes t join contas c on c.id = t.conta_id and c.tipo = 'corrente'
		where t.importacao_id = p_imp and t.lancamento_id is not null
	) x;
end $$;

