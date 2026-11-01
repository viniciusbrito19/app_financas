import type { Regra } from '../types.ts';

/** Regra cujo padrão (mais longo) está contido na descrição normalizada. */
export function regraPara(norm: string, regras: Regra[]): Regra | undefined {
	let melhor: Regra | undefined;
	for (const r of regras) if (norm.includes(r.padrao) && (!melhor || r.padrao.length > melhor.padrao.length)) melhor = r;
	return melhor;
}
