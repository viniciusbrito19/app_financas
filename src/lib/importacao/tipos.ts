/** Linha crua extraída de um arquivo, antes de classificar. Valor negativo = saída. */
export interface Bruta {
	data: string;
	descricao: string;
	valor: number;
	id?: string;
	parcela?: number;
	parcelas?: number;
}

export interface Fatura {
	vencimento: string;
	total: number;
	/** total da fatura anterior, informado na própria fatura */
	anterior?: number;
	itens: Bruta[];
}
