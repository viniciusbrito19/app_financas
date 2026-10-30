<script lang="ts" generics="T extends string">
	let { value = $bindable(), options }: { value: T; options: [T, string][] } = $props();
</script>

<div class="flex rounded-xl bg-zinc-100 p-1 dark:bg-zinc-800">
	{#each options as [v, rotulo] (v)}
		<button
			type="button"
			class="h-10 flex-1 rounded-lg text-sm font-semibold transition {value === v ? 'bg-white shadow-sm dark:bg-zinc-700' : 'text-zinc-500'}"
			onclick={() => (value = v)}>{rotulo}</button
		>
	{/each}
</div>
