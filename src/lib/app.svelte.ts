import type { User } from '@supabase/supabase-js';
import { mesAtual } from './format.ts';
import { ok, sb } from './supabase.ts';
import type { Cartao, Categoria, Conta, Membro, Natureza, Recorrencia, Regra, Residencia } from './types.ts';

/** Estado global da sessão: usuário, residência ativa e cadastros auxiliares. */
export const app = $state({
	user: null as User | null,
	res: null as Residencia | null,
	membros: [] as Membro[],
	cats: [] as Categoria[],
	contas: [] as Conta[],
	/** finais de cartão (titular/adicionais) e a pessoa de cada um */
	cartoes: [] as Cartao[],
	recs: [] as Recorrencia[],
	regras: [] as Regra[],
	/** transações de gasto ainda sem categoria (badge da aba Importar) */
	pendentes: 0,
	mes: mesAtual()
});

export async function carregarResidencia(user: User) {
	app.user = user;
	const m = ok(
		await sb.from('membros').select('residencias(*)').eq('user_id', user.id).limit(1).maybeSingle()
	) as { residencias: Residencia } | null;
	app.res = m?.residencias ?? null;
	if (app.res) await carregarCadastros();
}

export async function carregarCadastros() {
	const id = app.res!.id;
	const [membros, cats, contas, recs, regras, cartoes] = await Promise.all([
		sb.from('membros').select('*').eq('residencia_id', id).order('created_at'),
		sb.from('categorias').select('*').eq('residencia_id', id).order('nome'),
		sb.from('contas').select('*').eq('residencia_id', id).order('created_at'),
		sb.from('recorrencias').select('*').eq('residencia_id', id).order('descricao'),
		sb.from('regras').select('*').eq('residencia_id', id).order('padrao'),
		sb.from('cartoes').select('*').eq('residencia_id', id).order('final'),
		contarPendentes()
	]);
	app.membros = ok(membros) as Membro[];
	app.cats = ok(cats) as Categoria[];
	app.contas = ok(contas) as Conta[];
	app.recs = ok(recs) as Recorrencia[];
	app.regras = ok(regras) as Regra[];
	app.cartoes = ok(cartoes) as Cartao[];
}

export async function contarPendentes() {
	const { count } = await sb
		.from('transacoes')
		.select('id', { count: 'exact', head: true })
		.eq('residencia_id', app.res!.id)
		.eq('natureza', 'gasto')
		.eq('projetada', false)
		.is('categoria_id', null);
	app.pendentes = count ?? 0;
}

export function limpar() {
	Object.assign(app, { user: null, res: null, membros: [], cats: [], contas: [], cartoes: [], recs: [], regras: [], pendentes: 0 });
}

export const cat = (id: string | null) => app.cats.find((c) => c.id === id);
export const membro = (id: string | null) => app.membros.find((m) => m.id === id);
export const conta = (id: string | null) => app.contas.find((c) => c.id === id);
/** Recorrência paga no cartão (embutida na fatura): acompanhada pelos itens, fora dos totais. */
export const embutida = (recorrenciaId: string | null) => !!app.recs.find((r) => r.id === recorrenciaId)?.cartao_conta_id;

export const MEIOS = { pix: 'Pix', debito: 'Débito', cartao: 'Cartão', boleto: 'Boleto', transferencia: 'Transf.', tarifa: 'Tarifa', outro: 'Outro', manual: 'Manual' } as const;
export const NATUREZAS = { gasto: 'Gasto', receita: 'Receita', transferencia: 'Transferência', pagamento_fatura: 'Pag. fatura', ignorada: 'Não contar' } as const;
/** naturezas que entram em totais e análise */
export const contaNoTotal = (n: Natureza) => n === 'gasto' || n === 'receita';

/** "•• 8190 · Yanne" — final do cartão e a pessoa associada, quando houver. */
export function rotuloCartao(contaId: string, final: string | null) {
	if (!final) return 'Ajustes da fatura';
	const k = app.cartoes.find((c) => c.conta_id === contaId && c.final === final);
	const quem = k?.apelido || membro(k?.membro_id ?? null)?.nome;
	return `•• ${final}${quem ? ` · ${quem}` : ''}`;
}
