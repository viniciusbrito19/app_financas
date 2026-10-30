<script lang="ts">
	import { app, cat, membro } from '#lib/app.svelte.ts';
	import CamposBase from '#lib/components/CamposBase.svelte';
	import Icone from '#lib/components/Icone.svelte';
	import MonthPicker from '#lib/components/MonthPicker.svelte';
	import Seg from '#lib/components/Seg.svelte';
	import Sheet from '#lib/components/Sheet.svelte';
	import { brl, dataCurta, hoje, parseValor, valorInput } from '#lib/format.ts';
	import { ok, sb } from '#lib/supabase.ts';
	import type { Lancamento, Tipo } from '#lib/types.ts';

	let itens = $state<Lancamento[]>([]);
	let carregando = $state(true);

	async function carregar(mes = app.mes) {
		ok(await sb.rpc('gerar_mes', { p_res: app.res!.id, p_comp: mes }));
		const dados = ok(
			await sb.from('lancamentos').select('*').eq('residencia_id', app.res!.id).eq('competencia', mes).order('vencimento')
		) as Lancamento[];
		if (mes === app.mes) {
			itens = dados;
			carregando = false;
		}
	}

	$effect(() => {
		carregando = true;
		carregar(app.mes);
	});

	/** Melhor valor conhecido: o real, se informado; senão o previsto. */
	const valor = (l: Lancamento) => Number(l.valor_real ?? l.valor_previsto);
	const soma = (ls: Lancamento[]) => ls.reduce((s, l) => s + valor(l), 0);

	const grupos = $derived(
		(['receita', 'despesa'] as Tipo[]).map((tipo) => {
			const ls = itens
				.filter((l) => l.tipo === tipo)
				.sort((a, b) => +(a.status === 'pago') - +(b.status === 'pago') || a.vencimento.localeCompare(b.vencimento));
			return { tipo, ls, total: soma(ls), pago: soma(ls.filter((l) => l.status === 'pago')) };
		})
	);
	const [rec, desp] = $derived(grupos);

	function situacao(l: Lancamento) {
		if (l.status === 'pago')
			return { txt: `${l.tipo === 'receita' ? 'Recebido' : 'Pago'} ${dataCurta(l.pago_em ?? l.vencimento)}`, cls: 'bg-emerald-500/15 text-emerald-600' };
		if (l.vencimento < hoje()) return { txt: 'Atrasado', cls: 'bg-rose-500/15 text-rose-600' };
		return { txt: `Vence ${dataCurta(l.vencimento)}`, cls: 'bg-zinc-500/15 text-zinc-500' };
	}

	/** Diferença real x previsto (só para recorrentes com valor real informado). */
	function desvio(l: Lancamento) {
		if (!l.recorrencia_id || l.valor_real == null || !l.valor_previsto) return null;
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

	function abrir(l: Lancamento | null) {
		atual = l;
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
{:else if !itens.length}
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
								</p>
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
{/if}

<button class="fab" onclick={() => abrir(null)} aria-label="Novo lançamento avulso">+</button>

<Sheet bind:open={aberto} title={atual ? (atual.recorrencia_id ? 'Lançamento recorrente' : 'Editar lançamento') : 'Lançamento avulso'}>
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
