<script lang="ts">
	// Sheet para corrigir categoria/natureza de uma transação já gravada (fatura, extrato, análise)
	import { reclassificar } from '#lib/importacao/regras.ts';
	import type { Transacao } from '#lib/types.ts';
	import Classificar from './Classificar.svelte';
	import Sheet from './Sheet.svelte';

	let { t = $bindable(), onfeito }: { t: Transacao | null; onfeito?: () => void } = $props();
</script>

<Sheet bind:open={() => !!t, (v) => !v && (t = null)} title="Classificar transação">
	{#if t}
		<Classificar
			{t}
			onsalvar={async (v, padrao) => {
				await reclassificar(t!, v, padrao);
				t = null;
				onfeito?.();
			}}
		/>
	{/if}
</Sheet>
