import { describe, expect, it } from 'vitest';
import type { Conta, Lancamento, Regra } from '../types.ts';
import { meioDe, naturezaDe, normalizar } from './normalizar.ts';
import { parseOFX, valorOFX } from './ofx.ts';
import { montarItens, paraLinha, projetarParcelas, sugerirConciliacao } from './previa.ts';

const conta: Conta = { id: 'c1', residencia_id: 'r', nome: 'BB', tipo: 'corrente', banco: 'bb', membro_id: null, recorrencia_id: null };

describe('normalizar', () => {
	it('remove acentos, datas, horas e documentos', () => {
		expect(normalizar('Pix - Enviado 12/10 10:30 Padaria Pão & Cia')).toBe('PIX ENVIADO PADARIA PAO CIA');
		expect(normalizar('PAGTO CONTA 123456789 Celular')).toBe('PAGTO CONTA CELULAR');
		expect(normalizar('NETFLIX PARC 03/10')).toBe('NETFLIX');
	});
	it('deduz meio e natureza', () => {
		expect(meioDe('PIX ENVIADO FULANO')).toBe('pix');
		expect(meioDe('TARIFA PACOTE SERVICOS')).toBe('tarifa');
		expect(meioDe('DEB AUTOMATICO ENERGIA')).toBe('debito');
		expect(meioDe('PAGAMENTO DE BOLETO')).toBe('boleto');
		expect(naturezaDe('PAGTO FATURA CARTAO', -900)).toBe('pagamento_fatura');
		expect(naturezaDe('SALARIO', 5000)).toBe('receita');
		expect(naturezaDe('PAGAMENTO FATURA DE GAS CONSIGAZ DISTRI DE GAS', -23.6)).toBe('gasto');
		expect(naturezaDe('CARTAO CX CARTOES DE CREDITO', -12856.13)).toBe('pagamento_fatura');
		expect(naturezaDe('BB RENDE FACIL RENDE FACIL', 130)).toBe('transferencia');
		expect(naturezaDe('APLICACAO BB CDB DI', -7000)).toBe('transferencia');
	});
});

describe('OFX', () => {
	const ofx = [
		'OFXHEADER:100',
		'<OFX><BANKMSGSRSV1><STMTTRNRS><STMTRS><BANKTRANLIST>',
		'<STMTTRN><TRNTYPE>OTHER<DTPOSTED>20261001120000[-3:BRT]<TRNAMT>0.00<FITID>1<MEMO>Saldo Anterior</STMTTRN>',
		'<STMTTRN><TRNTYPE>DEBIT<DTPOSTED>20261005120000[-3:BRT]<TRNAMT>-50.00<FITID>2<MEMO>Pix - Enviado 05/10 09:12 Igreja</STMTTRN>',
		'<STMTTRN><TRNTYPE>CREDIT<DTPOSTED>20261005<TRNAMT>8500.00<FITID>3<NAME>Proventos<MEMO>Proventos Salario</STMTTRN>',
		'</BANKTRANLIST></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>'
	].join('\n');

	it('entende os formatos de valor de BB e Caixa', () => {
		expect(['-12.856.13', '15.992.38', '-239.14', '50.00', '8500', '1.234,56', '-0,5'].map(valorOFX)).toEqual([
			-12856.13, 15992.38, -239.14, 50, 8500, 1234.56, -0.5
		]);
	});

	it('lê transações e ignora saldo', () => {
		const t = parseOFX(ofx);
		expect(t).toHaveLength(2);
		expect(t[0]).toMatchObject({ data: '2026-10-05', valor: -50, descricao: 'Pix - Enviado 05/10 09:12 Igreja' });
		expect(t[1].descricao).toBe('Proventos Salario');
	});
});

describe('prévia', () => {
	const regras: Regra[] = [
		{ id: 'g1', residencia_id: 'r', padrao: 'IGREJA', categoria_id: 'dizimo', natureza: null, recorrencia_id: null },
		{ id: 'g2', residencia_id: 'r', padrao: 'PROVENTOS', categoria_id: null, natureza: null, recorrencia_id: 'rec-sal' }
	];
	const lanc = (p: Partial<Lancamento>): Lancamento => ({
		id: 'x',
		residencia_id: 'r',
		recorrencia_id: 'rec',
		competencia: '2026-10-01',
		vencimento: '2026-10-10',
		tipo: 'despesa',
		descricao: '',
		categoria_id: null,
		membro_id: null,
		valor_previsto: 100,
		valor_real: null,
		status: 'previsto',
		pago_em: null,
		...p
	});

	it('aplica regras, gera hash estável com ordinal e concilia', () => {
		const itens = montarItens(
			[
				{ data: '2026-10-05', valor: -50, descricao: 'Pix Enviado Igreja' },
				{ data: '2026-10-05', valor: -50, descricao: 'Pix Enviado Igreja' },
				{ data: '2026-10-05', valor: 8500, descricao: 'Proventos' },
				{ data: '2026-10-09', valor: -104, descricao: 'Deb Aut Energia' }
			],
			conta,
			regras
		);
		expect(itens[0].categoria_id).toBe('dizimo');
		expect(itens[0].hash).not.toBe(itens[1].hash);
		sugerirConciliacao(itens, [lanc({ id: 'sal', recorrencia_id: 'rec-sal', tipo: 'receita', valor_previsto: 8000 }), lanc({ id: 'luz' })], conta);
		expect(itens[2]).toMatchObject({ lancamento_id: 'sal', sugerido: false });
		expect(itens[3]).toMatchObject({ lancamento_id: 'luz', sugerido: true });
		expect(itens[0].lancamento_id).toBeNull();
	});

	it('sugere pelo melhor encaixe, não pelo primeiro candidato', () => {
		// caso real: Pix 2.600 (dízimo) e boleto 2.521,74 (escola) estão a menos de 10% um do outro
		const itens = montarItens(
			[
				{ data: '2026-10-05', valor: -2600, descricao: 'Pix Enviado Igreja Shalom' },
				{ data: '2026-10-06', valor: -2521.74, descricao: 'Pagamento de Boleto Centro de Ensino' }
			],
			conta,
			[]
		);
		sugerirConciliacao(itens, [lanc({ id: 'escola', valor_previsto: 2521.74, vencimento: '2026-10-05' }), lanc({ id: 'dizimo', valor_previsto: 2600, vencimento: '2026-10-05' })], conta);
		expect(itens.map((i) => i.lancamento_id)).toEqual(['dizimo', 'escola']);
	});

	it('item conciliado sem categoria herda a do lançamento (e perde se a conciliação sair)', () => {
		const itens = montarItens([{ data: '2026-10-28', valor: -325.43, descricao: 'Pagto Energia Eletrica Neoenergia' }], conta, []);
		const luz = lanc({ id: 'luz', categoria_id: 'energia', valor_previsto: 300, vencimento: '2026-10-25' });
		sugerirConciliacao(itens, [luz], conta);
		expect(itens[0]).toMatchObject({ lancamento_id: 'luz', categoria_id: 'energia' });
		sugerirConciliacao(itens, [], conta);
		expect(itens[0]).toMatchObject({ lancamento_id: null, categoria_id: null });
		expect('categoriaHerdada' in paraLinha(itens[0])).toBe(false);
	});

	it('recorrência paga em várias vezes recebe todos os saques pela regra', () => {
		const regraSaque: Regra = { id: 'g3', residencia_id: 'r', padrao: 'SAQUE DINHEIRO', categoria_id: null, natureza: null, recorrencia_id: 'rec-fax' };
		const saques = [
			{ data: '2026-10-01', valor: -540, descricao: 'Saque dinheiro ATM cartao 01/10 13:07 SEC.ORC.UNIAO-DF' },
			{ data: '2026-10-12', valor: -200, descricao: 'Saque dinheiro ATM cartao 12/10 10:00 SEC.ORC.UNIAO-DF' },
			{ data: '2026-10-23', valor: -360, descricao: 'Saque dinheiro ATM cartao 23/10 14:48 SEC.ORC.UNIAO-DF' }
		];
		const faxina = lanc({ id: 'fax', recorrencia_id: 'rec-fax', valor_previsto: 600, vencimento: '2026-10-10' });

		const itens = montarItens(saques, conta, [regraSaque]);
		sugerirConciliacao(itens, [faxina], conta, (id) => id === 'rec-fax');
		expect(itens.map((i) => i.lancamento_id)).toEqual(['fax', 'fax', 'fax']);

		// sem "acumula", só o primeiro saque é ligado
		const comuns = montarItens(saques, conta, [regraSaque]);
		sugerirConciliacao(comuns, [faxina], conta);
		expect(comuns.map((i) => i.lancamento_id)).toEqual(['fax', null, null]);
	});

	it('sugestão por valor ignora recorrências pagas em várias vezes', () => {
		const itens = montarItens([{ data: '2026-10-10', valor: -600, descricao: 'Pix Enviado Fulano' }], conta, []);
		sugerirConciliacao(itens, [lanc({ id: 'fax', recorrencia_id: 'rec-fax', valor_previsto: 600 })], conta, () => true);
		expect(itens[0].lancamento_id).toBeNull();
	});

	it('projeta parcelas restantes', () => {
		const cartao: Conta = { ...conta, tipo: 'cartao' };
		const [it] = montarItens([{ data: '2026-09-20', valor: -300, descricao: 'LOJA PARC 03/05', parcela: 3, parcelas: 5 }], cartao, [], '2026-11-01');
		expect(it).toMatchObject({ meio: 'cartao', natureza: 'gasto', descricao_norm: 'LOJA' });
		expect(projetarParcelas([it]).map((x) => [x.competencia, x.parcela, x.projetada])).toEqual([
			['2026-12-01', 4, true],
			['2027-01-01', 5, true]
		]);
	});
});
