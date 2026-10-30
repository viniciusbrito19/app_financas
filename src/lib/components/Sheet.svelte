<script lang="ts">
	import type { Snippet } from 'svelte';
	import { fade, fly } from 'svelte/transition';

	let { open = $bindable(false), title, children }: { open: boolean; title: string; children: Snippet } = $props();
</script>

{#if open}
	<div class="fixed inset-0 z-40 bg-black/40" transition:fade={{ duration: 150 }} onclick={() => (open = false)} role="presentation"></div>
	<div
		class="fixed inset-x-0 bottom-0 z-50 mx-auto max-h-[92dvh] max-w-lg overflow-y-auto rounded-t-3xl bg-white px-5 pt-3 dark:bg-zinc-900 sm:bottom-auto sm:top-1/2 sm:-translate-y-1/2 sm:rounded-3xl"
		style="padding-bottom: calc(1.25rem + env(safe-area-inset-bottom))"
		transition:fly={{ y: 400, duration: 220 }}
		role="dialog"
		aria-modal="true"
	>
		<div class="mx-auto mb-3 h-1.5 w-10 rounded-full bg-zinc-300 dark:bg-zinc-700 sm:hidden"></div>
		<div class="mb-4 flex items-center justify-between">
			<h2 class="text-lg font-bold">{title}</h2>
			<button class="grid size-9 place-items-center rounded-full bg-zinc-100 dark:bg-zinc-800" onclick={() => (open = false)} aria-label="Fechar">✕</button>
		</div>
		{@render children()}
	</div>
{/if}
