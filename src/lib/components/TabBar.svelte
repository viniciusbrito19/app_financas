<script lang="ts">
	import { resolve } from '$app/paths';
	import { page } from '$app/state';

	const tabs = [
		{ href: '/', rotulo: 'Mês', d: 'M4 5h16v15H4zM4 9h16M9 3v4M15 3v4' },
		{ href: '/recorrentes', rotulo: 'Recorrentes', d: 'M4 12a8 8 0 0 1 14-5.3M20 4v5h-5M20 12a8 8 0 0 1-14 5.3M4 20v-5h5' },
		{ href: '/ajustes', rotulo: 'Ajustes', d: 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM4 12h2m12 0h2M12 4v2m0 12v2M6.3 6.3l1.4 1.4m8.6 8.6 1.4 1.4m0-11.4-1.4 1.4m-8.6 8.6-1.4 1.4' }
	] as const;
</script>

<nav
	class="fixed inset-x-0 bottom-0 z-30 flex border-t border-zinc-200 bg-white/85 backdrop-blur-lg dark:border-zinc-800 dark:bg-zinc-900/85"
	style="padding-bottom: env(safe-area-inset-bottom)"
>
	{#each tabs as t (t.href)}
		{@const ativo = page.route.id === t.href}
		<a href={resolve(t.href)} class="flex h-16 flex-1 flex-col items-center justify-center gap-1 text-[11px] font-medium {ativo ? 'text-brand' : 'text-zinc-500'}">
			<svg viewBox="0 0 24 24" class="size-6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d={t.d} /></svg>
			{t.rotulo}
		</a>
	{/each}
</nav>
