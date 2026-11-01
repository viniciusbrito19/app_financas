import type { Bruta, Fatura, TextoPDF } from './tipos.ts';

// Item: "DD/MM DESCRIÇÃO [| NN DE NN] [| CIDADE] | 1.234,56D". Busca global na linha por segurança,
// mas os itens são lidos coluna a coluna (texto.colunas), para saber a qual cartão pertencem.
const ITEM = /(\d{2})\/(\d{2})(?: \| | )([^|]+?)(?: \| (\d{2}) DE (\d{2}))?(?: \| ([^|]+?))? \| ([\d.]+,\d{2}) ?([DC])(?=$| )/g;
const IGNORAR = /TOTAL DA FATURA ANTERIOR|OBRIGADO PELO PAGAMENTO/i;
// título de seção: "YANNE SOUZA C BRITO (Cartão 8190)", "COMPRAS PARCELADAS (Cartão 8190)"
const SECAO = /\(Cart[ãa]o (\d{4})\)/i;
const TOTAL_CARTAO = /Total final \(cart[ãa]o (\d{4})\) \| ([\d.]+,\d{2})D/gi;

const num = (s: string) => Number(s.replace(/\./g, '').replace(',', '.'));

/**
 * Fatura do cartão de crédito Caixa (PDF com texto). Débito vira valor negativo; crédito/ajuste, positivo.
 * Um PDF traz os cartões titular e adicionais; cada item guarda o final do cartão (ajustes gerais ficam sem).
 */
export function parseFaturaCaixa({ linhas, colunas }: TextoPDF): Fatura {
	const iVenc = linhas.findIndex((l) => /^VENCIMENTO$/i.test(l.trim()));
	const venc = linhas.slice(iVenc + 1, iVenc + 4).join(' ').match(/(\d{2})\/(\d{2})\/(\d{4})/);
	const tudo = linhas.join('\n');
	const total = tudo.match(/Valor total desta fatura R\$ ([\d.]+,\d{2})/i);
	if (iVenc < 0 || !venc || !total) throw new Error('Não parece uma fatura do cartão Caixa (vencimento/total não encontrados).');

	const [, dv, mv, av] = venc;
	const itens: Bruta[] = [];
	let cartao: string | undefined;
	for (const l of colunas) {
		const secao = l.match(SECAO);
		if (secao) cartao = secao[1];
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
				parcelas,
				cartao
			});
		}
	}
	const anterior = tudo.match(/TOTAL DA FATURA ANTERIOR \| ([\d.]+,\d{2})D/i);
	const cartoes = Object.fromEntries([...colunas.join('\n').matchAll(TOTAL_CARTAO)].map(([, f, v]) => [f, num(v)]));
	return { vencimento: `${av}-${mv}-${dv}`, total: num(total[1]), anterior: anterior ? num(anterior[1]) : undefined, cartoes, itens };
}
