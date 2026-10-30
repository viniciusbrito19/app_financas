// Datas trafegam como 'YYYY-MM-DD' (sem fuso) e meses como 'YYYY-MM-01'.

const fmtBRL = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' });
const fmtMes = new Intl.DateTimeFormat('pt-BR', { month: 'long', year: 'numeric', timeZone: 'UTC' });

export const brl = (n: number | null | undefined) => fmtBRL.format(Number(n ?? 0));

/** Aceita "1.234,56", "1234,56" ou "1234.56". */
export function parseValor(s: string): number {
	const t = s.trim();
	const n = Number(t.includes(',') ? t.replace(/\./g, '').replace(',', '.') : t);
	return Number.isFinite(n) ? Math.round(n * 100) / 100 : 0;
}

export const valorInput = (n: number | null | undefined) =>
	n == null ? '' : Number(n).toFixed(2).replace('.', ',');

export function hoje(): string {
	const d = new Date();
	return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

export const mesAtual = () => hoje().slice(0, 8) + '01';

export function addMes(mes: string, n: number): string {
	const d = new Date(mes + 'T00:00:00Z');
	d.setUTCMonth(d.getUTCMonth() + n);
	return d.toISOString().slice(0, 10);
}

export function mesLabel(mes: string): string {
	const s = fmtMes.format(new Date(mes + 'T00:00:00Z')).replace(' de ', ' ');
	return s[0].toUpperCase() + s.slice(1);
}

export const dataCurta = (d: string) => `${d.slice(8, 10)}/${d.slice(5, 7)}`;
