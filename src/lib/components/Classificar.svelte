<script lang="ts">
	// Classifica uma transação (categoria, natureza, conciliação) e opcionalmente cria a regra
	import { app, NATUREZAS } from '#lib/app.svelte.ts';
	import { brl, dataCurta } from '#lib/format.ts';
	import type { Lancamento, Natureza } from '#lib/types.ts';
	import { untrack } from 'svelte';

	type T = { descricao: string; descricao_norm: string; valor: number; data: string; categoria_id: string | null; natureza: Natureza; lancamento_id: string | null };

	let {
		t,
		lancs,
		onsalvar
	}: { t: T; lancs?: Lancamento[]; onsalvar: (v: Pick<T, 'categoria_id' | 'natureza' | 'lancamento_id'>, padrao: string | null) => void } = $props();

	// edição local (cópia dos valores iniciais); só aplica ao salvar
	let f = $state(untrack(() => ({ categoria_id: t.categoria_id, natureza: t.natureza, lancamento_id: t.lancamento_id })));
	let lembrar = $state(true);
	let padrao = $state(untrack(() => t.descricao_norm));

	const cats = $derived(app.cats.filter((c) => c.tipo === (f.natureza === 'receita' ? 'receita' : 'despesa')));
	const opcoes = $derived((lancs ?? []).filter((l) => l.tipo === (t.valor < 0 ? 'despesa' : 'receita')));

	function salvar(e: SubmitEvent) {
		e.preventDefault();
		onsalvar(f, lembrar && padrao.trim() ? padrao.trim().toUpperCase() : null);
	}
</script>

<form class="space-y-4" onsubmit={salvar}>
	<div class="rounded-xl bg-zinc-100 p-3 dark:bg-zinc-800">
		<p class="font-medium break-words">{t.descricao}</p>
		<p class="text-sm text-zinc-500">{dataCurta(t.data)} · <span class="tabular-nums {t.valor > 0 ? 'text-receita' : ''}">{brl(t.valor)}</span></p>
	</div>
	<div class="grid grid-cols-2 gap-3">
		<div>
			<label class="label" for="nat">Natureza</label>
			<select id="nat" class="input" bind:value={f.natureza}>
				{#each Object.entries(NATUREZAS) as [v, r] (v)}<option value={v}>{r}</option>{/each}
			</select>
		</div>
		<div>
			<label class="label" for="cat">Categoria</label>
			<select id="cat" class="input" bind:value={f.categoria_id} disabled={f.natureza === 'transferencia' || f.natureza === 'ignorada'}>
				<option value={null}>Sem categoria</option>
				{#each cats as c (c.id)}<option value={c.id}>{c.icone} {c.nome}</option>{/each}
			</select>
		</div>
	</div>
	{#if lancs}
		<div>
			<label class="label" for="lanc">Conciliar com lançamento previsto</label>
			<select id="lanc" class="input" bind:value={f.lancamento_id}>
				<option value={null}>Nenhum (gasto não previsto)</option>
				{#each opcoes as l (l.id)}<option value={l.id}>{l.descricao} · {dataCurta(l.vencimento)} · {brl(l.valor_real ?? l.valor_previsto)}</option>{/each}
			</select>
		</div>
	{/if}
	<label class="flex items-center gap-3 rounded-xl bg-zinc-100 px-3 py-3 dark:bg-zinc-800">
		<input type="checkbox" class="size-5 accent-brand" bind:checked={lembrar} />
		<span class="font-medium">Lembrar para as próximas</span>
	</label>
	{#if lembrar}
		<div>
			<label class="label" for="padrao">Quando a descrição contiver</label>
			<input id="padrao" class="input uppercase" bind:value={padrao} />
			<p class="mt-1 text-xs text-zinc-500">Encurte para generalizar (ex.: "IFOOD" em vez da descrição inteira).</p>
		</div>
	{/if}
	<button class="btn btn-primary w-full">Salvar</button>
</form>
