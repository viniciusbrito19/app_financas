/** Linha crua extraída de um arquivo, antes de classificar. Valor negativo = saída. */
export interface Bruta {
	data: string;
	descricao: string;
	valor: number;
	id?: string;
	parcela?: number;
	parcelas?: number;
	/** final do cartão (titular ou adicional) na fatura */
	cartao?: string;
}

export interface Fatura {
	vencimento: string;
	total: number;
	/** total da fatura anterior, informado na própria fatura */
	anterior?: number;
	/** total impresso por cartão (final → valor), para conferência */
	cartoes?: Record<string, number>;
	itens: Bruta[];
}

/** Texto extraído de um PDF. */
export interface TextoPDF {
	/** linhas da página inteira (cabeçalhos, totais) */
	linhas: string[];
	/** linhas na ordem de leitura em duas colunas (seções por cartão) */
	colunas: string[];
}
