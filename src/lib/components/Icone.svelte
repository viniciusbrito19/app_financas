<script lang="ts">
	import type { Categoria } from '#lib/types.ts';

	let { c }: { c: Categoria | undefined } = $props();
</script>

<span class="grid size-10 shrink-0 place-items-center rounded-full text-lg" style:background-color={(c?.cor ?? '#71717a') + '26'}>
	{c?.icone ?? '•'}
</span>
