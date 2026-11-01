import { addMes } from '../format.ts';
import type { Conta, Lancamento, Regra, Transacao } from '../types.ts';
import { regraPara } from './classificar.ts';
import { meioDe, naturezaDe, normalizar } from './normalizar.ts';
import type { Bruta } from './tipos.ts';

export type Item = Omit<Transacao, 'id' | 'residencia_id' | 'importacao_id'> & {
	regra?: Regra;
	sugerido?: boolean;
	duplicada?: boolean;
};

/** Converte linhas cruas em itens classificados. Cartão: competência = mês do vencimento da fatura. */
export function montarItens(brutas: Bruta[], conta: Conta, regras: Regra[], competenciaFatura?: string): Item[] {
	const vistos = new Map<string, number>();
	return brutas.map((b) => {
		const norm = normalizar(b.descricao);
		const chave = `${b.data}|${b.valor.toFixed(2)}|${norm}|${b.parcela ?? ''}`;
		const n = vistos.get(chave) ?? 0;
		vistos.set(chave, n + 1);
		const cartao = conta.tipo === 'cartao';
		const it: Item = {
			conta_id: conta.id,
			data: b.data,
			competencia: competenciaFatura ?? b.data.slice(0, 8) + '01',
			descricao: b.descricao,
			descricao_norm: norm,
			valor: b.valor,
			meio: cartao ? 'cartao' : meioDe(norm),
			natureza: cartao ? 'gasto' : naturezaDe(norm, b.valor),
			categoria_id: null,
			lancamento_id: null,
			parcela: b.parcela ?? null,
			parcelas: b.parcelas ?? null,
			projetada: false,
			hash: b.id ?? `${chave}|${n}`
		};
		return aplicarRegra(it, regras);
	});
}

export function aplicarRegra(it: Item, regras: Regra[]): Item {
	const r = regraPara(it.descricao_norm, regras);
	if (r) {
		it.regra = r;
		if (r.categoria_id) it.categoria_id = r.categoria_id;
		if (r.natureza) it.natureza = r.natureza;
	}
	return it;
}

/**
 * Liga itens de conta corrente a lançamentos previstos: primeiro pela recorrência da regra,
 * depois por sugestão (mesmo tipo, valor ±10%, vencimento ±5 dias). As sugestões são atribuídas
 * pelo melhor encaixe global (menor diferença de valor, depois de data), cada lançamento uma vez.
 */
export function sugerirConciliacao(itens: Item[], lancs: Lancamento[], conta: Conta) {
	if (conta.tipo === 'cartao') return;
	const usados = new Set<string>();
	const candidatos: { it: Item; l: Lancamento; nota: number }[] = [];
	for (const it of itens) {
		it.lancamento_id = null;
		it.sugerido = false;
		if (it.duplicada || (it.natureza !== 'gasto' && it.natureza !== 'receita')) continue;
		const recId = it.regra?.recorrencia_id;
		if (recId) {
			const l = lancs.find((l) => l.recorrencia_id === recId && l.competencia === it.competencia && !usados.has(l.id));
			if (l) {
				usados.add(l.id);
				it.lancamento_id = l.id;
			}
			continue;
		}
		for (const l of lancs) {
			if (l.status !== 'previsto' || !l.recorrencia_id || l.tipo !== (it.valor < 0 ? 'despesa' : 'receita')) continue;
			const difValor = Math.abs(Math.abs(it.valor) - l.valor_previsto) / (l.valor_previsto || 1);
			const difDias = Math.abs(dias(l.vencimento) - dias(it.data));
			if (difValor <= 0.1 && difDias <= 5) candidatos.push({ it, l, nota: difValor + difDias / 1000 });
		}
	}
	for (const { it, l } of candidatos.sort((a, b) => a.nota - b.nota)) {
		if (it.lancamento_id || usados.has(l.id)) continue;
		usados.add(l.id);
		it.lancamento_id = l.id;
		it.sugerido = true;
	}
}

/** Parcelas restantes (n/N, n < N) projetadas nas faturas seguintes. */
export function projetarParcelas(itens: Item[]): Item[] {
	return itens.flatMap((it) =>
		it.parcela && it.parcelas && it.parcela < it.parcelas && !it.duplicada
			? Array.from({ length: it.parcelas - it.parcela }, (_, k) => ({
					...it,
					competencia: addMes(it.competencia, k + 1),
					parcela: it.parcela! + k + 1,
					projetada: true,
					lancamento_id: null,
					hash: `proj|${it.competencia}|${it.hash}|${k + 1}`
				}))
			: []
	);
}

/** Campos gravados em `transacoes`. */
export const paraLinha = ({ regra, sugerido, duplicada, ...t }: Item) => t;

const dias = (d: string) => Date.parse(d + 'T00:00:00Z') / 864e5;
