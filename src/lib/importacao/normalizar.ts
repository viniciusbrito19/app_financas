import type { Meio, Natureza } from '../types.ts';

/** Descrição comparável entre extratos: sem acentos, datas, horas, documentos e parcelas. */
export function normalizar(s: string): string {
	return s
		.normalize('NFD')
		.replace(/[\u0300-\u036f]/g, '')
		.toUpperCase()
		.replace(/PARC(ELA)?\s*\d{1,2}\s*(DE|\/)\s*\d{1,2}/g, ' ')
		.replace(/\b\d{1,2}\/\d{1,2}(\/\d{2,4})?\b/g, ' ')
		.replace(/\b\d{1,2}:\d{2}(:\d{2})?\b/g, ' ')
		.replace(/\b\d{4,}\b/g, ' ')
		.replace(/[^A-Z0-9 ]+/g, ' ')
		.replace(/\s+/g, ' ')
		.trim();
}

const MEIOS: [RegExp, Meio][] = [
	[/\bPIX\b/, 'pix'],
	[/TARIFA|\bTAR\b|JUROS|\bIOF\b|ENCARGO|ANUIDADE|CESTA (DE )?SERVICO/, 'tarifa'],
	[/\bTED\b|\bDOC\b|TRANSF/, 'transferencia'],
	[/DEB(ITO)? ?AUT|DEBITO|COMPRA|\bCARTAO\b|SAQUE/, 'debito'],
	[/BOLETO|PAGTO|PAGAMENTO|\bPAG\b|CONVENIO|PRESTACAO/, 'boleto']
];

export function meioDe(norm: string): Meio {
	return MEIOS.find(([re]) => re.test(norm))?.[1] ?? 'outro';
}

/** Aplicações/resgates (BB Rende Fácil, CDB, poupança) movem dinheiro para investimentos: não são gasto nem receita. */
const INVESTIMENTO = /APLICACAO|RESGATE|RENDE FACIL|\bCDB\b|POUPANCA|\bLCI\b|\bLCA\b|TESOURO DIRETO/;

export function naturezaDe(norm: string, valor: number): Natureza {
	if (INVESTIMENTO.test(norm)) return 'transferencia';
	if (valor < 0 && /FATURA (DO |DE )?CARTAO|CARTAO DE CREDITO|CARTOES DE CREDITO|CART CRED|^CARTAO CX\b/.test(norm)) return 'pagamento_fatura';
	return valor > 0 ? 'receita' : 'gasto';
}
