<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import Seg from '#lib/components/Seg.svelte';
	import { sb } from '#lib/supabase.ts';

	let modo = $state<'entrar' | 'criar'>('entrar');
	let email = $state('');
	let senha = $state('');
	let msg = $state('');
	let carregando = $state(false);

	async function enviar(e: SubmitEvent) {
		e.preventDefault();
		carregando = true;
		msg = '';
		const { data, error } =
			modo === 'entrar'
				? await sb.auth.signInWithPassword({ email, password: senha })
				: await sb.auth.signUp({ email, password: senha, options: { emailRedirectTo: location.origin + resolve('/') } });
		carregando = false;
		if (error) msg = error.message;
		else if (data.session) goto(resolve('/'));
		else msg = 'Conta criada! Confirme pelo link enviado ao seu e-mail e depois entre.';
	}
</script>

<div class="flex min-h-[85dvh] flex-col justify-center gap-6">
	<div class="text-center">
		<div class="mx-auto mb-3 grid size-16 place-items-center rounded-2xl bg-brand text-3xl text-white shadow-lg">R$</div>
		<h1 class="text-2xl font-bold">Finanças da Casa</h1>
	</div>
	<form class="card space-y-4" onsubmit={enviar}>
		<Seg bind:value={modo} options={[['entrar', 'Entrar'], ['criar', 'Criar conta']]} />
		<div>
			<label class="label" for="email">E-mail</label>
			<input id="email" class="input" type="email" autocomplete="email" required bind:value={email} />
		</div>
		<div>
			<label class="label" for="senha">Senha</label>
			<input id="senha" class="input" type="password" minlength="6" autocomplete={modo === 'entrar' ? 'current-password' : 'new-password'} required bind:value={senha} />
		</div>
		{#if msg}<p class="text-sm text-zinc-600 dark:text-zinc-300">{msg}</p>{/if}
		<button class="btn btn-primary w-full" disabled={carregando}>{modo === 'entrar' ? 'Entrar' : 'Criar conta'}</button>
	</form>
</div>
