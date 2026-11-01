<script lang="ts">
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { app } from '#lib/app.svelte.ts';

	const tabs = [
		{ href: '/', rotulo: 'Mês', d: 'M4 5h16v15H4zM4 9h16M9 3v4M15 3v4' },
		{ href: '/recorrentes', rotulo: 'Recorrentes', d: 'M4 12a8 8 0 0 1 14-5.3M20 4v5h-5M20 12a8 8 0 0 1-14 5.3M4 20v-5h5' },
		{ href: '/importar', rotulo: 'Importar', d: 'M12 15V3m0 0L7 8m5-5 5 5M4 15v4a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-4' },
		{ href: '/analise', rotulo: 'Análise', d: 'M4 20V10m6 10V4m6 16v-7m4 7H2' },
		{ href: '/ajustes', rotulo: 'Ajustes', d: 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM4 12h2m12 0h2M12 4v2m0 12v2M6.3 6.3l1.4 1.4m8.6 8.6 1.4 1.4m0-11.4-1.4 1.4m-8.6 8.6-1.4 1.4' }
	] as const;
</script>

<nav
	class="fixed inset-x-0 bottom-0 z-30 flex border-t border-zinc-200 bg-white/85 backdrop-blur-lg dark:border-zinc-800 dark:bg-zinc-900/85"
	style="padding-bottom: env(safe-area-inset-bottom)"
>
	{#each tabs as t (t.href)}
		{@const ativo = page.route.id === t.href}
		<a href={resolve(t.href)} class="relative flex h-16 flex-1 flex-col items-center justify-center gap-1 text-[10px] font-medium {ativo ? 'text-brand' : 'text-zinc-500'}">
			<svg viewBox="0 0 24 24" class="size-6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d={t.d} /></svg>
			{t.rotulo}
			{#if t.href === '/importar' && app.pendentes}
				<span class="absolute top-2 left-1/2 ml-2 grid h-4 min-w-4 place-items-center rounded-full bg-rose-500 px-1 text-[10px] text-white">{app.pendentes}</span>
			{/if}
		</a>
	{/each}
</nav>
