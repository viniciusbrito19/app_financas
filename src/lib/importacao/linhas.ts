/** Item de texto do pdf.js (subconjunto usado). */
export interface ItemTexto {
	str: string;
	transform: number[];
	width: number;
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
