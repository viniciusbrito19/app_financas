-- "Fatura cartão" passa a ficar no mês das COMPRAS (fatura de outubro = compras de outubro,
-- vence em 10/11 e é quitada pelos pagamentos de novembro), como a aba Cartão e a análise.
-- importacoes.competencia continua sendo o mês do vencimento (D): o lançamento ligado é o de D-1.
-- Nada conta duas vezes: totais do mês = só a fatura; análise = só os itens.

-- Total da fatura das compras de p_comp, somando os cartões da recorrência: total do PDF que vence
-- em p_comp+1 ou, na falta, o "total anterior" do PDF seguinte. Sem informação, mantém o valor.
create or replace function recalcular_fatura(p_rec uuid, p_comp date) returns void
language plpgsql security invoker set search_path = public as $$
declare
	total numeric;
begin
	select sum(v) into total from (
		select coalesce(
			(select i.total from importacoes i
				where i.conta_id = c.id and i.competencia = (p_comp + interval '1 month')::date and i.total is not null
				order by i.created_at desc limit 1),
			(select i.total_anterior from importacoes i
				where i.conta_id = c.id and i.competencia = (p_comp + interval '2 months')::date and i.total_anterior is not null
				order by i.created_at desc limit 1)
		) as v
		from contas c where c.recorrencia_id = p_rec and c.tipo = 'cartao'
	) x;
	if total is null then return; end if;
	update lancamentos set valor_real = total
	where recorrencia_id = p_rec and competencia = p_comp and status <> 'cancelado';
end $$;

-- Fatura: vence no mês seguinte; previsto = soma das metas (ou média), nunca abaixo das parcelas do mês.
create or replace function gerar_mes(p_res uuid, p_comp date) returns void
language sql security invoker set search_path = public as $$
	insert into lancamentos as l (residencia_id, recorrencia_id, competencia, vencimento, tipo, descricao, categoria_id, membro_id, valor_previsto)
	select r.residencia_id, r.id, m.c,
		v.mes + (least(r.dia_vencimento, extract(day from v.mes + interval '1 month - 1 day')::int) - 1),
		r.tipo, r.descricao, r.categoria_id, r.membro_id,
		case
			when fat.sim and metas.total is not null then greatest(metas.total, parc.total)
			when r.modo_valor = 'fixo' then r.valor_base
			else greatest(coalesce((
				select round(avg(h.valor_real), 2) from (
					select x.valor_real from lancamentos x
					where x.recorrencia_id = r.id and x.valor_real is not null and x.competencia < m.c
					order by x.competencia desc limit r.janela_media
				) h
			), r.valor_base), parc.total)
		end
	from recorrencias r
	cross join (select date_trunc('month', p_comp)::date as c) m
	cross join lateral (select exists (select 1 from contas c where c.recorrencia_id = r.id and c.tipo = 'cartao') as sim) fat
	cross join lateral (select case when fat.sim then (m.c + interval '1 month')::date else m.c end as mes) v
	cross join lateral (select sum(valor) as total from metas_cartao where residencia_id = r.residencia_id) metas
	cross join lateral (
		select coalesce(-sum(t.valor), 0) as total from transacoes t join contas c on c.id = t.conta_id
		where c.recorrencia_id = r.id and t.projetada and t.competencia = m.c
	) parc
	where r.residencia_id = p_res and r.ativo
		and date_trunc('month', r.inicio) <= m.c and (r.fim is null or r.fim >= m.c)
	on conflict (recorrencia_id, competencia) do update set valor_previsto = excluded.valor_previsto
	where l.status = 'previsto' and l.valor_real is null
		and exists (select 1 from contas c where c.recorrencia_id = l.recorrencia_id and c.tipo = 'cartao')
		and exists (select 1 from metas_cartao mc where mc.residencia_id = l.residencia_id)
$$;

create or replace function conciliar_importacao(p_imp uuid) returns void
language plpgsql security invoker set search_path = public as $$
declare
	imp importacoes;
	cta contas;
	lanc uuid;
	compras date;
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
		compras := (imp.competencia - interval '1 month')::date;
		-- a fatura nova reprojeta todas as parcelas pendentes
		delete from transacoes
		where conta_id = cta.id and projetada and importacao_id <> p_imp and competencia >= compras;

		if cta.recorrencia_id is not null then
			-- lançamento da fatura = mês das compras (vencimento no mês seguinte)
			perform gerar_mes(imp.residencia_id, compras);
			perform gerar_mes(imp.residencia_id, (compras - interval '1 month')::date);
			select id into lanc from lancamentos
			where recorrencia_id = cta.recorrencia_id and competencia = compras and status <> 'cancelado';

			update transacoes set lancamento_id = lanc
			where importacao_id = p_imp and not projetada and lanc is not null;

			-- valor real = soma das faturas de todos os cartões ligados à recorrência (ex.: VISA + Elo)
			perform recalcular_fatura(cta.recorrencia_id, compras);
			perform recalcular_fatura(cta.recorrencia_id, (compras - interval '1 month')::date);
			perform recalcular_lancamento(x.id) from lancamentos x
			where x.recorrencia_id = cta.recorrencia_id and x.competencia in (compras, (compras - interval '1 month')::date);

			-- parcelas de compras do mês M compõem a fatura de M
			update lancamentos l set valor_previsto = greatest(l.valor_previsto, p.total)
			from (
				select competencia, -sum(valor) as total from transacoes
				where conta_id = cta.id and projetada group by 1
			) p
			where l.recorrencia_id = cta.recorrencia_id and l.competencia = p.competencia and l.valor_real is null;
		end if;
	end if;

	-- pagamento de fatura no mês M+1 → fatura das compras de M com valor mais próximo
	update transacoes t set lancamento_id = (
		select l.id from lancamentos l
		join contas c on c.recorrencia_id = l.recorrencia_id and c.tipo = 'cartao'
		where l.residencia_id = t.residencia_id and l.competencia = (t.competencia - interval '1 month')::date and l.status <> 'cancelado'
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

create or replace function desfazer_importacao(p_imp uuid) returns void
language plpgsql security invoker set search_path = public as $$
declare
	imp importacoes;
	cta contas;
	afetados uuid[];
	compras date;
begin
	select * into imp from importacoes where id = p_imp;
	select * into cta from contas where id = imp.conta_id;
	select array_agg(distinct lancamento_id) into afetados
	from transacoes where importacao_id = p_imp and lancamento_id is not null;

	delete from importacoes where id = p_imp;

	if cta.tipo = 'cartao' and cta.recorrencia_id is not null then
		-- refaz a soma das faturas sem esta importação
		compras := (imp.competencia - interval '1 month')::date;
		update lancamentos set valor_real = null
		where recorrencia_id = cta.recorrencia_id and status <> 'cancelado'
			and competencia in (compras, (compras - interval '1 month')::date);
		perform recalcular_fatura(cta.recorrencia_id, compras);
		perform recalcular_fatura(cta.recorrencia_id, (compras - interval '1 month')::date);
		perform recalcular_lancamento(x.id) from lancamentos x
		where x.recorrencia_id = cta.recorrencia_id
			and x.competencia in (compras, (compras - interval '1 month')::date);
	else
		perform recalcular_lancamento(x) from unnest(afetados) x;
	end if;
end $$;

-- dados: lançamentos de fatura recuam para o mês das compras (em dois passos por causa do unique)
update lancamentos l set competencia = (l.competencia - interval '1 month' - interval '100 years')::date
where exists (select 1 from contas c where c.recorrencia_id = l.recorrencia_id and c.tipo = 'cartao');
update lancamentos l set competencia = (l.competencia + interval '100 years')::date
where l.competencia < '1950-01-01'
	and exists (select 1 from contas c where c.recorrencia_id = l.recorrencia_id and c.tipo = 'cartao');

update lancamentos l set
	vencimento = (l.competencia + interval '1 month')::date
		+ (least(r.dia_vencimento, extract(day from l.competencia + interval '2 months - 1 day')::int) - 1),
	valor_real = null
from recorrencias r
where r.id = l.recorrencia_id and exists (select 1 from contas c where c.recorrencia_id = r.id and c.tipo = 'cartao');

update recorrencias r set inicio = least(r.inicio, (select min(competencia) from lancamentos where recorrencia_id = r.id))
where exists (select 1 from contas c where c.recorrencia_id = r.id and c.tipo = 'cartao');

select recalcular_fatura(l.recorrencia_id, l.competencia)
from lancamentos l
where exists (select 1 from contas c where c.recorrencia_id = l.recorrencia_id and c.tipo = 'cartao');

select recalcular_lancamento(l.id)
from lancamentos l
where exists (select 1 from contas c where c.recorrencia_id = l.recorrencia_id and c.tipo = 'cartao');
