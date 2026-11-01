import { app, contarPendentes } from '../app.svelte.ts';
import { ok, sb } from '../supabase.ts';
import type { Natureza, Regra } from '../types.ts';

/**
 * Cria/atualiza a regra para `padrao` e aplica a categoria às transações já gravadas
 * que ainda estão sem categoria. Só guarda a natureza quando foge do padrão (transferência/fatura).
 */
export async function lembrarRegra(padrao: string, t: { categoria_id: string | null; natureza: Natureza; recorrencia_id?: string | null }) {
	const natureza = t.natureza === 'transferencia' || t.natureza === 'pagamento_fatura' ? t.natureza : null;
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
		ok(
			await sb
				.from('transacoes')
				.update({ categoria_id: r.categoria_id })
				.eq('residencia_id', app.res!.id)
				.eq('natureza', 'gasto')
				.is('categoria_id', null)
				.like('descricao_norm', `%${padrao}%`)
		);
		await contarPendentes();
	}
	return r;
}
