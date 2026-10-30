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
