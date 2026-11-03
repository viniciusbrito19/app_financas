<script lang="ts">
	import { app, mediaCartao as calcMedia, cat, contaNoTotal, MEIOS, membro, rotuloCartao } from '#lib/app.svelte.ts';
	import CamposBase from '#lib/components/CamposBase.svelte';
	import Icone from '#lib/components/Icone.svelte';
	import Reclassificar from '#lib/components/Reclassificar.svelte';
	import MonthPicker from '#lib/components/MonthPicker.svelte';
	import Seg from '#lib/components/Seg.svelte';
	import Sheet from '#lib/components/Sheet.svelte';
	import { addMes, brl, dataCurta, hoje, parseValor, valorInput } from '#lib/format.ts';
	import { ok, sb } from '#lib/supabase.ts';
	import type { Lancamento, Meta, Tipo, Transacao } from '#lib/types.ts';

	/** opções da recorrência vêm junto do banco (não dependem da lista em memória, que pode estar desatualizada) */
	type Opcoes = { recorrencias?: { acumula: boolean } | null };
	type L = Lancamento & Opcoes & { transacoes: { count: number }[] };

	let itens = $state<L[]>([]);
	/** gastos/receitas importados que não correspondem a nenhum lançamento previsto */
	let outros = $state<Transacao[]>([]);
	let carregando = $state(true);

	async function carregar(mes = app.mes) {
		ok(await sb.rpc('gerar_mes', { p_res: app.res!.id, p_comp: mes }));
		const cartoes = app.contas.filter((c) => c.tipo === 'cartao').map((c) => c.id);
		const [ls, ts, ms] = await Promise.all([
			sb.from('lancamentos').select('*, transacoes(count), recorrencias(acumula)')
				.eq('residencia_id', app.res!.id)
				.eq('competencia', mes)
				.neq('status', 'cancelado')
				.order('vencimento'),
			sb
				.from('transacoes')
				.select('*')
				.eq('residencia_id', app.res!.id)
				.eq('competencia', mes)
				.eq('projetada', false)
				.is('lancamento_id', null)
				.in('natureza', ['gasto', 'receita'])
				.order('data'),
			sb.from('metas_cartao').select('*').eq('residencia_id', app.res!.id)
		]);
		const lancs = ok(ls) as L[];
		// compras do cartão do mês (realizado das metas)
		const compras = cartoes.length
			? (ok(
					await sb
						.from('transacoes')
						.select('*')
						.eq('residencia_id', app.res!.id)
						.eq('competencia', mes)
						.eq('natureza', 'gasto')
						.eq('projetada', false)
						.in('conta_id', cartoes)
						.order('data')
				) as Transacao[])
			: [];
		if (mes === app.mes) {
			itens = lancs;
			// gasto do cartão só entra nos totais pela fatura, nunca pelos itens
			outros = (ok(ts) as Transacao[]).filter((t) => !cartoes.includes(t.conta_id));
			comprasCartao = compras;
			metas = ok(ms) as Meta[];
			carregando = false;
		}
	}

	/** compras do cartão no mês (realizado das metas) */
	let comprasCartao = $state<Transacao[]>([]);
	let metas = $state<Meta[]>([]);
	let metaAberta = $state<string | null>(null);

	/**
	 * Cartão: meta x itens da fatura por categoria (com meta ou com gasto). Só acompanhamento:
	 * fora dos totais, pois a fatura já soma. Estouradas primeiro, depois por gasto.
	 */
	const porCategoria = $derived.by(() => {
		const ids = new Set([...metas.map((m) => m.categoria_id), ...comprasCartao.map((t) => t.categoria_id ?? '')]);
		return [...ids]
			.map((id) => {
				const ts = comprasCartao.filter((t) => (t.categoria_id ?? '') === id);
				const meta = metas.find((m) => m.categoria_id === id);
				return { id, ts, meta: meta ? Number(meta.valor) : null, real: -ts.reduce((s, t) => s + Number(t.valor), 0) };
			})
			.sort((a, b) => +(b.meta !== null && b.real > b.meta) - +(a.meta !== null && a.real > a.meta) || b.real - a.real);
	});
	const totalMetas = $derived(metas.reduce((s, m) => s + Number(m.valor), 0));
	const totalCartao = $derived(porCategoria.reduce((s, g) => s + g.real, 0));

	const conciliado = (l: L) => (l.transacoes[0]?.count ?? 0) > 0;

	/** "Outros gastos" agrupados por categoria (receita = valor positivo). */
	const outrosGrupos = $derived.by(() => {
		const m = new Map<string, { id: string | null; ts: Transacao[]; total: number }>();
		for (const t of outros.filter((t) => t.valor < 0)) {
			const k = t.categoria_id ?? '';
			const g = m.get(k) ?? m.set(k, { id: t.categoria_id, ts: [], total: 0 }).get(k)!;
			g.ts.push(t);
			g.total -= t.valor;
		}
		return [...m.values()].sort((a, b) => b.total - a.total);
	});
	const outrasReceitas = $derived(outros.filter((t) => t.valor > 0));
	let expandido = $state<string | null>(null);

	$effect(() => {
		carregando = true;
		carregar(app.mes);
	});

	/** Lançamento da fatura do cartão (recorrência ligada a uma ou mais contas-cartão). */
	const ehFatura = (l: Lancamento) => app.contas.some((c) => c.tipo === 'cartao' && c.recorrencia_id === l.recorrencia_id);

	/**
	 * Recorrência paga em várias vezes (ex.: faxina em saques) ainda sem atingir o previsto.
	 * Não se aplica à fatura: o valor real dela é o total dos PDFs, não o que já foi pago.
	 */
	const parcial = (l: Lancamento & Opcoes) =>
		l.status !== 'pago' && l.valor_real != null && !!l.recorrencias?.acumula && !ehFatura(l);

	/** Melhor valor conhecido: o real, se informado; senão o previsto. Parcial: o maior dos dois. */
	const valor = (l: Lancamento) =>
		parcial(l) ? Math.max(Number(l.valor_real), Number(l.valor_previsto)) : Number(l.valor_real ?? l.valor_previsto);
	const soma = (ls: Lancamento[]) => ls.reduce((s, l) => s + valor(l), 0);
	/** Quanto já saiu/entrou: pagos inteiros + o realizado dos parciais. */
	const somaPaga = (ls: Lancamento[]) =>
		ls.reduce((s, l) => s + (l.status === 'pago' ? valor(l) : parcial(l) ? Number(l.valor_real) : 0), 0);

	const grupos = $derived(
		(['receita', 'despesa'] as Tipo[]).map((tipo) => {
			const ls = itens
				.filter((l) => l.tipo === tipo)
				.sort((a, b) => +(a.status === 'pago') - +(b.status === 'pago') || a.vencimento.localeCompare(b.vencimento));
			// importados não previstos já são realizados: entram no total e no pago
			const extra = outros.filter((t) => (tipo === 'receita' ? t.valor > 0 : t.valor < 0)).reduce((s, t) => s + Math.abs(t.valor), 0);
			return { tipo, ls, total: soma(ls) + extra, pago: somaPaga(ls) + extra };
		})
	);
	const [rec, desp] = $derived(grupos);

	// --- abas das despesas: cada uma mostra (e soma) só o que exibe ------------
	let filtroDespesa = $state<'geral' | 'cartao' | 'naoPrevistas'>('geral');
	/** recorrentes fora do cartão */
	const despGeral = $derived(desp.ls.filter((l) => l.recorrencia_id));
	/** lançados à mão, sem recorrência */
	const despAvulsas = $derived(desp.ls.filter((l) => !l.recorrencia_id));
	const totalOutros = $derived(outrosGrupos.reduce((s, g) => s + g.total, 0));
	const abasDespesa = $derived([
		{ v: 'geral', rotulo: 'Geral', n: despGeral.length, total: soma(despGeral) },
		{ v: 'cartao', rotulo: 'Cartão', n: porCategoria.length, total: totalCartao },
		{
			v: 'naoPrevistas',
			rotulo: 'Não previstas',
			n: despAvulsas.length + outrosGrupos.reduce((s, g) => s + g.ts.length, 0),
			total: soma(despAvulsas) + totalOutros
		}
	] as const);
	const abaAtual = $derived(abasDespesa.find((a) => a.v === filtroDespesa)!);

	function situacao(l: Lancamento) {
		if (l.status === 'pago')
			return { txt: `${l.tipo === 'receita' ? 'Recebido' : 'Pago'} ${dataCurta(l.pago_em ?? l.vencimento)}`, cls: 'bg-emerald-500/15 text-emerald-600' };
		if (parcial(l)) return { txt: `Parcial ${brl(l.valor_real)} de ${brl(l.valor_previsto)}`, cls: 'bg-amber-500/15 text-amber-600' };
		if (l.vencimento < hoje()) return { txt: 'Atrasado', cls: 'bg-rose-500/15 text-rose-600' };
		return { txt: `Vence ${dataCurta(l.vencimento)}`, cls: 'bg-zinc-500/15 text-zinc-500' };
	}

	/** Diferença real x previsto (só para recorrentes com valor real informado). */
	function desvio(l: Lancamento) {
		if (!l.recorrencia_id || l.valor_real == null || !l.valor_previsto || parcial(l)) return null;
		const pct = Math.round(((l.valor_real - l.valor_previsto) / l.valor_previsto) * 100);
		if (pct === 0) return null;
		const ruim = l.tipo === 'despesa' ? pct > 0 : pct < 0;
		return { txt: `${pct > 0 ? '+' : ''}${pct}% vs previsto`, cls: ruim ? 'text-rose-600' : 'text-emerald-600' };
	}

	async function alternarPago(l: Lancamento) {
		const pago = l.status !== 'pago';
		ok(
			await sb
				.from('lancamentos')
				.update({ status: pago ? 'pago' : 'previsto', pago_em: pago ? hoje() : null, valor_real: pago ? valor(l) : l.valor_real })
				.eq('id', l.id)
		);
		carregar();
	}

	// --- edição ------------------------------------------------------------
	let aberto = $state(false);
	let atual = $state<Lancamento | null>(null);
	let f = $state({ tipo: 'despesa' as Tipo, descricao: '', categoria_id: null as string | null, membro_id: null as string | null, valor: '', vencimento: '', status: 'previsto' as Lancamento['status'], pago_em: '' });

	// --- transações vinculadas (ex.: itens da fatura do cartão) por categoria ----
	let vinculadas = $state<Transacao[]>([]);
	/** média mensal por categoria dos gastos no cartão nos 3 meses anteriores */
	let mediaCartao = $state<Record<string, number> | null>(null);
	let grupoAberto = $state<string | null>(null);
	/** transação em reclassificação */
	let reclass = $state<Transacao | null>(null);

	async function carregarVinculadas(l: Lancamento) {
		const ts = ok(await sb.from('transacoes').select('*').eq('lancamento_id', l.id).order('data')) as Transacao[];
		// fatura: itens são do mês anterior ao vencimento; média dos 3 meses antes deles
		mediaCartao = ts.some((t) => t.meio === 'cartao') ? await calcMedia(addMes(l.competencia, -1)) : null;
		vinculadas = ts;
	}

	/** fatura com vários cartões: agrupar por categoria ou por cartão (titular/adicionais) */
	let agruparPor = $state<'categoria' | 'cartao'>('categoria');
	const variosCartoes = $derived(new Set(vinculadas.map((t) => t.cartao).filter(Boolean)).size > 1);

	const gruposVinculadas = $derived.by(() => {
		const m = new Map<string, { id: string; ts: Transacao[]; total: number }>();
		const porCartao = agruparPor === 'cartao' && variosCartoes;
		for (const t of vinculadas) {
			const k =
				t.natureza === 'pagamento_fatura' ? 'pagamento' : !contaNoTotal(t.natureza) ? 'fora' : porCartao ? `cartao:${t.cartao ?? ''}` : (t.categoria_id ?? '');
			const g = m.get(k) ?? m.set(k, { id: k, ts: [], total: 0 }).get(k)!;
			g.ts.push(t);
			g.total -= t.valor;
		}
		const fim = (id: string) => (id === 'pagamento' ? 2 : id === 'fora' ? 1 : 0);
		return [...m.values()].sort((a, b) => fim(a.id) - fim(b.id) || b.total - a.total);
	});

	// --- vincular, a partir da prevista, transações do extrato ainda soltas no mês ----
	let candidatas = $state<Transacao[]>([]);
	let mostrarCandidatas = $state(false);

	/** Transações de conta corrente do mês, sem vínculo, do mesmo sentido (saída/entrada) da prevista. */
	async function carregarCandidatas(l: Lancamento) {
		const correntes = app.contas.filter((c) => c.tipo === 'corrente').map((c) => c.id);
		const despesa = l.tipo === 'despesa';
		let q = sb
			.from('transacoes')
			.select('*')
			.eq('residencia_id', app.res!.id)
			.eq('competencia', l.competencia)
			.eq('projetada', false)
			.is('lancamento_id', null)
			.in('conta_id', correntes)
			.in('natureza', despesa ? ['gasto', 'pagamento_fatura'] : ['receita'])
			.order('data');
		q = despesa ? q.lt('valor', 0) : q.gt('valor', 0);
		candidatas = ok(await q) as Transacao[];
	}

	async function vincular(t: Transacao) {
		const l = atual!;
		ok(await sb.rpc('vincular_transacao', { p_tx: t.id, p_lanc: l.id }));
		// status e valor real recalculados no banco: reflete no formulário aberto
		const novo = ok(await sb.from('lancamentos').select('*').eq('id', l.id).single()) as Lancamento;
		atual = { ...l, ...novo };
		f = { ...f, status: novo.status, valor: valorInput(novo.valor_real ?? novo.valor_previsto), pago_em: novo.pago_em ?? hoje() };
		await Promise.all([carregarVinculadas(novo), carregarCandidatas(novo), carregar()]);
	}

	async function abrir(l: L | null) {
		atual = l;
		vinculadas = [];
		candidatas = [];
		mostrarCandidatas = false;
		grupoAberto = null;
		if (l && conciliado(l)) carregarVinculadas(l);
		if (l?.recorrencia_id) carregarCandidatas(l);
		f = l
			? { ...l, valor: valorInput(l.valor_real ?? l.valor_previsto), pago_em: l.pago_em ?? hoje() }
			: { tipo: 'despesa', descricao: '', categoria_id: null, membro_id: null, valor: '', vencimento: hoje().startsWith(app.mes.slice(0, 8)) ? hoje() : app.mes, status: 'previsto', pago_em: hoje() };
		aberto = true;
	}

	async function salvar(e: SubmitEvent) {
		e.preventDefault();
		const v = f.valor.trim() ? parseValor(f.valor) : null;
		const row = {
			tipo: f.tipo,
			descricao: f.descricao,
			categoria_id: f.categoria_id,
			membro_id: f.membro_id,
			vencimento: f.vencimento,
			status: f.status,
			pago_em: f.status === 'pago' ? f.pago_em || hoje() : null
		};
		if (atual?.recorrencia_id) {
			// recorrente: o valor digitado é o real; o previsto continua como referência
			const real = v ?? (f.status === 'pago' ? atual.valor_previsto : null);
			ok(await sb.from('lancamentos').update({ ...row, valor_real: real }).eq('id', atual.id));
		} else {
			const valores = { valor_previsto: v ?? 0, valor_real: f.status === 'pago' ? (v ?? 0) : null };
			ok(
				atual
					? await sb.from('lancamentos').update({ ...row, ...valores }).eq('id', atual.id)
					: await sb.from('lancamentos').insert({ ...row, ...valores, residencia_id: app.res!.id, competencia: app.mes })
			);
		}
		aberto = false;
		carregar();
	}

	/**
	 * Avulso: apaga. Recorrente: cancela só este mês (gerar_mes não o recria; a recorrente segue
	 * nos próximos meses) e desliga as transações, que passam a "Não previstas".
	 */
	async function excluir() {
		if (!atual) return;
		const recorrente = !!atual.recorrencia_id;
		const aviso = !recorrente
			? 'Excluir este lançamento?'
			: `Excluir "${atual.descricao}" só deste mês? A recorrente continua nos próximos meses.` +
				(ehFatura(atual)
					? ' Os itens e pagamentos ligados a esta fatura passam a contar como não previstos.'
					: ' Transações do extrato ligadas a ele passam para "Não previstas".');
		if (!confirm(aviso)) return;
		if (recorrente) {
			ok(await sb.from('transacoes').update({ lancamento_id: null }).eq('lancamento_id', atual.id));
			ok(await sb.from('lancamentos').update({ status: 'cancelado', valor_real: null, pago_em: null }).eq('id', atual.id));
		} else {
			ok(await sb.from('lancamentos').delete().eq('id', atual.id));
		}
		aberto = false;
		carregar();
	}
</script>

<MonthPicker bind:value={app.mes} />

<section class="card mt-3 bg-gradient-to-br from-brand to-indigo-700 text-white dark:from-brand dark:to-indigo-800">
	<p class="text-sm opacity-80">Saldo previsto do mês</p>
	<p class="text-3xl font-bold tracking-tight">{brl(rec.total - desp.total)}</p>
	<div class="mt-4 grid grid-cols-2 gap-3 text-sm">
		<div class="rounded-xl bg-white/15 p-3">
			<p class="opacity-80">Receitas</p>
			<p class="text-lg font-semibold">{brl(rec.total)}</p>
			<p class="text-xs opacity-80">recebido {brl(rec.pago)}</p>
		</div>
		<div class="rounded-xl bg-white/15 p-3">
			<p class="opacity-80">Despesas</p>
			<p class="text-lg font-semibold">{brl(desp.total)}</p>
			<p class="text-xs opacity-80">pago {brl(desp.pago)}</p>
		</div>
	</div>
</section>

{#if carregando}
	<p class="mt-8 text-center text-zinc-500">Carregando…</p>
{:else if !itens.length && !outros.length}
	<div class="card mt-4 text-center text-zinc-500">
		<p>Nenhum lançamento neste mês.</p>
		<p class="text-sm">Cadastre receitas e despesas em <b>Recorrentes</b> ou toque em + para um avulso.</p>
	</div>
{:else}
	{#if rec.ls.length}
		<h2 class="mt-6 mb-2 flex justify-between px-1 text-sm font-semibold text-zinc-500">
			<span>Receitas</span><span>{brl(rec.total)}</span>
		</h2>
		<ul class="card divide-y divide-zinc-100 p-0 dark:divide-zinc-800">
			{#each rec.ls as l (l.id)}{@render linhaLancamento(l)}{/each}
		</ul>
	{/if}

	<h2 class="mt-6 mb-2 flex justify-between px-1 text-sm font-semibold text-zinc-500">
		<span>Despesas</span><span>{brl(abaAtual.total)}</span>
	</h2>
	<div class="-mx-4 mb-2 flex gap-2 overflow-x-auto px-4 pb-1">
		{#each abasDespesa as a (a.v)}
			<button
				class="chip shrink-0 px-3 py-1.5 text-xs {filtroDespesa === a.v ? 'bg-brand text-white' : 'bg-white text-zinc-600 dark:bg-zinc-900 dark:text-zinc-300'}"
				onclick={() => (filtroDespesa = a.v)}>{a.rotulo} ({a.n})</button
			>
		{/each}
	</div>

	{#if filtroDespesa === 'geral'}
		{#if despGeral.length}
			<ul class="card divide-y divide-zinc-100 p-0 dark:divide-zinc-800">
				{#each despGeral as l (l.id)}{@render linhaLancamento(l)}{/each}
			</ul>
		{:else}
			<p class="card text-sm text-zinc-500">Nenhuma despesa recorrente neste mês.</p>
		{/if}
	{:else if filtroDespesa === 'cartao'}
		<p class="mb-2 px-1 text-xs text-zinc-500">
			Gasto no cartão x meta por categoria{totalMetas ? ` (metas ${brl(totalMetas)})` : ''}. Não soma nos totais do mês: a fatura já soma.
		</p>
		{#if porCategoria.length}
		<ul class="card divide-y divide-zinc-100 p-0 dark:divide-zinc-800">
			{#each porCategoria as g (g.id)}
				{@const c = cat(g.id || null)}
				{@const passou = g.meta !== null && g.real > g.meta}
				<li>
					<button class="flex w-full items-center gap-3 px-3 py-3 text-left" onclick={() => (metaAberta = metaAberta === g.id ? null : g.id)}>
						<Icone {c} />
						<div class="min-w-0 flex-1">
							<p class="truncate font-medium">{c?.nome ?? 'Sem categoria'}</p>
							<p class="text-xs {passou ? 'text-rose-600' : 'text-zinc-500'}">
								{g.meta !== null ? `${brl(g.real)} de ${brl(g.meta)}` : 'sem meta'} · {g.ts.length} {g.ts.length === 1 ? 'compra' : 'compras'}
							</p>
							{#if g.meta !== null}
								<div class="mt-1.5 h-1 rounded-full bg-zinc-200 dark:bg-zinc-700">
									<div class="h-full rounded-full {passou ? 'bg-rose-500' : 'bg-amber-500'}" style:width="{Math.min(100, g.meta ? (g.real / g.meta) * 100 : 100)}%"></div>
								</div>
							{/if}
						</div>
						<p class="font-semibold tabular-nums">{brl(g.real)}</p>
					</button>
					{#if metaAberta === g.id}
						<ul class="bg-zinc-50 px-3 pb-2 dark:bg-zinc-950/40">
							{#each g.ts as t (t.id)}{@render itemTransacao(t)}{:else}
								<li class="py-2 text-xs text-zinc-500">Nenhuma compra no cartão nesta categoria neste mês.</li>
							{/each}
						</ul>
					{/if}
				</li>
			{/each}
		</ul>
		{:else}
			<p class="card text-sm text-zinc-500">Nenhuma compra no cartão neste mês. Defina metas em Recorrentes → Cartão.</p>
		{/if}
	{:else}
		{#if despAvulsas.length}
			<ul class="card divide-y divide-zinc-100 p-0 dark:divide-zinc-800">
				{#each despAvulsas as l (l.id)}{@render linhaLancamento(l)}{/each}
			</ul>
		{/if}
		{#if outrosGrupos.length}
			<div class={despAvulsas.length ? 'mt-3' : ''}>
			<ul class="card divide-y divide-zinc-100 p-0 dark:divide-zinc-800">
				{#each outrosGrupos as g (g.id)}
					{@const c = cat(g.id)}
					<li>
						<button class="flex w-full items-center gap-3 px-3 py-3 text-left" onclick={() => (expandido = expandido === g.id ? null : g.id)}>
							<Icone {c} />
							<div class="min-w-0 flex-1">
								<p class="truncate font-medium">{c?.nome ?? 'Sem categoria'}</p>
								<p class="text-xs text-zinc-500">{g.ts.length} {g.ts.length === 1 ? 'transação' : 'transações'}</p>
							</div>
							<p class="font-semibold tabular-nums">{brl(g.total)}</p>
						</button>
						{#if expandido === g.id}
							<ul class="bg-zinc-50 px-3 pb-2 dark:bg-zinc-950/40">
								{#each g.ts as t (t.id)}{@render itemTransacao(t)}{/each}
							</ul>
						{/if}
					</li>
				{/each}
			</ul>
			</div>
		{/if}
		{#if !despAvulsas.length && !outrosGrupos.length}
			<p class="card text-sm text-zinc-500">Nenhuma despesa não prevista neste mês.</p>
		{/if}
	{/if}

	{#if outrasReceitas.length}
		<h2 class="mt-6 mb-2 px-1 text-sm font-semibold text-zinc-500">Outras entradas</h2>
		<ul class="card divide-y divide-zinc-100 px-3 py-1 dark:divide-zinc-800">
			{#each outrasReceitas as t (t.id)}{@render itemTransacao(t)}{/each}
		</ul>
	{/if}
{/if}

<button class="fab" onclick={() => abrir(null)} aria-label="Novo lançamento avulso">+</button>

{#snippet linhaLancamento(l: L)}
	{@const s = situacao(l)}
	{@const d = desvio(l)}
		<li class="flex items-center gap-3 px-3 py-3">
			<button class="relative" onclick={() => alternarPago(l)} aria-label={l.status === 'pago' ? 'Desmarcar pago' : 'Marcar como pago'}>
				<Icone c={cat(l.categoria_id)} />
				{#if l.status === 'pago'}<span class="absolute -right-1 -bottom-1 grid size-5 place-items-center rounded-full bg-emerald-500 text-[11px] text-white ring-2 ring-white dark:ring-zinc-900">✓</span>{/if}
			</button>
			<button class="flex min-w-0 flex-1 items-center gap-2 text-left" onclick={() => abrir(l)}>
				<div class="min-w-0 flex-1">
					<p class="truncate font-medium {l.status === 'pago' ? 'text-zinc-400' : ''}">{l.descricao}</p>
					<p class="flex flex-wrap items-center gap-1.5 text-xs text-zinc-500">
						<span class="chip {s.cls}">{s.txt}</span>
						{#if l.membro_id}<span>{membro(l.membro_id)?.nome}</span>{/if}
						{#if d}<span class={d.cls}>{d.txt}</span>{/if}
						{#if conciliado(l)}<span title="Conciliado com extrato/fatura">🔗</span>{/if}
					</p>
					{#if parcial(l)}
						<div class="mt-1.5 h-1 rounded-full bg-zinc-200 dark:bg-zinc-700">
							<div class="h-full rounded-full bg-amber-500" style:width="{Math.min(100, (Number(l.valor_real) / Number(l.valor_previsto)) * 100)}%"></div>
						</div>
					{/if}
				</div>
				<div class="text-right">
					<p class="font-semibold tabular-nums {l.tipo === 'receita' ? 'text-receita' : ''}">{brl(valor(l))}</p>
					{#if l.recorrencia_id && l.valor_real == null}<p class="text-[11px] text-zinc-400">estimado</p>{/if}
				</div>
			</button>
		</li>
{/snippet}

{#snippet itemTransacao(t: Transacao)}
	<li>
		<button type="button" class="flex w-full items-center gap-2 py-1.5 text-left text-sm" onclick={() => (reclass = t)}>
			<span class="w-11 shrink-0 text-xs text-zinc-500">{dataCurta(t.data)}</span>
			<span class="chip bg-zinc-500/15">{MEIOS[t.meio]}</span>
			<span class="min-w-0 flex-1">
				<span class="block truncate">{t.descricao}{t.parcela ? ` ${t.parcela}/${t.parcelas}` : ''}</span>
				{#if t.nota}<span class="block truncate text-xs text-zinc-500 italic">📝 {t.nota}</span>{/if}
			</span>
			<span class="tabular-nums {t.valor > 0 ? 'text-receita' : ''}">{brl(Math.abs(t.valor))}</span>
		</button>
	</li>
{/snippet}

<Sheet bind:open={aberto} title={atual ? (atual.recorrencia_id ? 'Lançamento recorrente' : 'Editar lançamento') : 'Lançamento avulso'}>
	{#if vinculadas.length}
		<div class="mb-4">
			<p class="label">{vinculadas.length} {vinculadas.length === 1 ? 'transação vinculada' : 'transações vinculadas'} · toque para ver e reclassificar</p>
			{#if variosCartoes}
				<div class="mb-2"><Seg bind:value={agruparPor} options={[['categoria', 'Por categoria'], ['cartao', 'Por cartão']]} /></div>
			{/if}
			<ul class="divide-y divide-zinc-200 rounded-xl bg-zinc-100 dark:divide-zinc-700 dark:bg-zinc-800">
				{#each gruposVinculadas as g (g.id)}
					{@const ehCartao = g.id.startsWith('cartao:')}
					{@const c = ehCartao ? undefined : cat(g.id || null)}
					{@const meta = ehCartao ? undefined : metas.find((m) => m.categoria_id === g.id)}
					{@const media = mediaCartao && g.id !== 'fora' && g.id !== 'pagamento' && !ehCartao ? (mediaCartao[g.id] ?? 0) : null}
					<li>
						<button type="button" class="flex w-full items-center gap-2 px-3 py-2.5 text-left text-sm" onclick={() => (grupoAberto = grupoAberto === g.id ? null : g.id)}>
							<span class="min-w-0 flex-1 truncate font-medium">
								{g.id === 'fora'
									? '⊘ Não contam'
									: g.id === 'pagamento'
										? '💸 Pagamento da fatura'
									: ehCartao
										? `💳 ${rotuloCartao(g.ts[0].conta_id, g.ts[0].cartao)}`
										: `${c?.icone ?? '•'} ${c?.nome ?? 'Sem categoria'}`}
								<span class="text-xs font-normal text-zinc-500">({g.ts.length})</span>
							</span>
							{#if meta}
								<span class="text-xs {g.total > Number(meta.valor) ? 'text-rose-600' : 'text-zinc-500'}">meta {brl(meta.valor)}</span>
							{:else if media !== null}
								<span class="text-xs {g.total > media * 1.2 && g.total - media > 50 ? 'text-rose-600' : 'text-zinc-500'}">média {brl(media)}</span>
							{/if}
							<span class="font-semibold tabular-nums">{brl(g.total)}</span>
						</button>
						{#if grupoAberto === g.id}
							<ul class="px-3 pb-2">
								{#each g.ts as t (t.id)}{@render itemTransacao(t)}{/each}
							</ul>
						{/if}
					</li>
				{/each}
			</ul>
		</div>
	{/if}
	{#if candidatas.length}
		<div class="mb-4 rounded-xl border border-dashed border-zinc-300 dark:border-zinc-700">
			<button type="button" class="flex w-full items-center justify-between px-3 py-2.5 text-left text-sm" onclick={() => (mostrarCandidatas = !mostrarCandidatas)}>
				<span class="font-medium">🔗 Vincular lançamentos do mês <span class="text-xs font-normal text-zinc-500">({candidatas.length} soltos)</span></span>
				<span class="text-zinc-400">{mostrarCandidatas ? '▴' : '▾'}</span>
			</button>
			{#if mostrarCandidatas}
				<ul class="divide-y divide-zinc-100 px-3 pb-2 dark:divide-zinc-800">
					{#each candidatas as t (t.id)}
						<li class="flex items-center gap-2 py-1.5 text-sm">
							<span class="w-11 shrink-0 text-xs text-zinc-500">{dataCurta(t.data)}</span>
							<span class="min-w-0 flex-1 truncate">{t.descricao}</span>
							<span class="tabular-nums">{brl(Math.abs(t.valor))}</span>
							<button type="button" class="rounded-lg bg-brand/10 px-2 py-1 text-xs font-semibold text-brand" onclick={() => vincular(t)}>Vincular</button>
						</li>
					{/each}
				</ul>
				<p class="px-3 pb-2 text-xs text-zinc-500">Para desvincular, toque na transação vinculada e escolha "Nenhum" em Conciliar.</p>
			{/if}
		</div>
	{/if}
	<form class="space-y-4" onsubmit={salvar}>
		<CamposBase bind:f />
		<div class="grid grid-cols-2 gap-3">
			<div>
				<label class="label" for="valor">{atual?.recorrencia_id ? 'Valor real' : 'Valor'}</label>
				<input id="valor" class="input tabular-nums" inputmode="decimal" placeholder="0,00" bind:value={f.valor} />
				{#if atual?.recorrencia_id}<p class="mt-1 text-xs text-zinc-500">Previsto: {brl(atual.valor_previsto)}</p>{/if}
			</div>
			<div>
				<label class="label" for="venc">Vencimento</label>
				<input id="venc" class="input" type="date" required bind:value={f.vencimento} />
			</div>
		</div>
		<Seg bind:value={f.status} options={[['previsto', 'Pendente'], ['pago', f.tipo === 'receita' ? 'Recebido' : 'Pago']]} />
		{#if f.status === 'pago'}
			<div>
				<label class="label" for="pagoem">Data do pagamento</label>
				<input id="pagoem" class="input" type="date" bind:value={f.pago_em} />
			</div>
		{/if}
		<button class="btn btn-primary w-full">Salvar</button>
		{#if atual}
			<button type="button" class="btn w-full text-despesa" onclick={excluir}>{atual.recorrencia_id ? 'Excluir só deste mês' : 'Excluir'}</button>
		{/if}
	</form>
</Sheet>

<!-- reclassificar uma transação (itens da fatura ou "Outros gastos") -->
<Reclassificar
	bind:t={reclass}
	onfeito={() => {
		carregar();
		if (aberto && atual) carregarVinculadas(atual);
	}}
/>
