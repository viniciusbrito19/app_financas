-- Cartão: meta mensal de gasto por categoria (previsto) x itens da fatura daquela categoria (realizado).
-- Substitui as recorrentes "pagas no cartão" (cartao_conta_id) e o vínculo avulso→itens (avulso_id).
-- Nada conta duas vezes: nos totais do mês entra só o lançamento da fatura; na análise, só os itens.

create table metas_cartao (
	id uuid primary key default gen_random_uuid(),
	residencia_id uuid not null references residencias on delete cascade,
	categoria_id uuid not null references categorias on delete cascade,
	valor numeric(14, 2) not null check (valor >= 0),
	unique (residencia_id, categoria_id)
);

alter table metas_cartao enable row level security;
create policy metas_cartao_rw on metas_cartao for all using (sou_membro(residencia_id)) with check (sou_membro(residencia_id));

-- recorrentes "no cartão" → meta da categoria (os lançamentos delas eram só acompanhamento)
insert into metas_cartao (residencia_id, categoria_id, valor)
select residencia_id, categoria_id, sum(valor_base) from recorrencias
where cartao_conta_id is not null and categoria_id is not null
group by 1, 2
on conflict (residencia_id, categoria_id) do update set valor = metas_cartao.valor + excluded.valor;

-- apaga os lançamentos antes: excluir a recorrência os transformaria em avulsos (on delete set null)
delete from lancamentos l using recorrencias r where r.id = l.recorrencia_id and r.cartao_conta_id is not null;
delete from recorrencias where cartao_conta_id is not null;

-- avulsos vinculados a itens do cartão → meta da categoria
insert into metas_cartao (residencia_id, categoria_id, valor)
select l.residencia_id, l.categoria_id, sum(l.valor_previsto) from lancamentos l
where l.categoria_id is not null and exists (select 1 from transacoes t where t.avulso_id = l.id)
group by 1, 2
on conflict (residencia_id, categoria_id) do update set valor = metas_cartao.valor + excluded.valor;

delete from lancamentos l
where l.categoria_id is not null and exists (select 1 from transacoes t where t.avulso_id = l.id);

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

alter table transacoes drop column avulso_id;
alter table recorrencias drop column cartao_conta_id;

-- Fatura do cartão: previsto = soma das metas (nunca abaixo das parcelas já compromissadas).
-- Ainda sem valor real, é atualizado ao reabrir o mês (metas alteradas). Demais lançamentos: intocados.
create or replace function gerar_mes(p_res uuid, p_comp date) returns void
language sql security invoker set search_path = public as $$
	insert into lancamentos as l (residencia_id, recorrencia_id, competencia, vencimento, tipo, descricao, categoria_id, membro_id, valor_previsto)
	select r.residencia_id, r.id, m.c,
		m.c + (least(r.dia_vencimento, extract(day from m.c + interval '1 month - 1 day')::int) - 1),
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
	cross join lateral (select sum(valor) as total from metas_cartao where residencia_id = r.residencia_id) metas
	cross join lateral (
		select coalesce(-sum(t.valor), 0) as total from transacoes t join contas c on c.id = t.conta_id
		where c.recorrencia_id = r.id and t.projetada and t.competencia = (m.c - interval '1 month')::date
	) parc
	where r.residencia_id = p_res and r.ativo
		and date_trunc('month', r.inicio) <= m.c and (r.fim is null or r.fim >= m.c)
	on conflict (recorrencia_id, competencia) do update set valor_previsto = excluded.valor_previsto
	where l.status = 'previsto' and l.valor_real is null
		and exists (select 1 from contas c where c.recorrencia_id = l.recorrencia_id and c.tipo = 'cartao')
		and exists (select 1 from metas_cartao mc where mc.residencia_id = l.residencia_id)
$$;
