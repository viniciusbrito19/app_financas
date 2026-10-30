-- Etapa 1: residência compartilhada, categorias, recorrências e lançamentos mensais

create table residencias (
	id uuid primary key default gen_random_uuid(),
	nome text not null,
	codigo_convite text not null unique default upper(substr(md5(random()::text), 1, 8)),
	created_at timestamptz not null default now()
);

-- membro sem user_id = pessoa da casa sem login (ex.: filho), usada só como titular
create table membros (
	id uuid primary key default gen_random_uuid(),
	residencia_id uuid not null references residencias on delete cascade,
	user_id uuid references auth.users on delete set null,
	nome text not null,
	papel text not null default 'membro' check (papel in ('admin', 'membro')),
	created_at timestamptz not null default now(),
	unique (residencia_id, user_id)
);

create table categorias (
	id uuid primary key default gen_random_uuid(),
	residencia_id uuid not null references residencias on delete cascade,
	nome text not null,
	tipo text not null check (tipo in ('receita', 'despesa')),
	cor text not null default '#64748b',
	icone text,
	parent_id uuid references categorias on delete set null
);

create table recorrencias (
	id uuid primary key default gen_random_uuid(),
	residencia_id uuid not null references residencias on delete cascade,
	tipo text not null check (tipo in ('receita', 'despesa')),
	descricao text not null,
	categoria_id uuid references categorias on delete set null,
	membro_id uuid references membros on delete set null,
	modo_valor text not null default 'fixo' check (modo_valor in ('fixo', 'variavel')),
	valor_base numeric(14, 2) not null default 0 check (valor_base >= 0),
	janela_media int not null default 3 check (janela_media between 1 and 12),
	dia_vencimento int not null default 10 check (dia_vencimento between 1 and 31),
	inicio date not null default date_trunc('month', current_date),
	fim date,
	ativo boolean not null default true,
	created_at timestamptz not null default now()
);

create table lancamentos (
	id uuid primary key default gen_random_uuid(),
	residencia_id uuid not null references residencias on delete cascade,
	recorrencia_id uuid references recorrencias on delete set null,
	competencia date not null check (extract(day from competencia) = 1),
	vencimento date not null,
	tipo text not null check (tipo in ('receita', 'despesa')),
	descricao text not null,
	categoria_id uuid references categorias on delete set null,
	membro_id uuid references membros on delete set null,
	valor_previsto numeric(14, 2) not null default 0,
	valor_real numeric(14, 2),
	status text not null default 'previsto' check (status in ('previsto', 'pago')),
	pago_em date,
	created_at timestamptz not null default now(),
	unique (recorrencia_id, competencia)
);

create index on membros (user_id);
create index on lancamentos (residencia_id, competencia);
create index on recorrencias (residencia_id);
create index on categorias (residencia_id);

-- RLS ---------------------------------------------------------------------

create function sou_membro(r uuid) returns boolean
language sql stable security definer set search_path = public as $$
	select exists (select 1 from membros where residencia_id = r and user_id = auth.uid())
$$;

alter table residencias enable row level security;
alter table membros enable row level security;
alter table categorias enable row level security;
alter table recorrencias enable row level security;
alter table lancamentos enable row level security;

-- residências só são criadas pela RPC criar_residencia
create policy residencia_ler on residencias for select using (sou_membro(id));
create policy residencia_editar on residencias for update using (sou_membro(id));

create policy membros_rw on membros for all using (sou_membro(residencia_id)) with check (sou_membro(residencia_id));
create policy categorias_rw on categorias for all using (sou_membro(residencia_id)) with check (sou_membro(residencia_id));
create policy recorrencias_rw on recorrencias for all using (sou_membro(residencia_id)) with check (sou_membro(residencia_id));
create policy lancamentos_rw on lancamentos for all using (sou_membro(residencia_id)) with check (sou_membro(residencia_id));

-- RPCs --------------------------------------------------------------------

create function criar_residencia(p_nome text, p_meu_nome text) returns uuid
language plpgsql security definer set search_path = public as $$
declare r uuid;
begin
	if auth.uid() is null then raise exception 'não autenticado'; end if;
	insert into residencias (nome) values (p_nome) returning id into r;
	insert into membros (residencia_id, user_id, nome, papel) values (r, auth.uid(), p_meu_nome, 'admin');
	insert into categorias (residencia_id, nome, tipo, cor, icone)
	select r, c.nome, c.tipo, c.cor, c.icone from (values
		('Salário', 'receita', '#16a34a', '💼'),
		('Outras receitas', 'receita', '#0d9488', '💰'),
		('Moradia', 'despesa', '#7c3aed', '🏠'),
		('Condomínio', 'despesa', '#6d28d9', '🏢'),
		('Energia', 'despesa', '#eab308', '⚡'),
		('Água', 'despesa', '#0ea5e9', '💧'),
		('Gás', 'despesa', '#f97316', '🔥'),
		('Internet', 'despesa', '#6366f1', '🌐'),
		('Telefone', 'despesa', '#8b5cf6', '📱'),
		('Cartão de crédito', 'despesa', '#e11d48', '💳'),
		('Mercado', 'despesa', '#22c55e', '🛒'),
		('Transporte', 'despesa', '#f59e0b', '🚗'),
		('Saúde', 'despesa', '#ef4444', '🩺'),
		('Educação', 'despesa', '#3b82f6', '🎓'),
		('Lazer', 'despesa', '#ec4899', '🎉'),
		('Assinaturas', 'despesa', '#a855f7', '📺'),
		('Impostos', 'despesa', '#64748b', '🧾'),
		('Outros', 'despesa', '#71717a', '📦')
	) as c (nome, tipo, cor, icone);
	return r;
end $$;

create function entrar_residencia(p_codigo text, p_meu_nome text) returns uuid
language plpgsql security definer set search_path = public as $$
declare r uuid;
begin
	if auth.uid() is null then raise exception 'não autenticado'; end if;
	select id into r from residencias where codigo_convite = upper(trim(p_codigo));
	if r is null then raise exception 'código inválido'; end if;
	insert into membros (residencia_id, user_id, nome) values (r, auth.uid(), p_meu_nome)
	on conflict (residencia_id, user_id) do nothing;
	return r;
end $$;

-- Gera (idempotente) os lançamentos do mês a partir das recorrências ativas.
-- Variável: previsto = média dos últimos `janela_media` valores reais; sem histórico usa valor_base.
create function gerar_mes(p_res uuid, p_comp date) returns void
language sql security invoker set search_path = public as $$
	insert into lancamentos (residencia_id, recorrencia_id, competencia, vencimento, tipo, descricao, categoria_id, membro_id, valor_previsto)
	select r.residencia_id, r.id, m.c,
		m.c + (least(r.dia_vencimento, extract(day from m.c + interval '1 month - 1 day')::int) - 1),
		r.tipo, r.descricao, r.categoria_id, r.membro_id,
		case when r.modo_valor = 'fixo' then r.valor_base else coalesce((
			select round(avg(h.valor_real), 2) from (
				select l.valor_real from lancamentos l
				where l.recorrencia_id = r.id and l.valor_real is not null and l.competencia < m.c
				order by l.competencia desc limit r.janela_media
			) h
		), r.valor_base) end
	from recorrencias r, (select date_trunc('month', p_comp)::date as c) m
	where r.residencia_id = p_res and r.ativo
		and date_trunc('month', r.inicio) <= m.c and (r.fim is null or r.fim >= m.c)
	on conflict (recorrencia_id, competencia) do nothing
$$;

-- Ao alterar/excluir uma recorrência, descarta lançamentos futuros ainda não tocados;
-- eles são regerados com os novos dados quando o mês for aberto (gerar_mes).
create function limpar_futuros() returns trigger
language plpgsql security invoker set search_path = public as $$
begin
	delete from lancamentos
	where recorrencia_id = old.id and status = 'previsto' and valor_real is null
		and competencia >= date_trunc('month', current_date);
	return coalesce(new, old);
end $$;

create trigger recorrencia_alterada after update on recorrencias
	for each row execute function limpar_futuros();
create trigger recorrencia_excluida before delete on recorrencias
	for each row execute function limpar_futuros();

revoke execute on function criar_residencia, entrar_residencia, gerar_mes from public, anon;
grant execute on function criar_residencia, entrar_residencia, gerar_mes to authenticated;
