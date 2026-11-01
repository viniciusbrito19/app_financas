<script lang="ts">
	// Sheet para corrigir categoria/natureza/conciliação de uma transação já gravada (fatura, extrato, análise)
	import { app, conta } from '#lib/app.svelte.ts';
	import { reclassificar } from '#lib/importacao/regras.ts';
	import { ok, sb } from '#lib/supabase.ts';
	import type { Lancamento, Transacao } from '#lib/types.ts';
	import Classificar from './Classificar.svelte';
	import Sheet from './Sheet.svelte';

	let { t = $bindable(), onfeito }: { t: Transacao | null; onfeito?: () => void } = $props();

	/** lançamentos recorrentes do mês que podem ser conciliados (só conta corrente; itens de cartão compõem a fatura) */
	let lancs = $state<Lancamento[] | undefined>(undefined);
	let carregado = $state<string | null>(null);

	$effect(() => {
		const alvo = t;
		lancs = undefined;
		carregado = null;
		if (!alvo) return;
		if (conta(alvo.conta_id)?.tipo !== 'corrente') {
			carregado = alvo.id;
			return;
		}
		(async () => {
			ok(await sb.rpc('gerar_mes', { p_res: app.res!.id, p_comp: alvo.competencia }));
			const ls = ok(
				await sb
					.from('lancamentos')
					.select('*')
					.eq('residencia_id', app.res!.id)
					.eq('competencia', alvo.competencia)
					.not('recorrencia_id', 'is', null)
					.order('vencimento')
			) as Lancamento[];
			if (t !== alvo) return;
			// todos, inclusive os já pagos: um gasto extra no mês soma no valor real do lançamento
			lancs = ls;
			carregado = alvo.id;
		})();
	});
</script>

<Sheet bind:open={() => !!t, (v) => !v && (t = null)} title="Classificar transação">
	{#if t && carregado === t.id}
		<Classificar
			{t}
			{lancs}
			onsalvar={async (v, padrao) => {
				const recorrencia_id = lancs?.find((l) => l.id === v.lancamento_id)?.recorrencia_id;
				await reclassificar(t!, { ...v, lancamento_id: lancs ? v.lancamento_id : undefined, recorrencia_id }, padrao);
				t = null;
				onfeito?.();
			}}
		/>
	{:else if t}
		<p class="py-6 text-center text-sm text-zinc-500">Carregando…</p>
	{/if}
</Sheet>
