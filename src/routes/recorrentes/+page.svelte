<script lang="ts">
	import { app, carregarCadastros, cat, membro } from '#lib/app.svelte.ts';
	import CamposBase from '#lib/components/CamposBase.svelte';
	import Icone from '#lib/components/Icone.svelte';
	import Seg from '#lib/components/Seg.svelte';
	import Sheet from '#lib/components/Sheet.svelte';
	import { brl, mesAtual, parseValor, valorInput } from '#lib/format.ts';
	import { ok, sb } from '#lib/supabase.ts';
	import type { Recorrencia, Tipo } from '#lib/types.ts';

	let itens = $state<Recorrencia[]>([]);

	async function carregar() {
		itens = ok(
			await sb.from('recorrencias').select('*').eq('residencia_id', app.res!.id).order('ativo', { ascending: false }).order('dia_vencimento')
		) as Recorrencia[];
	}
	carregar();

	/** Despesas: "geral" = fora do cartão; "cartao" = embutidas na fatura (já somadas na fatura, nunca juntas). */
	let filtroDespesa = $state<'geral' | 'cartao'>('geral');
	const despesas = $derived(itens.filter((r) => r.tipo === 'despesa'));
	const qtdCartao = $derived(despesas.filter((r) => r.cartao_conta_id).length);

	const grupos = $derived(
		(['receita', 'despesa'] as Tipo[]).map((tipo) => {
			const ls = itens.filter(
				(r) => r.tipo === tipo && (tipo === 'receita' || (filtroDespesa === 'cartao') === !!r.cartao_conta_id)
			);
			// total só do que está na lista exibida
			return { tipo, ls, total: ls.filter((r) => r.ativo).reduce((s, r) => s + Number(r.valor_base), 0) };
		})
	);

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
		acumula: false,
		cartao_conta_id: null as string | null
	});

	function abrir(r: Recorrencia | null) {
		atual = r;
		f = r
			? { ...r, valor: valorInput(r.valor_base), inicio: r.inicio.slice(0, 7), fim: r.fim?.slice(0, 7) ?? '' }
			: { tipo: 'despesa', descricao: '', categoria_id: null, membro_id: null, modo_valor: 'fixo', valor: '', janela_media: 3, dia_vencimento: 10, inicio: mesAtual().slice(0, 7), fim: '', ativo: true, acumula: false, cartao_conta_id: null };
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
			cartao_conta_id: resto.tipo === 'despesa' ? resto.cartao_conta_id : null,
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
		// mostra a aba onde a recorrência salva aparece
		if (row.tipo === 'despesa') filtroDespesa = row.cartao_conta_id ? 'cartao' : 'geral';
		// atualiza também a lista global (usada no Mês para embutidas e "várias vezes")
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
	<h2 class="mt-6 mb-2 flex justify-between px-1 text-sm font-semibold text-zinc-500">
		<span>{g.tipo === 'receita' ? 'Receitas' : 'Despesas'}</span>
		<span>{brl(g.total)}/mês</span>
	</h2>
	{#if g.tipo === 'despesa'}
		<div class="mb-2 flex gap-2">
			{#each [['geral', 'Geral', despesas.length - qtdCartao], ['cartao', 'Cartão', qtdCartao]] as const as [v, r, n] (v)}
				<button
					class="chip shrink-0 px-3 py-1.5 text-xs {filtroDespesa === v ? 'bg-brand text-white' : 'bg-white text-zinc-600 dark:bg-zinc-900 dark:text-zinc-300'}"
					onclick={() => (filtroDespesa = v)}>{r} ({n})</button
				>
			{/each}
		</div>
	{/if}
	{#if g.ls.length}
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
								{#if r.cartao_conta_id}· no cartão{/if}
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
		<p class="card text-sm text-zinc-500">
			{g.tipo === 'despesa' && filtroDespesa === 'cartao'
				? "Nenhuma despesa marcada como paga no cartão. Edite uma recorrente e escolha o cartão em 'Paga no cartão'."
				: `Nenhuma ${g.tipo} cadastrada.`}
		</p>
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
		{#if f.tipo === 'despesa' && app.contas.some((c) => c.tipo === 'cartao')}
			<div>
				<label class="label" for="cartao">Paga no cartão (embutida na fatura)</label>
				<select id="cartao" class="input" bind:value={f.cartao_conta_id}>
					<option value={null}>Não</option>
					{#each app.contas.filter((c) => c.tipo === 'cartao') as c (c.id)}<option value={c.id}>{c.nome}</option>{/each}
				</select>
				<p class="mt-1 text-xs text-zinc-500">
					Acompanhada pelas compras do cartão com a mesma categoria; não soma nos totais do mês (a fatura já soma).
				</p>
			</div>
		{/if}
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
