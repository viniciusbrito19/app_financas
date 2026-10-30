<script lang="ts">
	import { app, carregarCadastros } from '#lib/app.svelte.ts';
	import Icone from '#lib/components/Icone.svelte';
	import Seg from '#lib/components/Seg.svelte';
	import Sheet from '#lib/components/Sheet.svelte';
	import { ok, sb } from '#lib/supabase.ts';
	import type { Categoria, Membro, Tipo } from '#lib/types.ts';

	async function renomearCasa() {
		const nome = prompt('Nome da residência', app.res!.nome)?.trim();
		if (!nome) return;
		ok(await sb.from('residencias').update({ nome }).eq('id', app.res!.id));
		app.res!.nome = nome;
	}

	async function convidar() {
		const texto = `Entre na residência "${app.res!.nome}" no app Finanças com o código ${app.res!.codigo_convite}: ${location.origin}`;
		if (navigator.share) await navigator.share({ text: texto }).catch(() => {});
		else {
			await navigator.clipboard.writeText(app.res!.codigo_convite);
			alert('Código copiado!');
		}
	}

	async function salvarMembro(m: Membro | null) {
		const nome = prompt('Nome', m?.nome ?? '')?.trim();
		if (!nome) return;
		ok(
			m
				? await sb.from('membros').update({ nome }).eq('id', m.id)
				: await sb.from('membros').insert({ nome, residencia_id: app.res!.id })
		);
		carregarCadastros();
	}

	async function excluirMembro(m: Membro) {
		if (!confirm(`Remover ${m.nome}? Os lançamentos dele(a) passam a ser da casa.`)) return;
		ok(await sb.from('membros').delete().eq('id', m.id));
		carregarCadastros();
	}

	// --- categorias --------------------------------------------------------
	let aberto = $state(false);
	let atual = $state<Categoria | null>(null);
	let f = $state({ nome: '', tipo: 'despesa' as Tipo, icone: '', cor: '#6d5efc' });

	function abrir(c: Categoria | null) {
		atual = c;
		f = c ? { nome: c.nome, tipo: c.tipo, icone: c.icone ?? '', cor: c.cor } : { nome: '', tipo: 'despesa', icone: '', cor: '#6d5efc' };
		aberto = true;
	}

	async function salvarCategoria(e: SubmitEvent) {
		e.preventDefault();
		const row = { ...f, icone: f.icone || null };
		ok(
			atual
				? await sb.from('categorias').update(row).eq('id', atual.id)
				: await sb.from('categorias').insert({ ...row, residencia_id: app.res!.id })
		);
		aberto = false;
		carregarCadastros();
	}

	async function excluirCategoria() {
		if (!atual || !confirm(`Excluir a categoria ${atual.nome}?`)) return;
		ok(await sb.from('categorias').delete().eq('id', atual.id));
		aberto = false;
		carregarCadastros();
	}
</script>

<h1 class="text-2xl font-bold">Ajustes</h1>

<section class="card mt-4 space-y-3">
	<button class="flex w-full items-center justify-between text-left" onclick={renomearCasa}>
		<div>
			<p class="label mb-0">Residência</p>
			<p class="text-lg font-semibold">{app.res?.nome}</p>
		</div>
		<span class="text-zinc-400">Editar</span>
	</button>
	<div class="flex items-center justify-between rounded-xl bg-zinc-100 p-3 dark:bg-zinc-800">
		<div>
			<p class="label mb-0">Código de convite</p>
			<p class="font-mono text-lg font-bold tracking-widest">{app.res?.codigo_convite}</p>
		</div>
		<button class="btn btn-primary h-10 text-sm" onclick={convidar}>Convidar</button>
	</div>
</section>

<h2 class="mt-6 mb-2 flex justify-between px-1 text-sm font-semibold text-zinc-500">
	<span>Membros</span>
	<button class="text-brand" onclick={() => salvarMembro(null)}>+ Adicionar</button>
</h2>
<ul class="card divide-y divide-zinc-100 p-0 dark:divide-zinc-800">
	{#each app.membros as m (m.id)}
		<li class="flex items-center gap-3 px-3 py-3">
			<span class="grid size-10 place-items-center rounded-full bg-brand/15 font-bold text-brand">{m.nome[0]?.toUpperCase()}</span>
			<button class="flex-1 text-left" onclick={() => salvarMembro(m)}>
				<p class="font-medium">{m.nome}{m.user_id === app.user?.id ? ' (você)' : ''}</p>
				<p class="text-xs text-zinc-500">{m.user_id ? (m.papel === 'admin' ? 'Administrador' : 'Com acesso') : 'Sem login (apenas titular)'}</p>
			</button>
			{#if !m.user_id}<button class="px-2 text-zinc-400" onclick={() => excluirMembro(m)} aria-label="Remover">✕</button>{/if}
		</li>
	{/each}
</ul>

{#each [['receita', 'Categorias de receita'], ['despesa', 'Categorias de despesa']] as [tipo, titulo] (tipo)}
	<h2 class="mt-6 mb-2 flex justify-between px-1 text-sm font-semibold text-zinc-500">
		<span>{titulo}</span>
		<button class="text-brand" onclick={() => { abrir(null); f.tipo = tipo as Tipo; }}>+ Nova</button>
	</h2>
	<div class="card flex flex-wrap gap-2 p-3">
		{#each app.cats.filter((c) => c.tipo === tipo) as c (c.id)}
			<button class="flex items-center gap-2 rounded-full bg-zinc-100 py-1 pr-3 pl-1 text-sm dark:bg-zinc-800" onclick={() => abrir(c)}>
				<span class="scale-75"><Icone {c} /></span>{c.nome}
			</button>
		{/each}
	</div>
{/each}

<button class="btn btn-ghost mt-8 w-full" onclick={() => sb.auth.signOut()}>Sair</button>

<Sheet bind:open={aberto} title={atual ? 'Editar categoria' : 'Nova categoria'}>
	<form class="space-y-4" onsubmit={salvarCategoria}>
		<Seg bind:value={f.tipo} options={[['despesa', 'Despesa'], ['receita', 'Receita']]} />
		<div class="grid grid-cols-[1fr_4.5rem_4.5rem] gap-3">
			<div>
				<label class="label" for="cnome">Nome</label>
				<input id="cnome" class="input" required bind:value={f.nome} />
			</div>
			<div>
				<label class="label" for="cicone">Emoji</label>
				<input id="cicone" class="input text-center" maxlength="4" bind:value={f.icone} />
			</div>
			<div>
				<label class="label" for="ccor">Cor</label>
				<input id="ccor" class="input p-1" type="color" bind:value={f.cor} />
			</div>
		</div>
		<button class="btn btn-primary w-full">Salvar</button>
		{#if atual}<button type="button" class="btn w-full text-despesa" onclick={excluirCategoria}>Excluir</button>{/if}
	</form>
</Sheet>
