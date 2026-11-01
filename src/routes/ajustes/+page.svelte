<script lang="ts">
	import { app, carregarCadastros } from '#lib/app.svelte.ts';
	import Icone from '#lib/components/Icone.svelte';
	import Seg from '#lib/components/Seg.svelte';
	import Sheet from '#lib/components/Sheet.svelte';
	import { ok, sb } from '#lib/supabase.ts';
	import type { Categoria, Conta, Membro, Regra, Tipo } from '#lib/types.ts';
	import { NATUREZAS } from '#lib/app.svelte.ts';

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

	// --- contas e cartões --------------------------------------------------
	let abertaConta = $state(false);
	let contaAtual = $state<Conta | null>(null);
	let fc = $state({ nome: '', tipo: 'corrente' as Conta['tipo'], banco: 'bb' as Conta['banco'], membro_id: null as string | null, recorrencia_id: null as string | null });

	function abrirConta(c: Conta | null) {
		contaAtual = c;
		fc = c ? { nome: c.nome, tipo: c.tipo, banco: c.banco, membro_id: c.membro_id, recorrencia_id: c.recorrencia_id } : { nome: '', tipo: 'corrente', banco: 'bb', membro_id: null, recorrencia_id: null };
		abertaConta = true;
	}

	async function salvarConta(e: SubmitEvent) {
		e.preventDefault();
		const row = { ...fc, recorrencia_id: fc.tipo === 'cartao' ? fc.recorrencia_id : null };
		ok(
			contaAtual
				? await sb.from('contas').update(row).eq('id', contaAtual.id)
				: await sb.from('contas').insert({ ...row, residencia_id: app.res!.id })
		);
		abertaConta = false;
		carregarCadastros();
	}

	async function excluirConta() {
		if (!contaAtual || !confirm(`Excluir ${contaAtual.nome}? Todas as transações importadas dela serão apagadas.`)) return;
		ok(await sb.from('contas').delete().eq('id', contaAtual.id));
		abertaConta = false;
		carregarCadastros();
	}

	// --- regras de classificação -------------------------------------------
	let abertaRegra = $state(false);
	let regraAtual = $state<Regra | null>(null);
	let fr = $state({ padrao: '', categoria_id: null as string | null, natureza: null as Regra['natureza'], recorrencia_id: null as string | null });

	function abrirRegra(r: Regra) {
		regraAtual = r;
		fr = { padrao: r.padrao, categoria_id: r.categoria_id, natureza: r.natureza, recorrencia_id: r.recorrencia_id };
		abertaRegra = true;
	}

	async function salvarRegra(e: SubmitEvent) {
		e.preventDefault();
		ok(await sb.from('regras').update({ ...fr, padrao: fr.padrao.trim().toUpperCase() }).eq('id', regraAtual!.id));
		abertaRegra = false;
		carregarCadastros();
	}

	async function excluirRegra() {
		ok(await sb.from('regras').delete().eq('id', regraAtual!.id));
		abertaRegra = false;
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

<h2 class="mt-6 mb-2 flex justify-between px-1 text-sm font-semibold text-zinc-500">
	<span>Contas e cartões</span>
	<button class="text-brand" onclick={() => abrirConta(null)}>+ Adicionar</button>
</h2>
<ul class="card divide-y divide-zinc-100 p-0 dark:divide-zinc-800">
	{#each app.contas as c (c.id)}
		<li>
			<button class="flex w-full items-center gap-3 px-3 py-3 text-left" onclick={() => abrirConta(c)}>
				<span class="grid size-10 place-items-center rounded-full bg-zinc-100 text-lg dark:bg-zinc-800">{c.tipo === 'cartao' ? '💳' : '🏦'}</span>
				<div class="min-w-0 flex-1">
					<p class="font-medium">{c.nome}</p>
					<p class="text-xs text-zinc-500">
						{c.tipo === 'cartao' ? 'Cartão de crédito' : 'Conta corrente'} · {c.banco.toUpperCase()}
						{#if c.tipo === 'cartao'}· fatura: {app.recs.find((r) => r.id === c.recorrencia_id)?.descricao ?? '⚠ sem recorrência'}{/if}
					</p>
				</div>
			</button>
		</li>
	{:else}
		<li class="px-3 py-3 text-sm text-zinc-500">Cadastre BB, Caixa e o cartão para importar extratos e faturas.</li>
	{/each}
</ul>

{#if app.regras.length}
	<h2 class="mt-6 mb-2 px-1 text-sm font-semibold text-zinc-500">Regras de classificação ({app.regras.length})</h2>
	<ul class="card max-h-96 divide-y divide-zinc-100 overflow-y-auto p-0 dark:divide-zinc-800">
		{#each app.regras as r (r.id)}
			{@const c = app.cats.find((x) => x.id === r.categoria_id)}
			<li>
				<button class="flex w-full items-center gap-2 px-3 py-2.5 text-left text-sm" onclick={() => abrirRegra(r)}>
					<span class="min-w-0 flex-1 truncate font-mono text-xs">{r.padrao}</span>
					<span class="shrink-0 text-zinc-500">→ {c ? `${c.icone ?? ''} ${c.nome}` : r.natureza ? NATUREZAS[r.natureza] : '—'}</span>
				</button>
			</li>
		{/each}
	</ul>
{/if}

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

<Sheet bind:open={abertaConta} title={contaAtual ? 'Editar conta' : 'Nova conta'}>
	<form class="space-y-4" onsubmit={salvarConta}>
		<Seg bind:value={fc.tipo} options={[['corrente', 'Conta corrente'], ['cartao', 'Cartão de crédito']]} />
		<div class="grid grid-cols-[1fr_7rem] gap-3">
			<div>
				<label class="label" for="knome">Nome</label>
				<input id="knome" class="input" required placeholder={fc.tipo === 'cartao' ? 'Cartão Caixa' : 'Conta BB'} bind:value={fc.nome} />
			</div>
			<div>
				<label class="label" for="kbanco">Banco</label>
				<select id="kbanco" class="input" bind:value={fc.banco}>
					<option value="bb">BB</option>
					<option value="caixa">Caixa</option>
					<option value="outro">Outro</option>
				</select>
			</div>
		</div>
		<div>
			<label class="label" for="ktit">Titular</label>
			<select id="ktit" class="input" bind:value={fc.membro_id}>
				<option value={null}>Casa</option>
				{#each app.membros as m (m.id)}<option value={m.id}>{m.nome}</option>{/each}
			</select>
		</div>
		{#if fc.tipo === 'cartao'}
			<div>
				<label class="label" for="krec">Recorrência que representa a fatura</label>
				<select id="krec" class="input" bind:value={fc.recorrencia_id}>
					<option value={null}>Nenhuma</option>
					{#each app.recs.filter((r) => r.tipo === 'despesa') as r (r.id)}<option value={r.id}>{r.descricao}</option>{/each}
				</select>
				<p class="mt-1 text-xs text-zinc-500">Crie em Recorrentes uma despesa variável (ex.: "Fatura Cartão Caixa") com o dia do vencimento.</p>
			</div>
		{/if}
		<button class="btn btn-primary w-full">Salvar</button>
		{#if contaAtual}<button type="button" class="btn w-full text-despesa" onclick={excluirConta}>Excluir</button>{/if}
	</form>
</Sheet>

<Sheet bind:open={abertaRegra} title="Regra de classificação">
	<form class="space-y-4" onsubmit={salvarRegra}>
		<div>
			<label class="label" for="rpad">Quando a descrição contiver</label>
			<input id="rpad" class="input uppercase" required bind:value={fr.padrao} />
		</div>
		<div class="grid grid-cols-2 gap-3">
			<div>
				<label class="label" for="rcat">Categoria</label>
				<select id="rcat" class="input" bind:value={fr.categoria_id}>
					<option value={null}>—</option>
					{#each app.cats as c (c.id)}<option value={c.id}>{c.icone} {c.nome}</option>{/each}
				</select>
			</div>
			<div>
				<label class="label" for="rnat">Natureza</label>
				<select id="rnat" class="input" bind:value={fr.natureza}>
					<option value={null}>Automática</option>
					{#each Object.entries(NATUREZAS) as [v, r] (v)}<option value={v}>{r}</option>{/each}
				</select>
			</div>
		</div>
		<div>
			<label class="label" for="rrec">Conciliar com a recorrência</label>
			<select id="rrec" class="input" bind:value={fr.recorrencia_id}>
				<option value={null}>Nenhuma</option>
				{#each app.recs as r (r.id)}<option value={r.id}>{r.descricao}</option>{/each}
			</select>
		</div>
		<button class="btn btn-primary w-full">Salvar</button>
		<button type="button" class="btn w-full text-despesa" onclick={excluirRegra}>Excluir</button>
	</form>
</Sheet>
