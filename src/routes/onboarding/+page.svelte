<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { app, carregarResidencia } from '#lib/app.svelte.ts';
	import Seg from '#lib/components/Seg.svelte';
	import { sb } from '#lib/supabase.ts';

	let modo = $state<'criar' | 'entrar'>('criar');
	let nome = $state('Minha casa');
	let codigo = $state('');
	let meuNome = $state('');
	let erro = $state('');

	async function enviar(e: SubmitEvent) {
		e.preventDefault();
		erro = '';
		const { error } =
			modo === 'criar'
				? await sb.rpc('criar_residencia', { p_nome: nome, p_meu_nome: meuNome })
				: await sb.rpc('entrar_residencia', { p_codigo: codigo, p_meu_nome: meuNome });
		if (error) return (erro = error.message);
		await carregarResidencia(app.user!);
		goto(resolve('/'));
	}
</script>

<div class="flex min-h-[85dvh] flex-col justify-center gap-6">
	<div>
		<h1 class="text-2xl font-bold">Bem-vindo(a)!</h1>
		<p class="text-zinc-500">Crie a residência ou entre na de alguém com o código de convite.</p>
	</div>
	<form class="card space-y-4" onsubmit={enviar}>
		<Seg bind:value={modo} options={[['criar', 'Criar residência'], ['entrar', 'Tenho um código']]} />
		{#if modo === 'criar'}
			<div>
				<label class="label" for="nome">Nome da residência</label>
				<input id="nome" class="input" required bind:value={nome} />
			</div>
		{:else}
			<div>
				<label class="label" for="codigo">Código de convite</label>
				<input id="codigo" class="input uppercase" required autocapitalize="characters" bind:value={codigo} />
			</div>
		{/if}
		<div>
			<label class="label" for="meu">Seu nome</label>
			<input id="meu" class="input" required autocomplete="given-name" bind:value={meuNome} />
		</div>
		{#if erro}<p class="text-sm text-despesa">{erro}</p>{/if}
		<button class="btn btn-primary w-full">Continuar</button>
	</form>
	<button class="text-sm text-zinc-500" onclick={() => sb.auth.signOut()}>Sair</button>
</div>
