import { app, contarPendentes } from '../app.svelte.ts';
import { ok, sb } from '../supabase.ts';
import type { Natureza, Regra, Transacao } from '../types.ts';

type Classificacao = { categoria_id: string | null; natureza: Natureza; recorrencia_id?: string | null };

/**
 * Cria/atualiza a regra para `padrao` e aplica a categoria às transações de gasto já gravadas
 * (só às sem categoria, ou a todas com `sobrescrever`). Guarda a natureza só quando foge do padrão.
 */
export async function lembrarRegra(padrao: string, t: Classificacao, sobrescrever = false) {
	const natureza = t.natureza === 'gasto' || t.natureza === 'receita' ? null : t.natureza;
	const r = ok(
		await sb
			.from('regras')
			.upsert(
				{ residencia_id: app.res!.id, padrao, categoria_id: t.categoria_id, natureza, recorrencia_id: t.recorrencia_id ?? null },
				{ onConflict: 'residencia_id,padrao' }
			)
			.select()
			.single()
	) as Regra;
	app.regras = [...app.regras.filter((x) => x.padrao !== r.padrao), r];

	if (r.categoria_id) {
		let q = sb
			.from('transacoes')
			.update({ categoria_id: r.categoria_id })
			.eq('residencia_id', app.res!.id)
			.eq('natureza', 'gasto')
			.like('descricao_norm', `%${padrao}%`);
		if (!sobrescrever) q = q.is('categoria_id', null);
		ok(await q);
	}
	await contarPendentes();
	return r;
}

/**
 * Corrige a classificação de uma transação já gravada (e, com padrão, das semelhantes).
 * Com `lancamento_id` informado, também troca a conciliação (o lançamento anterior é reaberto).
 */
export async function reclassificar(t: Transacao, v: Classificacao & { lancamento_id?: string | null; nota?: string | null }, padrao: string | null) {
	const campos = { categoria_id: v.categoria_id, natureza: v.natureza, ...(v.nota !== undefined && { nota: v.nota }) };
	ok(await sb.from('transacoes').update(campos).eq('id', t.id));
	if (v.lancamento_id !== undefined && v.lancamento_id !== t.lancamento_id) {
		ok(await sb.rpc('vincular_transacao', { p_tx: t.id, p_lanc: v.lancamento_id }));
		t.lancamento_id = v.lancamento_id;
	}
	Object.assign(t, campos);
	if (padrao) await lembrarRegra(padrao, v, true);
	else await contarPendentes();
}
