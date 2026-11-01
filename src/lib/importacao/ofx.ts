import type { Bruta } from './tipos.ts';

/**
 * TRNAMT fora do padrão: a Caixa usa ponto de milhar e ponto decimal ("-12.856.13");
 * outros bancos usam vírgula decimal ("1.234,56"). O último separador é sempre o decimal.
 */
export function valorOFX(s: string): number {
	const m = s.trim().match(/^(-?)([\d.,]*?)[.,]?(\d{1,2})?$/);
	const n = m && m[3] !== undefined && /[.,]\d{1,2}$/.test(s.trim()) ? Number(`${m[1]}${m[2].replace(/[.,]/g, '')}.${m[3]}`) : Number(s.replace(/[.,]/g, ''));
	if (!Number.isFinite(n)) throw new Error(`Valor inválido no OFX: "${s}"`);
	return n;
}

/** OFX 1.x (SGML), como exportado pelo BB e pela Caixa. */
export function parseOFX(txt: string): Bruta[] {
	const blocos = txt.split(/<STMTTRN>/i).slice(1);
	return blocos
		.map((b) => {
			const tag = (n: string) => b.match(new RegExp(`<${n}>([^<\r\n]*)`, 'i'))?.[1].trim() ?? '';
			const d = tag('DTPOSTED');
			const memo = tag('MEMO');
			const nome = tag('NAME');
			return {
				data: `${d.slice(0, 4)}-${d.slice(4, 6)}-${d.slice(6, 8)}`,
				valor: valorOFX(tag('TRNAMT')),
				descricao: memo.includes(nome) ? memo : [nome, memo].filter(Boolean).join(' '),
				// o FITID do BB pode se repetir; combinado com data e valor fica estável
				id: tag('FITID') ? `${tag('FITID')}|${d.slice(0, 8)}|${tag('TRNAMT')}` : undefined
			};
		})
		.filter((t) => t.valor !== 0 && !/S\s?A\s?L\s?D\s?O/i.test(t.descricao));
}

/** O BB exporta em windows-1252; respeita o cabeçalho CHARSET quando presente. */
export function decodificarOFX(buf: ArrayBuffer): string {
	const cab = new TextDecoder('latin1').decode(buf.slice(0, 400));
	return new TextDecoder(/CHARSET:\s*(UTF-?8|NONE)/i.test(cab) && !/1252/.test(cab) ? 'utf-8' : 'windows-1252').decode(buf);
}
