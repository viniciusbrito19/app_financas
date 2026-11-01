import type { Conta, Importacao } from '../types.ts';
import { parseFaturaCaixa } from './caixa-fatura.ts';
import { decodificarOFX, parseOFX } from './ofx.ts';
import type { Bruta, Fatura } from './tipos.ts';

export interface Leitura {
	formato: Importacao['formato'];
	brutas: Bruta[];
	fatura?: Fatura;
}

/** Conta corrente: extrato OFX (BB, Caixa). Cartão: fatura em PDF, lida no navegador (pdf.js sob demanda). */
export async function lerArquivo(file: File, conta: Conta, senha?: string): Promise<Leitura> {
	const buf = await file.arrayBuffer();
	if (conta.tipo === 'corrente') {
		if (!/\.(ofx|ofc)$/i.test(file.name)) throw new Error('Para conta corrente, exporte o extrato em OFX.');
		return { formato: 'ofx', brutas: parseOFX(decodificarOFX(buf)) };
	}
	if (!/\.pdf$/i.test(file.name)) throw new Error('Para o cartão, use o PDF da fatura.');
	const { linhasPDF } = await import('./pdf.ts');
	const fatura = parseFaturaCaixa(await linhasPDF(buf, senha));
	return { formato: 'pdf_fatura', brutas: fatura.itens, fatura };
}

export const senhaNecessaria = (e: unknown) => (e as { name?: string })?.name === 'PasswordException';
