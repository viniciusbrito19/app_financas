-- Etapa 2: contas, importação de extratos/faturas, regras de classificação e conciliação

create table contas (
	id uuid primary key default gen_random_uuid(),
	residencia_id uuid not null references residencias on delete cascade,
	nome text not null,
	tipo text not null check (tipo in ('corrente', 'cartao')),
	banco text not null default 'outro' check (banco in ('bb', 'caixa', 'outro')),
	membro_id uuid references membros on delete set null,
	-- cartão: recorrência variável que representa a fatura mensal
	recorrencia_id uuid references recorrencias on delete set null,
	created_at timestamptz not null default now()
);

create table importacoes (
	id uuid primary key default gen_random_uuid(),
	residencia_id uuid not null references residencias on delete cascade,
	conta_id uuid not null references contas on delete cascade,
	arquivo text not null,
	formato text not null check (formato in ('ofx', 'pdf_extrato', 'pdf_fatura')),
	competencia date,
	total numeric(14, 2),
	qtd int not null default 0,
	created_at timestamptz not null default now()
);

create table regras (
	id uuid primary key default gen_random_uuid(),
	residencia_id uuid not null references residencias on delete cascade,
	padrao text not null,
	categoria_id uuid references categorias on delete cascade,
	natureza text check (natureza in ('gasto', 'receita', 'transferencia', 'pagamento_fatura')),
	recorrencia_id uuid references recorrencias on delete cascade,
	created_at timestamptz not null default now(),
	unique (residencia_id, padrao)
);

-- valor negativo = saída
create table transacoes (
	id uuid primary key default gen_random_uuid(),
	residencia_id uuid not null references residencias on delete cascade,
	conta_id uuid not null references contas on delete cascade,
	importacao_id uuid references importacoes on delete cascade,
	data date not null,
	competencia date not null check (extract(day from competencia) = 1),
	descricao text not null,
	descricao_norm text not null,
	valor numeric(14, 2) not null,
	meio text not null default 'outro' check (meio in ('pix', 'debito', 'cartao', 'boleto', 'transferencia', 'tarifa', 'outro')),
	natureza text not null default 'gasto' check (natureza in ('gasto', 'receita', 'transferencia', 'pagamento_fatura')),
	categoria_id uuid references categorias on delete set null,
	lancamento_id uuid references lancamentos on delete set null,
	parcela int,
	parcelas int,
	projetada boolean not null default false,
	hash text not null,
	created_at timestamptz not null default now(),
	unique (conta_id, hash)
);

create index on contas (residencia_id);
create index on importacoes (residencia_id);
create index on regras (residencia_id);
create index on transacoes (residencia_id, competencia);
create index on transacoes (lancamento_id);
create index on transacoes (importacao_id);

alter table contas enable row level security;
alter table importacoes enable row level security;
alter table regras enable row level security;
alter table transacoes enable row level security;

create policy contas_rw on contas for all using (sou_membro(residencia_id)) with check (sou_membro(residencia_id));
create policy importacoes_rw on importacoes for all using (sou_membro(residencia_id)) with check (sou_membro(residencia_id));
create policy regras_rw on regras for all using (sou_membro(residencia_id)) with check (sou_membro(residencia_id));
create policy transacoes_rw on transacoes for all using (sou_membro(residencia_id)) with check (sou_membro(residencia_id));

-- Novas categorias padrão -------------------------------------------------

create function seed_categorias_v2(r uuid) returns void
language sql security definer set search_path = public as $$
	insert into categorias (residencia_id, nome, tipo, cor, icone)
	select r, c.nome, 'despesa', c.cor, c.icone from (values
		('Alimentação fora', '#f43f5e', '🍽️'),
		('Dízimo/Doações', '#0891b2', '🙏'),
		('Financiamento', '#475569', '🏦')
	) as c (nome, cor, icone)
	where not exists (select 1 from categorias x where x.residencia_id = r and x.nome = c.nome)
$$;

select seed_categorias_v2(id) from residencias;

create function seed_categorias_v2_trg() returns trigger
language plpgsql security definer set search_path = public as $$
begin
	perform seed_categorias_v2(new.id);
	return new;
end $$;

-- residências novas (o seed base continua em criar_residencia)
create trigger residencia_seed_v2 after insert on residencias
	for each row execute function seed_categorias_v2_trg();

-- gerar_mes: a fatura do cartão nunca é prevista abaixo das parcelas já comprometidas ----

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
			where c.recorrencia_id = r.id and t.projetada and t.competencia = m.c
		), 0)) end
	from recorrencias r, (select date_trunc('month', p_comp)::date as c) m
	where r.residencia_id = p_res and r.ativo
		and date_trunc('month', r.inicio) <= m.c and (r.fim is null or r.fim >= m.c)
	on conflict (recorrencia_id, competencia) do nothing
$$;

-- Conciliação -------------------------------------------------------------
-- O cliente já grava em transacoes.lancamento_id as conciliações por regra/sugestão.
-- Aqui: transferências entre contas, fatura do cartão, pagamento de fatura e baixa dos lançamentos.

create function conciliar_importacao(p_imp uuid) returns void
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

-- Desfaz uma importação e reabre os lançamentos que ela havia baixado
create function desfazer_importacao(p_imp uuid) returns void
language plpgsql security invoker set search_path = public as $$
declare
	cartao boolean;
begin
	select c.tipo = 'cartao' into cartao from importacoes i join contas c on c.id = i.conta_id where i.id = p_imp;

	update lancamentos l set
		valor_real = case when cartao then null else l.valor_real end,
		status = case when cartao then l.status else 'previsto' end,
		pago_em = case when cartao then l.pago_em else null end
	where l.id in (select lancamento_id from transacoes where importacao_id = p_imp);

	-- baixa por conta corrente: o valor real veio do extrato, exceto se a fatura do cartão já o definiu
	if not cartao then
		update lancamentos l set valor_real = null
		where l.id in (select lancamento_id from transacoes where importacao_id = p_imp and natureza <> 'pagamento_fatura');
	end if;

	delete from importacoes where id = p_imp;
end $$;

-- Gastos realizados por categoria/meio (base da análise).
-- A fatura do cartão é representada pelos seus itens, não pelo lançamento.
create view v_gastos_categoria with (security_invoker = true) as
select l.residencia_id, l.competencia, l.categoria_id, coalesce(t.meio, 'manual') as meio, coalesce(l.valor_real, l.valor_previsto) as valor
from lancamentos l
left join lateral (select meio from transacoes where lancamento_id = l.id limit 1) t on true
where l.tipo = 'despesa' and (l.status = 'pago' or l.valor_real is not null)
	and not exists (select 1 from contas c where c.recorrencia_id = l.recorrencia_id and c.tipo = 'cartao')
union all
select t.residencia_id, t.competencia, t.categoria_id, t.meio, -t.valor
from transacoes t
where t.natureza = 'gasto' and not t.projetada
	and (t.lancamento_id is null or exists (select 1 from contas c where c.id = t.conta_id and c.tipo = 'cartao'));

revoke execute on function conciliar_importacao, desfazer_importacao, seed_categorias_v2 from public, anon;
grant execute on function conciliar_importacao, desfazer_importacao to authenticated;
