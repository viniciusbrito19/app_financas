export type Tipo = 'receita' | 'despesa';

export interface Residencia {
	id: string;
	nome: string;
	codigo_convite: string;
}

export interface Membro {
	id: string;
	residencia_id: string;
	user_id: string | null;
	nome: string;
	papel: 'admin' | 'membro';
}

export interface Categoria {
	id: string;
	residencia_id: string;
	nome: string;
	tipo: Tipo;
	cor: string;
	icone: string | null;
	parent_id: string | null;
}

export interface Recorrencia {
	id: string;
	residencia_id: string;
	tipo: Tipo;
	descricao: string;
	categoria_id: string | null;
	membro_id: string | null;
	modo_valor: 'fixo' | 'variavel';
	valor_base: number;
	janela_media: number;
	dia_vencimento: number;
	inicio: string;
	fim: string | null;
	ativo: boolean;
	/** paga em várias vezes no mês: só quita quando a soma atinge o previsto */
	acumula: boolean;
}

export interface Lancamento {
	id: string;
	residencia_id: string;
	recorrencia_id: string | null;
	competencia: string;
	vencimento: string;
	tipo: Tipo;
	descricao: string;
	categoria_id: string | null;
	membro_id: string | null;
	valor_previsto: number;
	valor_real: number | null;
	status: 'previsto' | 'pago';
	pago_em: string | null;
}

export type Meio = 'pix' | 'debito' | 'cartao' | 'boleto' | 'transferencia' | 'tarifa' | 'outro';
export type Natureza = 'gasto' | 'receita' | 'transferencia' | 'pagamento_fatura' | 'ignorada';

export interface Conta {
	id: string;
	residencia_id: string;
	nome: string;
	tipo: 'corrente' | 'cartao';
	banco: 'bb' | 'caixa' | 'outro';
	membro_id: string | null;
	recorrencia_id: string | null;
}

export interface Importacao {
	id: string;
	conta_id: string;
	arquivo: string;
	formato: 'ofx' | 'pdf_extrato' | 'pdf_fatura';
	competencia: string | null;
	total: number | null;
	qtd: number;
	created_at: string;
}

export interface Regra {
	id: string;
	residencia_id: string;
	padrao: string;
	categoria_id: string | null;
	natureza: Natureza | null;
	recorrencia_id: string | null;
}

export interface Transacao {
	id: string;
	residencia_id: string;
	conta_id: string;
	importacao_id: string | null;
	data: string;
	competencia: string;
	descricao: string;
	descricao_norm: string;
	valor: number;
	meio: Meio;
	natureza: Natureza;
	categoria_id: string | null;
	lancamento_id: string | null;
	parcela: number | null;
	parcelas: number | null;
	projetada: boolean;
	nota: string | null;
	/** final do cartão (fatura com titular e adicionais) */
	cartao: string | null;
	hash: string;
}

/** Final de cartão (titular ou adicional) de uma conta-cartão, associado a uma pessoa. */
export interface Cartao {
	id: string;
	residencia_id: string;
	conta_id: string;
	final: string;
	membro_id: string | null;
	apelido: string | null;
}
