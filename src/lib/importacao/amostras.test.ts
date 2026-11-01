// Testes contra arquivos reais em amostras/ (fora do git). Pulados quando a pasta não existe (CI).
import fs from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import type { Conta } from '../types.ts';
import { parseFaturaCaixa } from './caixa-fatura.ts';
import { agruparColunas, agruparLinhas, type ItemTexto } from './linhas.ts';
import { decodificarOFX, parseOFX } from './ofx.ts';
import { montarItens, projetarParcelas } from './previa.ts';
import type { TextoPDF } from './tipos.ts';

const DIR = path.resolve('amostras');
const arquivos = fs.existsSync(DIR) ? fs.readdirSync(DIR) : [];
const achar = (re: RegExp) => arquivos.filter((f) => re.test(f)).map((f) => path.join(DIR, f));

/** Mesmo que textoPDF (pdf.ts), com o build legado do pdf.js para Node. */
async function textoPDFNode(arquivo: string): Promise<TextoPDF> {
	const { getDocument } = await import('pdfjs-dist/legacy/build/pdf.mjs');
	const doc = await getDocument({ data: new Uint8Array(fs.readFileSync(arquivo)), verbosity: 0 }).promise;
	const texto: TextoPDF = { linhas: [], colunas: [] };
	for (let p = 1; p <= doc.numPages; p++) {
		const pagina = await doc.getPage(p);
		const items = (await pagina.getTextContent()).items as ItemTexto[];
		texto.linhas.push(...agruparLinhas(items));
		texto.colunas.push(...agruparColunas(items, pagina.view[2]));
	}
	return texto;
}

const conta = (tipo: Conta['tipo']): Conta => ({ id: 'c', residencia_id: 'r', nome: '', tipo, banco: 'caixa', membro_id: null, recorrencia_id: null });
const centavos = (n: number) => Math.round(n * 100);

describe.skipIf(!arquivos.length)('amostras reais', { timeout: 30_000 }, () => {
	for (const f of achar(/fatura.*\.pdf$/i))
		it(`fatura: ${path.basename(f)}`, async () => {
			const fat = parseFaturaCaixa(await textoPDFNode(f));
			const soma = -fat.itens.reduce((s, i) => s + i.valor, 0);
			expect(fat.itens.length).toBeGreaterThan(0);
			expect(fat.anterior).toBeGreaterThan(0);
			expect(fat.vencimento).toMatch(/^\d{4}-\d{2}-\d{2}$/);
			// a soma dos itens precisa fechar com o total da fatura
			expect(centavos(soma)).toBe(centavos(fat.total));
			// e a soma de cada cartão com o "Total final (cartão XXXX)" impresso
			const porCartao: Record<string, number> = {};
			for (const i of fat.itens.filter((i) => i.cartao)) porCartao[i.cartao!] = (porCartao[i.cartao!] ?? 0) - i.valor;
			expect(Object.keys(fat.cartoes ?? {}).length).toBeGreaterThan(0);
			expect(Object.fromEntries(Object.entries(porCartao).map(([k, v]) => [k, centavos(v)]))).toEqual(
				Object.fromEntries(Object.entries(fat.cartoes!).map(([k, v]) => [k, centavos(v)]))
			);
			console.log('por cartão:', porCartao, '| sem cartão (ajustes):', fat.itens.filter((i) => !i.cartao).map((i) => i.descricao));
			const itens = montarItens(fat.itens, conta('cartao'), [], fat.vencimento.slice(0, 8) + '01');
			expect(new Set(itens.map((i) => i.hash)).size).toBe(itens.length);
			console.log(
				`${path.basename(f)}: venc ${fat.vencimento}, total ${fat.total}, ${fat.itens.length} itens,`,
				`${itens.filter((i) => i.parcela).length} parcelados, ${projetarParcelas(itens).length} parcelas projetadas`
			);
		});

	for (const f of achar(/\.ofx$/i))
		it(`ofx: ${path.basename(f)}`, () => {
			const brutas = parseOFX(decodificarOFX(fs.readFileSync(f).buffer as ArrayBuffer));
			expect(brutas.length).toBeGreaterThan(0);
			expect(brutas.every((b) => /^\d{4}-\d{2}-\d{2}$/.test(b.data) && Number.isFinite(b.valor))).toBe(true);
			const itens = montarItens(brutas, { ...conta('corrente'), banco: 'bb' }, []);
			expect(new Set(itens.map((i) => i.hash)).size).toBe(itens.length);
			// nenhuma descrição com caractere de encoding quebrado
			expect(itens.some((i) => i.descricao.includes('�'))).toBe(false);
			const resumo = Object.groupBy(itens, (i) => `${i.natureza}/${i.meio}`);
			console.log(path.basename(f), Object.fromEntries(Object.entries(resumo).map(([k, v]) => [k, v!.length])));
		});
});
