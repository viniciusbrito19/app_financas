import type { Bruta, Fatura } from './tipos.ts';

// Item: "DD/MM DESCRIÇÃO [| NN DE NN] [| CIDADE] | 1.234,56D". A página pode ter duas colunas
// de itens na mesma linha (e a lateral de pontos/encargos), por isso a busca é global na linha.
const ITEM = /(\d{2})\/(\d{2})(?: \| | )([^|]+?)(?: \| (\d{2}) DE (\d{2}))?(?: \| ([^|]+?))? \| ([\d.]+,\d{2}) ?([DC])(?=$| )/g;
const IGNORAR = /TOTAL DA FATURA ANTERIOR|OBRIGADO PELO PAGAMENTO/i;

const num = (s: string) => Number(s.replace(/\./g, '').replace(',', '.'));

/** Fatura do cartão de crédito Caixa (PDF com texto). Débito vira valor negativo; crédito/ajuste, positivo. */
export function parseFaturaCaixa(linhas: string[]): Fatura {
	const iVenc = linhas.findIndex((l) => /^VENCIMENTO$/i.test(l.trim()));
	const venc = linhas.slice(iVenc + 1, iVenc + 4).join(' ').match(/(\d{2})\/(\d{2})\/(\d{4})/);
	const total = linhas.join('\n').match(/Valor total desta fatura R\$ ([\d.]+,\d{2})/i);
	if (iVenc < 0 || !venc || !total) throw new Error('Não parece uma fatura do cartão Caixa (vencimento/total não encontrados).');

	const [, dv, mv, av] = venc;
	const itens: Bruta[] = [];
	for (const l of linhas) {
		for (const m of l.matchAll(ITEM)) {
			const [, d, mes, descBruta, p1, n1, , valor, dc] = m;
			if (IGNORAR.test(descBruta)) continue;
			// parcela pode vir em coluna própria ou colada no fim da descrição
			const pd = descBruta.match(/^(.*?)\s+(\d{2}) DE (\d{2})$/);
			const descricao = (pd ? pd[1] : descBruta).trim();
			const parcela = Number(p1 ?? pd?.[2]) || undefined;
			const parcelas = Number(n1 ?? pd?.[3]) || undefined;
			// ano da compra: meses depois do vencimento são do ano anterior (parcelas antigas)
			const ano = Number(mes) > Number(mv) ? Number(av) - 1 : Number(av);
			itens.push({
				data: `${ano}-${mes}-${d}`,
				descricao: parcela ? `${descricao} ${String(parcela).padStart(2, '0')}/${String(parcelas).padStart(2, '0')}` : descricao,
				valor: dc === 'D' ? -num(valor) : num(valor),
				parcela,
				parcelas
			});
		}
	}
	const anterior = linhas.join('\n').match(/TOTAL DA FATURA ANTERIOR \| ([\d.]+,\d{2})D/i);
	return { vencimento: `${av}-${mv}-${dv}`, total: num(total[1]), anterior: anterior ? num(anterior[1]) : undefined, itens };
}
