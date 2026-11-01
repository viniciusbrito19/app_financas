-- Fatura com vários cartões (titular e adicionais): cada compra guarda o final do cartão,
-- e cada final pode ser associado a uma pessoa da casa.

alter table transacoes add column cartao text;

create table cartoes (
	id uuid primary key default gen_random_uuid(),
	residencia_id uuid not null references residencias on delete cascade,
	conta_id uuid not null references contas on delete cascade,
	final text not null,
	membro_id uuid references membros on delete set null,
	apelido text,
	created_at timestamptz not null default now(),
	unique (conta_id, final)
);

create index on cartoes (residencia_id);
alter table cartoes enable row level security;
create policy cartoes_rw on cartoes for all using (sou_membro(residencia_id)) with check (sou_membro(residencia_id));

-- Análise ganha a pessoa: titular do lançamento; na transação, o dono do cartão ou o titular da conta.
create or replace view v_gastos_categoria with (security_invoker = true) as
select l.residencia_id, l.competencia, l.categoria_id, coalesce(t.meio, 'manual') as meio, coalesce(l.valor_real, l.valor_previsto) as valor,
	l.membro_id
from lancamentos l
left join lateral (select meio from transacoes where lancamento_id = l.id limit 1) t on true
where l.tipo = 'despesa' and (l.status = 'pago' or l.valor_real is not null)
	and not exists (select 1 from contas c where c.recorrencia_id = l.recorrencia_id and c.tipo = 'cartao')
union all
select t.residencia_id, t.competencia, t.categoria_id, t.meio, -t.valor,
	coalesce(k.membro_id, c.membro_id)
from transacoes t
join contas c on c.id = t.conta_id
left join cartoes k on k.conta_id = t.conta_id and k.final = t.cartao
where t.natureza = 'gasto' and not t.projetada
	and (t.lancamento_id is null or c.tipo = 'cartao');
