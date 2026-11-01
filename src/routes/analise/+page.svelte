<script lang="ts">
	import { app, cat, MEIOS } from '#lib/app.svelte.ts';
	import Icone from '#lib/components/Icone.svelte';
	import MonthPicker from '#lib/components/MonthPicker.svelte';
	import Sheet from '#lib/components/Sheet.svelte';
	import { addMes, brl, dataCurta } from '#lib/format.ts';
	import { ok, sb } from '#lib/supabase.ts';
	import type { Transacao } from '#lib/types.ts';

	type Linha = { competencia: string; categoria_id: string | null; meio: keyof typeof MEIOS; valor: number };

	/** Fora do padrão: acima da média dos 3 meses anteriores em mais de 20% e de R$ 50. */
	const LIMITE_PCT = 0.2;
	const LIMITE_RS = 50;

	let linhas = $state<Linha[]>([]);
	let meio = $state<string>('');

	async function carregar(mes: string) {
		const dados = ok(
			await sb
				.from('v_gastos_categoria')
				.select('competencia, categoria_id, meio, valor')
				.eq('residencia_id', app.res!.id)
				.gte('competencia', addMes(mes, -3))
				.lte('competencia', mes)
		) as Linha[];
		if (mes === app.mes) linhas = dados;
	}
	$effect(() => {
		carregar(app.mes);
	});

	const filtradas = $derived(linhas.filter((l) => !meio || l.meio === meio));
	const meiosUsados = $derived([...new Set(linhas.map((l) => l.meio))]);

	const categorias = $derived.by(() => {
		const m = new Map<string, { id: string | null; atual: number; anteriores: number }>();
		for (const l of filtradas) {
			const k = l.categoria_id ?? '';
			const g = m.get(k) ?? m.set(k, { id: l.categoria_id, atual: 0, anteriores: 0 }).get(k)!;
			if (l.competencia === app.mes) g.atual += Number(l.valor);
			else g.anteriores += Number(l.valor);
		}
		return [...m.values()]
			.map((g) => {
				const media = g.anteriores / 3;
				const fora = g.atual - media > LIMITE_RS && g.atual > media * (1 + LIMITE_PCT);
				return { ...g, media, fora, pct: media ? Math.round((g.atual / media - 1) * 100) : null };
			})
			.filter((g) => g.atual || g.media)
			.sort((a, b) => +b.fora - +a.fora || b.atual - a.atual);
	});
	const total = $derived(categorias.reduce((s, g) => s + g.atual, 0));
	const totalMedia = $derived(categorias.reduce((s, g) => s + g.media, 0));
	const maior = $derived(Math.max(1, ...categorias.map((g) => Math.max(g.atual, g.media))));

	// --- detalhe de uma categoria ------------------------------------------
	let aberto = $state(false);
	let detalhe = $state<{ id: string | null; ts: Transacao[] }>({ id: null, ts: [] });

	async function abrir(id: string | null) {
		detalhe = { id, ts: [] };
		aberto = true;
		let q = sb
			.from('transacoes')
			.select('*')
			.eq('residencia_id', app.res!.id)
			.eq('competencia', app.mes)
			.eq('natureza', 'gasto')
			.eq('projetada', false)
			.order('valor');
		q = id ? q.eq('categoria_id', id) : q.is('categoria_id', null);
		if (meio) q = q.eq('meio', meio);
		detalhe.ts = ok(await q) as Transacao[];
	}
</script>

<MonthPicker bind:value={app.mes} />

<section class="card mt-3">
	<p class="text-sm text-zinc-500">Gasto realizado no mês</p>
	<p class="text-3xl font-bold tracking-tight">{brl(total)}</p>
	<p class="text-sm text-zinc-500">média dos 3 meses anteriores: {brl(totalMedia)}</p>
</section>

<div class="-mx-4 mt-4 flex gap-2 overflow-x-auto px-4 pb-1">
	{#each [['', 'Todos'], ...meiosUsados.map((m) => [m, MEIOS[m]])] as [v, r] (v)}
		<button class="chip shrink-0 px-3 py-1.5 text-xs {meio === v ? 'bg-brand text-white' : 'bg-white text-zinc-600 dark:bg-zinc-900 dark:text-zinc-300'}" onclick={() => (meio = v)}>{r}</button>
	{/each}
</div>

{#if !categorias.length}
	<p class="card mt-4 text-center text-sm text-zinc-500">Sem gastos realizados neste período. Importe extratos e faturas ou marque lançamentos como pagos.</p>
{:else}
	<ul class="card mt-3 divide-y divide-zinc-100 p-0 dark:divide-zinc-800">
		{#each categorias as g (g.id)}
			{@const c = cat(g.id)}
			<li>
				<button class="w-full px-3 py-3 text-left" onclick={() => abrir(g.id)}>
					<div class="flex items-center gap-3">
						<Icone {c} />
						<div class="min-w-0 flex-1">
							<p class="flex items-center gap-2 truncate font-medium">
								{c?.nome ?? 'Sem categoria'}
								{#if g.fora}<span class="chip bg-rose-500/15 text-rose-600">fora do padrão</span>{/if}
							</p>
							<p class="text-xs text-zinc-500">
								média {brl(g.media)}
								{#if g.pct !== null}<span class={g.pct > 0 ? 'text-rose-600' : 'text-emerald-600'}> · {g.pct > 0 ? '+' : ''}{g.pct}%</span>{/if}
							</p>
						</div>
						<p class="font-semibold tabular-nums">{brl(g.atual)}</p>
					</div>
					<!-- barra: mês atual x média (traço) -->
					<div class="relative mt-2 ml-13 h-1.5 rounded-full bg-zinc-100 dark:bg-zinc-800">
						<div class="h-full rounded-full {g.fora ? 'bg-rose-500' : 'bg-brand'}" style:width="{(g.atual / maior) * 100}%"></div>
						<div class="absolute -top-1 h-3.5 w-0.5 rounded bg-zinc-500" style:left="{(g.media / maior) * 100}%"></div>
					</div>
				</button>
			</li>
		{/each}
	</ul>
	<p class="mt-2 px-1 text-xs text-zinc-500">Fora do padrão: acima da média em mais de {LIMITE_PCT * 100}% e de {brl(LIMITE_RS)}.</p>
{/if}

<Sheet bind:open={aberto} title={cat(detalhe.id)?.nome ?? 'Sem categoria'}>
	{#if detalhe.ts.length}
		<ul class="divide-y divide-zinc-100 dark:divide-zinc-800">
			{#each detalhe.ts as t (t.id)}
				<li class="flex items-center gap-2 py-2.5 text-sm">
					<span class="w-11 text-xs text-zinc-500">{dataCurta(t.data)}</span>
					<span class="chip bg-zinc-500/15">{MEIOS[t.meio]}</span>
					<span class="min-w-0 flex-1 truncate">{t.descricao}</span>
					<span class="tabular-nums">{brl(-t.valor)}</span>
				</li>
			{/each}
		</ul>
	{:else}
		<p class="text-sm text-zinc-500">Sem transações importadas nesta categoria (valores podem vir de lançamentos pagos manualmente).</p>
	{/if}
</Sheet>
