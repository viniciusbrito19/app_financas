<script lang="ts">
	// Campos comuns a lançamentos e recorrências: tipo, descrição, categoria e titular
	import { app } from '#lib/app.svelte.ts';
	import type { Tipo } from '#lib/types.ts';
	import Seg from './Seg.svelte';

	type Base = { tipo: Tipo; descricao: string; categoria_id: string | null; membro_id: string | null };
	let { f = $bindable() }: { f: Base } = $props();

	const cats = $derived(app.cats.filter((c) => c.tipo === f.tipo));
</script>

<Seg bind:value={f.tipo} options={[['despesa', 'Despesa'], ['receita', 'Receita']]} />
<div>
	<label class="label" for="descricao">Descrição</label>
	<input id="descricao" class="input" required bind:value={f.descricao} />
</div>
<div class="grid grid-cols-2 gap-3">
	<div>
		<label class="label" for="categoria">Categoria</label>
		<select id="categoria" class="input" bind:value={f.categoria_id}>
			<option value={null}>Sem categoria</option>
			{#each cats as c (c.id)}<option value={c.id}>{c.icone} {c.nome}</option>{/each}
		</select>
	</div>
	<div>
		<label class="label" for="titular">Titular</label>
		<select id="titular" class="input" bind:value={f.membro_id}>
			<option value={null}>Casa</option>
			{#each app.membros as m (m.id)}<option value={m.id}>{m.nome}</option>{/each}
		</select>
	</div>
</div>
