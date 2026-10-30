<script lang="ts">
	import { addMes, mesLabel } from '#lib/format.ts';

	let { value = $bindable() }: { value: string } = $props();
</script>

<div class="flex items-center justify-between">
	<button class="grid size-11 place-items-center rounded-full text-2xl active:bg-zinc-200 dark:active:bg-zinc-800" onclick={() => (value = addMes(value, -1))} aria-label="Mês anterior">‹</button>
	<span class="text-lg font-bold">{mesLabel(value)}</span>
	<button class="grid size-11 place-items-center rounded-full text-2xl active:bg-zinc-200 dark:active:bg-zinc-800" onclick={() => (value = addMes(value, 1))} aria-label="Próximo mês">›</button>
</div>
