<script lang="ts">
	import { app, carregarCadastros, cat, mediaCartao, membro } from '#lib/app.svelte.ts';
	import CamposBase from '#lib/components/CamposBase.svelte';
	import Icone from '#lib/components/Icone.svelte';
	import Seg from '#lib/components/Seg.svelte';
	import Sheet from '#lib/components/Sheet.svelte';
	import { brl, mesAtual, parseValor, valorInput } from '#lib/format.ts';
	import { ok, sb } from '#lib/supabase.ts';
	import type { Meta, Recorrencia, Tipo } from '#lib/types.ts';

	let itens = $state<Recorrencia[]>([]);

	async function carregar() {
		itens = ok(
			await sb.from('recorrencias').select('*').eq('residencia_id', app.res!.id).order('ativo', { ascending: false }).order('dia_vencimento')
		) as Recorrencia[];
	}
	carregar();

	/** Despesas: "geral" = recorrentes; "cartao" = metas de gasto no cartão por categoria. */
	let filtroDespesa = $state<'geral' | 'cartao'>('geral');

	const grupos = $derived(
		(['receita', 'despesa'] as Tipo[]).map((tipo) => {
			const ls = itens.filter((r) => r.tipo === tipo);
			return { tipo, ls, total: ls.filter((r) => r.ativo).reduce((s, r) => s + Number(r.valor_base), 0) };
		})
	);

	// --- metas do cartão -----------------------------------------------------
	let metas = $state<Meta[]>([]);
	/** média dos últimos 3 meses no cartão, por categoria (sugestão de meta) */
	let medias = $state<Record<string, number> | null>(null);

	async function carregarMetas() {
		const [ms, md] = await Promise.all([sb.from('metas_cartao').select('*').eq('residencia_id', app.res!.id), mediaCartao(mesAtual())]);
		metas = ok(ms) as Meta[];
		medias = md;
	}
	carregarMetas();

	const meta = (categoriaId: string) => metas.find((m) => m.categoria_id === categoriaId);
	const totalMetas = $derived(metas.reduce((s, m) => s + Number(m.valor), 0));
	/** categorias de despesa (menos a da própria fatura); com meta primeiro, depois por média */
	const catsMeta = $derived(
		app.cats
			.filter((c) => c.tipo === 'despesa' && c.nome !== 'Cartão de crédito')
			.sort((a, b) => +!!meta(b.id) - +!!meta(a.id) || (medias?.[b.id] ?? 0) - (medias?.[a.id] ?? 0))
	);

	async function salvarMeta(categoriaId: string, texto: string) {
		const v = texto.trim() ? parseValor(texto) : 0;
		if (Number(meta(categoriaId)?.valor ?? 0) === v) return;
		ok(
			v > 0
				? await sb.from('metas_cartao').upsert({ residencia_id: app.res!.id, categoria_id: categoriaId, valor: v }, { onConflict: 'residencia_id,categoria_id' })
				: await sb.from('metas_cartao').delete().eq('residencia_id', app.res!.id).eq('categoria_id', categoriaId)
		);
		await carregarMetas();
	}

	// --- edição ------------------------------------------------------------
	let aberto = $state(false);
	let atual = $state<Recorrencia | null>(null);
	let f = $state({
		tipo: 'despesa' as Tipo,
		descricao: '',
		categoria_id: null as string | null,
		membro_id: null as string | null,
		modo_valor: 'fixo' as Recorrencia['modo_valor'],
		valor: '',
		janela_media: 3,
		dia_vencimento: 10,
		inicio: '',
		fim: '',
		ativo: true,
		acumula: false
	});

	function abrir(r: Recorrencia | null) {
		atual = r;
		f = r
			? { ...r, valor: valorInput(r.valor_base), inicio: r.inicio.slice(0, 7), fim: r.fim?.slice(0, 7) ?? '' }
			: { tipo: 'despesa', descricao: '', categoria_id: null, membro_id: null, modo_valor: 'fixo', valor: '', janela_media: 3, dia_vencimento: 10, inicio: mesAtual().slice(0, 7), fim: '', ativo: true, acumula: false };
		aberto = true;
	}

	async function salvar(e: SubmitEvent) {
		e.preventDefault();
		const { valor, inicio, fim, ...resto } = f;
		const row = {
			tipo: resto.tipo,
			descricao: resto.descricao,
			categoria_id: resto.categoria_id,
			membro_id: resto.membro_id,
			modo_valor: resto.modo_valor,
			janela_media: resto.janela_media,
			dia_vencimento: resto.dia_vencimento,
			ativo: resto.ativo,
			acumula: resto.acumula,
			valor_base: parseValor(valor),
			inicio: inicio + '-01',
			fim: fim ? fim + '-01' : null
		};
		ok(
			atual
				? await sb.from('recorrencias').update(row).eq('id', atual.id)
				: await sb.from('recorrencias').insert({ ...row, residencia_id: app.res!.id })
		);
		aberto = false;
		if (row.tipo === 'despesa') filtroDespesa = 'geral';
		// atualiza também a lista global (usada no Mês para "várias vezes")
		await Promise.all([carregar(), carregarCadastros()]);
	}

	async function excluir() {
		if (!atual || !confirm('Excluir esta recorrência? Lançamentos já pagos ou com valor informado são mantidos.')) return;
		ok(await sb.from('recorrencias').delete().eq('id', atual.id));
		aberto = false;
		await Promise.all([carregar(), carregarCadastros()]);
	}
</script>

<h1 class="text-2xl font-bold">Recorrentes</h1>
<p class="text-sm text-zinc-500">Geram os lançamentos de cada mês automaticamente.</p>

{#each grupos as g (g.tipo)}
	{@const metasVisiveis = g.tipo === 'despesa' && filtroDespesa === 'cartao'}
	<h2 class="mt-6 mb-2 flex justify-between px-1 text-sm font-semibold text-zinc-500">
		<span>{g.tipo === 'receita' ? 'Receitas' : 'Despesas'}</span>
		<span>{brl(metasVisiveis ? totalMetas : g.total)}/mês</span>
	</h2>
	{#if g.tipo === 'despesa'}
		<div class="mb-2 flex gap-2">
			{#each [['geral', 'Geral', g.ls.length], ['cartao', 'Cartão', metas.length]] as const as [v, r, n] (v)}
				<button
					class="chip shrink-0 px-3 py-1.5 text-xs {filtroDespesa === v ? 'bg-brand text-white' : 'bg-white text-zinc-600 dark:bg-zinc-900 dark:text-zinc-300'}"
					onclick={() => (filtroDespesa = v)}>{r} ({n})</button
				>
			{/each}
		</div>
	{/if}
	{#if metasVisiveis}
		<p class="mb-2 px-1 text-xs text-zinc-500">
			Meta mensal de gasto no cartão por categoria. O realizado vem dos itens da fatura; a previsão da fatura é a soma das metas.
		</p>
		<ul class="card divide-y divide-zinc-100 p-0 dark:divide-zinc-800">
			{#each catsMeta as c (c.id)}
				{@const m = meta(c.id)}
				<li class="flex items-center gap-3 px-3 py-2">
					<Icone {c} />
					<div class="min-w-0 flex-1">
						<p class="truncate font-medium {m ? '' : 'text-zinc-500'}">{c.nome}</p>
						<p class="text-xs text-zinc-500">{medias?.[c.id] ? `média 3m ${brl(medias[c.id])}` : 'sem gasto recente'}</p>
					</div>
					<input
						class="input w-28 text-right tabular-nums"
						inputmode="decimal"
						placeholder="—"
						aria-label="Meta de {c.nome}"
						value={m ? valorInput(m.valor) : ''}
						onchange={(e) => salvarMeta(c.id, e.currentTarget.value)}
					/>
				</li>
			{/each}
		</ul>
	{:else if g.ls.length}
		<ul class="card divide-y divide-zinc-100 p-0 dark:divide-zinc-800">
			{#each g.ls as r (r.id)}
				<li>
					<button class="flex w-full items-center gap-3 px-3 py-3 text-left {r.ativo ? '' : 'opacity-50'}" onclick={() => abrir(r)}>
						<Icone c={cat(r.categoria_id)} />
						<div class="min-w-0 flex-1">
							<p class="truncate font-medium">{r.descricao}</p>
							<p class="text-xs text-zinc-500">
								Dia {r.dia_vencimento} · {r.modo_valor === 'fixo' ? 'Fixo' : `Variável (média ${r.janela_media}m)`}
								{#if r.membro_id}· {membro(r.membro_id)?.nome}{/if}
								{#if r.acumula}· várias vezes{/if}
								{#if !r.ativo}· Inativa{/if}
							</p>
						</div>
						<p class="font-semibold tabular-nums {r.tipo === 'receita' ? 'text-receita' : ''}">
							{r.modo_valor === 'variavel' ? '~' : ''}{brl(r.valor_base)}
						</p>
					</button>
				</li>
			{/each}
		</ul>
	{:else}
		<p class="card text-sm text-zinc-500">Nenhuma {g.tipo} cadastrada.</p>
	{/if}
{/each}

<button class="fab" onclick={() => abrir(null)} aria-label="Nova recorrência">+</button>

<Sheet bind:open={aberto} title={atual ? 'Editar recorrência' : 'Nova recorrência'}>
	<form class="space-y-4" onsubmit={salvar}>
		<CamposBase bind:f />
		<Seg bind:value={f.modo_valor} options={[['fixo', 'Valor fixo'], ['variavel', 'Varia todo mês']]} />
		<div class="grid grid-cols-2 gap-3">
			<div>
				<label class="label" for="valor">{f.modo_valor === 'fixo' ? 'Valor' : 'Estimativa inicial'}</label>
				<input id="valor" class="input tabular-nums" inputmode="decimal" placeholder="0,00" required bind:value={f.valor} />
			</div>
			<div>
				<label class="label" for="dia">Dia do vencimento</label>
				<input id="dia" class="input" type="number" inputmode="numeric" min="1" max="31" required bind:value={f.dia_vencimento} />
			</div>
		</div>
		{#if f.modo_valor === 'variavel'}
			<div>
				<label class="label" for="janela">Previsão = média dos últimos</label>
				<select id="janela" class="input" bind:value={f.janela_media}>
					{#each [1, 2, 3, 4, 6, 12] as n (n)}<option value={n}>{n} {n === 1 ? 'mês' : 'meses'}</option>{/each}
				</select>
			</div>
		{/if}
		<div class="grid grid-cols-2 gap-3">
			<div>
				<label class="label" for="inicio">Início</label>
				<input id="inicio" class="input" type="month" required bind:value={f.inicio} />
			</div>
			<div>
				<label class="label" for="fim">Fim (opcional)</label>
				<input id="fim" class="input" type="month" bind:value={f.fim} />
			</div>
		</div>
		<label class="flex items-center justify-between gap-3 rounded-xl bg-zinc-100 px-3 py-3 dark:bg-zinc-800">
			<span>
				<span class="block font-medium">Paga em várias vezes no mês</span>
				<span class="block text-xs text-zinc-500">Ex.: faxina paga com saques. Só fica paga quando a soma atinge o previsto.</span>
			</span>
			<input type="checkbox" class="size-5 shrink-0 accent-brand" bind:checked={f.acumula} />
		</label>
		{#if atual}
			<label class="flex items-center justify-between rounded-xl bg-zinc-100 px-3 py-3 dark:bg-zinc-800">
				<span class="font-medium">Ativa</span>
				<input type="checkbox" class="size-5 accent-brand" bind:checked={f.ativo} />
			</label>
		{/if}
		<button class="btn btn-primary w-full">Salvar</button>
		{#if atual}<button type="button" class="btn w-full text-despesa" onclick={excluir}>Excluir</button>{/if}
	</form>
</Sheet>
