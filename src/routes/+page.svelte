<script lang="ts">
	import { app, cat, contaNoTotal, MEIOS, membro, rotuloCartao } from '#lib/app.svelte.ts';
	import CamposBase from '#lib/components/CamposBase.svelte';
	import Icone from '#lib/components/Icone.svelte';
	import Reclassificar from '#lib/components/Reclassificar.svelte';
	import MonthPicker from '#lib/components/MonthPicker.svelte';
	import Seg from '#lib/components/Seg.svelte';
	import Sheet from '#lib/components/Sheet.svelte';
	import { addMes, brl, dataCurta, hoje, parseValor, valorInput } from '#lib/format.ts';
	import { ok, sb } from '#lib/supabase.ts';
	import type { Lancamento, Tipo, Transacao } from '#lib/types.ts';

	/** opções da recorrência vêm junto do banco (não dependem da lista em memória, que pode estar desatualizada) */
	type Opcoes = { recorrencias?: { acumula: boolean; cartao_conta_id: string | null } | null };
	type L = Lancamento & Opcoes & { transacoes: { count: number }[] };

	let itens = $state<L[]>([]);
	/** gastos/receitas importados que não correspondem a nenhum lançamento previsto */
	let outros = $state<Transacao[]>([]);
	let carregando = $state(true);

	async function carregar(mes = app.mes) {
		ok(await sb.rpc('gerar_mes', { p_res: app.res!.id, p_comp: mes }));
		const [ls, ts] = await Promise.all([
			sb.from('lancamentos').select('*, transacoes(count), recorrencias(acumula, cartao_conta_id)').eq('residencia_id', app.res!.id).eq('competencia', mes).order('vencimento'),
			sb
				.from('transacoes')
				.select('*')
				.eq('residencia_id', app.res!.id)
				.eq('competencia', mes)
				.eq('projetada', false)
				.is('lancamento_id', null)
				.in('natureza', ['gasto', 'receita'])
				.order('data')
		]);
		const lancs = ok(ls) as L[];
		// compras do cartão do mês, para acompanhar as recorrentes embutidas na fatura
		const contasEmb = [...new Set(lancs.map((l) => l.recorrencias?.cartao_conta_id).filter((c): c is string => !!c))];
		const compras = contasEmb.length
			? (ok(
					await sb
						.from('transacoes')
						.select('*')
						.eq('residencia_id', app.res!.id)
						.eq('competencia', mes)
						.eq('natureza', 'gasto')
						.eq('projetada', false)
						.in('conta_id', contasEmb)
						.order('data')
				) as Transacao[])
			: [];
		if (mes === app.mes) {
			itens = lancs;
			outros = ok(ts) as Transacao[];
			comprasCartao = compras;
			carregando = false;
		}
	}

	/** compras do cartão no mês (base do realizado das embutidas) */
	let comprasCartao = $state<Transacao[]>([]);
	let embutidaAberta = $state<string | null>(null);

	/** Recorrentes pagas no cartão: previsto x compras da mesma categoria; fora dos totais (a fatura já soma). */
	const embutidas = $derived(
		itens
			.filter((l) => !!l.recorrencias?.cartao_conta_id)
			.map((l) => {
				const contaId = l.recorrencias?.cartao_conta_id;
				const ts = comprasCartao.filter((t) => t.conta_id === contaId && t.categoria_id === l.categoria_id);
				return { l, ts, real: -ts.reduce((s, t) => s + Number(t.valor), 0) };
			})
	);

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

	/** Recorrência paga em várias vezes (ex.: faxina em saques) ainda sem atingir o previsto. */
	const parcial = (l: Lancamento & Opcoes) => l.status !== 'pago' && l.valor_real != null && !!l.recorrencias?.acumula;

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
				.filter((l) => l.tipo === tipo && !l.recorrencias?.cartao_conta_id)
				.sort((a, b) => +(a.status === 'pago') - +(b.status === 'pago') || a.vencimento.localeCompare(b.vencimento));
			// importados não previstos já são realizados: entram no total e no pago
			const extra = outros.filter((t) => (tipo === 'receita' ? t.valor > 0 : t.valor < 0)).reduce((s, t) => s + Math.abs(t.valor), 0);
			return { tipo, ls, total: soma(ls) + extra, pago: somaPaga(ls) + extra };
		})
	);
	const [rec, desp] = $derived(grupos);

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
		mediaCartao = null;
		if (ts.some((t) => t.meio === 'cartao')) {
			const hist = ok(
				await sb
					.from('v_gastos_categoria')
					.select('competencia, categoria_id, valor')
					.eq('residencia_id', app.res!.id)
					.eq('meio', 'cartao')
					.gte('competencia', addMes(l.competencia, -4))
					.lt('competencia', addMes(l.competencia, -1))
			) as { competencia: string; categoria_id: string | null; valor: number }[];
			const meses = new Set(hist.map((h) => h.competencia)).size;
			if (meses) {
				const m: Record<string, number> = {};
				for (const h of hist) m[h.categoria_id ?? ''] = (m[h.categoria_id ?? ''] ?? 0) + Number(h.valor) / meses;
				mediaCartao = m;
			}
		}
		vinculadas = ts;
	}

	/** fatura com vários cartões: agrupar por categoria ou por cartão (titular/adicionais) */
	let agruparPor = $state<'categoria' | 'cartao'>('categoria');
	const variosCartoes = $derived(new Set(vinculadas.map((t) => t.cartao).filter(Boolean)).size > 1);

	const gruposVinculadas = $derived.by(() => {
		const m = new Map<string, { id: string; ts: Transacao[]; total: number }>();
		const porCartao = agruparPor === 'cartao' && variosCartoes;
		for (const t of vinculadas) {
			const k = !contaNoTotal(t.natureza) ? 'fora' : porCartao ? `cartao:${t.cartao ?? ''}` : (t.categoria_id ?? '');
			const g = m.get(k) ?? m.set(k, { id: k, ts: [], total: 0 }).get(k)!;
			g.ts.push(t);
			g.total -= t.valor;
		}
		return [...m.values()].sort((a, b) => +(a.id === 'fora') - +(b.id === 'fora') || b.total - a.total);
	});

	async function abrir(l: L | null) {
		atual = l;
		vinculadas = [];
		grupoAberto = null;
		if (l && conciliado(l)) carregarVinculadas(l);
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

	async function excluir() {
		if (!atual || !confirm('Excluir este lançamento?')) return;
		ok(await sb.from('lancamentos').delete().eq('id', atual.id));
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
	{#each grupos as g (g.tipo)}
		{#if g.ls.length}
			<h2 class="mt-6 mb-2 flex justify-between px-1 text-sm font-semibold text-zinc-500">
				<span>{g.tipo === 'receita' ? 'Receitas' : 'Despesas'}</span><span>{brl(g.total)}</span>
			</h2>
			<ul class="card divide-y divide-zinc-100 p-0 dark:divide-zinc-800">
				{#each g.ls as l (l.id)}
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
				{/each}
			</ul>
		{/if}
	{/each}

	{#if embutidas.length}
		<h2 class="mt-6 mb-1 px-1 text-sm font-semibold text-zinc-500">Embutidas na fatura do cartão</h2>
		<p class="mb-2 px-1 text-xs text-zinc-500">Acompanhamento: não somam nos totais, pois já estão na fatura.</p>
		<ul class="card divide-y divide-zinc-100 p-0 dark:divide-zinc-800">
			{#each embutidas as e (e.l.id)}
				{@const prev = Number(e.l.valor_previsto)}
				{@const passou = e.real > prev}
				<li>
					<button class="flex w-full items-center gap-3 px-3 py-3 text-left" onclick={() => (embutidaAberta = embutidaAberta === e.l.id ? null : e.l.id)}>
						<Icone c={cat(e.l.categoria_id)} />
						<div class="min-w-0 flex-1">
							<p class="truncate font-medium">{e.l.descricao}</p>
							<p class="text-xs {passou ? 'text-rose-600' : 'text-zinc-500'}">
								{brl(e.real)} de {brl(prev)} · {e.ts.length} {e.ts.length === 1 ? 'compra' : 'compras'}
							</p>
							<div class="mt-1.5 h-1 rounded-full bg-zinc-200 dark:bg-zinc-700">
								<div class="h-full rounded-full {passou ? 'bg-rose-500' : 'bg-amber-500'}" style:width="{Math.min(100, prev ? (e.real / prev) * 100 : 0)}%"></div>
							</div>
						</div>
						<p class="font-semibold text-zinc-400 tabular-nums">{brl(prev)}</p>
					</button>
					{#if embutidaAberta === e.l.id}
						<ul class="bg-zinc-50 px-3 pb-2 dark:bg-zinc-950/40">
							{#each e.ts as t (t.id)}{@render itemTransacao(t)}{:else}
								<li class="py-2 text-xs text-zinc-500">Nenhuma compra no cartão com a categoria "{cat(e.l.categoria_id)?.nome ?? '—'}" neste mês.</li>
							{/each}
						</ul>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}

	{#if outrosGrupos.length}
		<h2 class="mt-6 mb-2 flex justify-between px-1 text-sm font-semibold text-zinc-500">
			<span>Outros gastos (não previstos)</span><span>{brl(outrosGrupos.reduce((s, g) => s + g.total, 0))}</span>
		</h2>
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
	{/if}

	{#if outrasReceitas.length}
		<h2 class="mt-6 mb-2 px-1 text-sm font-semibold text-zinc-500">Outras entradas</h2>
		<ul class="card divide-y divide-zinc-100 px-3 py-1 dark:divide-zinc-800">
			{#each outrasReceitas as t (t.id)}{@render itemTransacao(t)}{/each}
		</ul>
	{/if}
{/if}

<button class="fab" onclick={() => abrir(null)} aria-label="Novo lançamento avulso">+</button>

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
					{@const media = mediaCartao && g.id !== 'fora' && !ehCartao ? (mediaCartao[g.id] ?? 0) : null}
					<li>
						<button type="button" class="flex w-full items-center gap-2 px-3 py-2.5 text-left text-sm" onclick={() => (grupoAberto = grupoAberto === g.id ? null : g.id)}>
							<span class="min-w-0 flex-1 truncate font-medium">
								{g.id === 'fora'
									? '⊘ Não contam'
									: ehCartao
										? `💳 ${rotuloCartao(g.ts[0].conta_id, g.ts[0].cartao)}`
										: `${c?.icone ?? '•'} ${c?.nome ?? 'Sem categoria'}`}
								<span class="text-xs font-normal text-zinc-500">({g.ts.length})</span>
							</span>
							{#if media !== null}
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
		{#if atual && !atual.recorrencia_id}
			<button type="button" class="btn w-full text-despesa" onclick={excluir}>Excluir</button>
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
