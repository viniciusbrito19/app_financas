<script lang="ts">
	import '../app.css';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { app, limpar } from '#lib/app.svelte.ts';
	import TabBar from '#lib/components/TabBar.svelte';
	import { sb } from '#lib/supabase.ts';

	let { children } = $props();

	$effect(() => {
		const { data } = sb.auth.onAuthStateChange((evento) => {
			if (evento === 'SIGNED_OUT') {
				limpar();
				goto(resolve('/login'));
			}
		});
		return () => data.subscription.unsubscribe();
	});

	const comTabs = $derived(!!app.res && page.route.id !== '/login' && page.route.id !== '/onboarding');
</script>

<main class="mx-auto max-w-lg px-4 pt-4" style:padding-bottom={comTabs ? 'calc(6rem + env(safe-area-inset-bottom))' : '2rem'}>
	{@render children()}
</main>
{#if comTabs}<TabBar />{/if}
