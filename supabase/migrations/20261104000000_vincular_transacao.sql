-- Conciliação manual depois da importação: ligar/desligar uma transação de um lançamento previsto.

-- Recalcula status e valor real de um lançamento a partir das transações de conta corrente ligadas a ele.
-- Itens de cartão não baixam lançamento (compõem a fatura); a fatura mantém o valor real vindo do PDF.
create function recalcular_lancamento(p_lanc uuid) returns void
language plpgsql security invoker set search_path = public as $$
begin
	if p_lanc is null then return; end if;
	update lancamentos l set
		status = case when s.n > 0 then 'pago' else 'previsto' end,
		pago_em = s.data,
		valor_real = case
			when s.n > 0 and s.fatura then coalesce(l.valor_real, s.total)
			when s.n > 0 then s.total
			when exists (select 1 from contas c where c.recorrencia_id = l.recorrencia_id and c.tipo = 'cartao') then l.valor_real
			else null
		end
	from (
		select count(*) as n, abs(sum(t.valor)) as total, max(t.data) as data, coalesce(bool_or(t.natureza = 'pagamento_fatura'), false) as fatura
		from transacoes t join contas c on c.id = t.conta_id and c.tipo = 'corrente'
		where t.lancamento_id = p_lanc
	) s
	where l.id = p_lanc;
end $$;

create function vincular_transacao(p_tx uuid, p_lanc uuid) returns void
language plpgsql security invoker set search_path = public as $$
declare
	antigo uuid;
begin
	select lancamento_id into antigo from transacoes where id = p_tx;
	if antigo is not distinct from p_lanc then return; end if;
	update transacoes set lancamento_id = p_lanc where id = p_tx;
	perform recalcular_lancamento(antigo);
	perform recalcular_lancamento(p_lanc);
end $$;

revoke execute on function recalcular_lancamento, vincular_transacao from public, anon;
grant execute on function recalcular_lancamento, vincular_transacao to authenticated;
