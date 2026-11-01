/** Item de texto do pdf.js (subconjunto usado). */
export interface ItemTexto {
	str: string;
	transform: number[];
	width: number;
}

/**
 * Linhas na ordem de leitura de um layout em duas colunas: primeiro a metade esquerda da página,
 * depois a direita. Usado na fatura da Caixa, em que cada coluna continua a seção do cartão anterior.
 */
export function agruparColunas(items: ItemTexto[], largura: number): string[] {
	const meio = largura / 2;
	return [...agruparLinhas(items.filter((i) => i.transform[4] < meio)), ...agruparLinhas(items.filter((i) => i.transform[4] >= meio))];
}

/**
 * Agrupa os itens de texto de uma página em linhas (pela coordenada Y), da esquerda para a direita.
 * Colunas separadas por espaço largo viram " | " para facilitar as regex dos parsers.
 */
export function agruparLinhas(items: ItemTexto[]): string[] {
	const porY = new Map<number, { x: number; w: number; s: string }[]>();
	for (const it of items) {
		if (!it.str?.trim()) continue;
		const y = Math.round(it.transform[5] / 2) * 2;
		(porY.get(y) ?? porY.set(y, []).get(y)!).push({ x: it.transform[4], w: it.width, s: it.str.trim() });
	}
	return [...porY.keys()]
		.sort((a, b) => b - a)
		.map((y) => {
			const cel = porY.get(y)!.sort((a, b) => a.x - b.x);
			return cel.reduce((acc, c, i) => (i === 0 ? c.s : acc + (c.x - (cel[i - 1].x + cel[i - 1].w) > 12 ? ' | ' : ' ') + c.s), '');
		});
}
