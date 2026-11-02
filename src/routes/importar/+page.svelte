<script lang="ts">
	import { app, carregarCadastros, cat, conta as contaDe, contaNoTotal, contarPendentes, MEIOS, NATUREZAS, rotuloCartao } from '#lib/app.svelte.ts';
	import Classificar from '#lib/components/Classificar.svelte';
	import Icone from '#lib/components/Icone.svelte';
	import MonthPicker from '#lib/components/MonthPicker.svelte';
	import Reclassificar from '#lib/components/Reclassificar.svelte';
	import Sheet from '#lib/components/Sheet.svelte';
	import { naturezaDe } from '#lib/importacao/normalizar.ts';
	import { addMes, brl, dataCurta, mesLabel } from '#lib/format.ts';
	import { lerArquivo, senhaNecessaria, type Leitura } from '#lib/importacao/ler.ts';
	import { aplicarRegra, montarItens, paraLinha, projetarParcelas, sugerirConciliacao, type Item } from '#lib/importacao/previa.ts';
	import { lembrarRegra } from '#lib/importacao/regras.ts';
	import { ok, sb } from '#lib/supabase.ts';
	import type { Importacao, Lancamento, Transacao } from '#lib/types.ts';

	let contaId = $state(app.contas[0]?.id ?? '');
	const conta = $derived(contaDe(contaId));
	let arquivo = $state<File | null>(null);
	let leitura = $state<Leitura | null>(null);
	let itens = $state<Item[]>([]);
	let lancs = $state<Lancamento[]>([]);
	let erro = $state('');
	let ocupado = $state(false);
	let aviso = $state('');

	const competenciaFatura = $derived(leitura?.fatura ? leitura.fatura.vencimento.slice(0, 8) + '01' : undefined);
	const novos = $derived(itens.filter((i) => !i.duplicada));

	// recorrências pagas em várias vezes (ex.: faxina em saques) aceitam vários itens
	const acumula = (id: string) => !!app.recs.find((r) => r.id === id)?.acumula;
	const sugerir = () => conta && sugerirConciliacao(itens, lancs, conta, acumula);

	async function escolher(e: Event) {
		const input = e.currentTarget as HTMLInputElement;
		arquivo = input.files?.[0] ?? null;
		input.value = '';
		if (arquivo && conta) await ler();
	}

	async function ler(senha?: string) {
		erro = '';
		ocupado = true;
		try {
			leitura = await lerArquivo(arquivo!, conta!, senha);
			// compras do cartão contam no mês anterior ao vencimento da fatura
			itens = montarItens(leitura.brutas, conta!, app.regras, competenciaFatura && addMes(competenciaFatura, -1));
			await marcarDuplicadas();
			await carregarLancamentos();
		} catch (e) {
			if (senhaNecessaria(e)) {
				const s = prompt(senha ? 'Senha incorreta. Tente novamente:' : 'PDF protegido. Informe a senha:');
				if (s) return ler(s);
			}
			erro = (e as Error).message;
			leitura = null;
		} finally {
			ocupado = false;
		}
	}

	async function marcarDuplicadas() {
		if (!itens.length) return;
		const datas = itens.map((i) => i.data).sort();
		const existentes = ok(
			await sb.from('transacoes').select('hash').eq('conta_id', contaId).gte('data', datas[0]).lte('data', datas.at(-1)!)
		) as { hash: string }[];
		const set = new Set(existentes.map((x) => x.hash));
		for (const i of itens) i.duplicada = set.has(i.hash);
	}

	async function carregarLancamentos() {
		const comps = [...new Set(novos.map((i) => i.competencia))];
		await Promise.all(comps.map((c) => sb.rpc('gerar_mes', { p_res: app.res!.id, p_comp: c })));
		lancs = comps.length
			? (ok(await sb.from('lancamentos').select('*').eq('residencia_id', app.res!.id).in('competencia', comps).order('vencimento')) as Lancamento[])
			: [];
		sugerir();
	}

	async function confirmar() {
		ocupado = true;
		try {
			const imp = ok(
				await sb
					.from('importacoes')
					.insert({
						residencia_id: app.res!.id,
						conta_id: contaId,
						arquivo: arquivo!.name,
						formato: leitura!.formato,
						competencia: competenciaFatura ?? null,
						total: leitura!.fatura?.total ?? null,
						total_anterior: leitura!.fatura?.anterior ?? null,
						qtd: novos.length
					})
					.select()
					.single()
			) as Importacao;
			const linhas = [...novos, ...projetarParcelas(novos)].map((i) => ({ ...paraLinha(i), residencia_id: app.res!.id, importacao_id: imp.id }));
			ok(await sb.from('transacoes').upsert(linhas, { onConflict: 'conta_id,hash', ignoreDuplicates: true }));
			ok(await sb.rpc('conciliar_importacao', { p_imp: imp.id }));
			// registra finais de cartão novos (titular/adicionais) para associar a pessoas em Ajustes
			const finais = [...new Set(novos.map((i) => i.cartao).filter((f): f is string => !!f))];
			if (finais.length) {
				ok(await sb.from('cartoes').upsert(finais.map((final) => ({ residencia_id: app.res!.id, conta_id: contaId, final })), { onConflict: 'conta_id,final', ignoreDuplicates: true }));
				await carregarCadastros();
			}
			aviso = `${novos.length} transações importadas.`;
			cancelar();
			await Promise.all([carregarHistorico(), carregarFila(), carregarFora(), contarPendentes()]);
		} catch (e) {
			erro = (e as Error).message;
		} finally {
			ocupado = false;
		}
	}

	function cancelar() {
		leitura = null;
		itens = [];
		arquivo = null;
	}

	// --- edição de um item da prévia ----------------------------------------
	let aberto = $state(false);
	let alvo = $state<Item | null>(null);
	/** transação gravada da fila "a classificar" */
	let filaAlvo = $state<Transacao | null>(null);

	/** Liga/desliga "não contar" (ex.: resgate automático "BB Rende Fácil"). O item é gravado, mas fica fora dos totais. */
	function alternarContar(it: Item) {
		const r = it.regra?.natureza;
		it.natureza =
			it.natureza !== 'ignorada' ? 'ignorada' : r && r !== 'ignorada' ? r : cartao ? 'gasto' : naturezaDe(it.descricao_norm, it.valor);
		sugerir();
	}

	async function salvarClassificacao(v: Pick<Item, 'categoria_id' | 'natureza' | 'lancamento_id'>, padrao: string | null) {
		const t = alvo!;
		Object.assign(t, v, { sugerido: false, categoriaHerdada: false });
		const recorrencia_id = lancs.find((l) => l.id === v.lancamento_id)?.recorrencia_id;
		if (padrao) {
			await lembrarRegra(padrao, { ...v, recorrencia_id });
			// reaplica nas linhas da prévia ainda sem categoria
			for (const i of itens) if (!i.categoria_id && i !== t) aplicarRegra(i, app.regras);
			sugerir();
		}
		aberto = false;
	}

	// --- fila "a classificar" e histórico ------------------------------------
	let fila = $state<Transacao[]>([]);
	let historico = $state<Importacao[]>([]);
	/** últimas descartadas, para desfazer */
	let descartadas = $state<Transacao[]>([]);

	/** Descarta da fila: vira "Não contar" (continua gravada para não reaparecer em reimportações). */
	async function descartar(t: Transacao) {
		ok(await sb.from('transacoes').update({ natureza: 'ignorada' }).eq('id', t.id));
		fila = fila.filter((x) => x.id !== t.id);
		descartadas = [...descartadas, t];
		await Promise.all([contarPendentes(), carregarFora()]);
	}

	async function desfazerDescarte() {
		const ids = descartadas.map((t) => t.id);
		ok(await sb.from('transacoes').update({ natureza: 'gasto' }).in('id', ids));
		descartadas = [];
		await Promise.all([carregarFila(), carregarFora(), contarPendentes()]);
	}

	// --- o que não conta nos totais (por mês) ---------------------------------
	let foraDosTotais = $state<Transacao[]>([]);
	let grupoForaAberto = $state<string | null>(null);

	async function carregarFora(mes = app.mes) {
		const ts = ok(
			await sb
				.from('transacoes')
				.select('*')
				.eq('residencia_id', app.res!.id)
				.eq('competencia', mes)
				.eq('projetada', false)
				.in('natureza', ['ignorada', 'transferencia', 'pagamento_fatura'])
				.order('data')
		) as Transacao[];
		if (mes === app.mes) foraDosTotais = ts;
	}
	$effect(() => {
		carregarFora(app.mes);
	});

	const gruposFora = $derived(
		(
			[
				['ignorada', '⊘ Descartadas'],
				['transferencia', '⇄ Transferências e investimentos'],
				['pagamento_fatura', '💳 Pagamentos de fatura']
			] as const
		)
			.map(([natureza, rotulo]) => ({ natureza, rotulo, ts: foraDosTotais.filter((t) => t.natureza === natureza) }))
			.filter((g) => g.ts.length)
	);

	/** Volta a contar: gasto ou receita pelo sinal do valor. */
	async function voltarAContar(t: Transacao) {
		ok(await sb.from('transacoes').update({ natureza: t.valor < 0 ? 'gasto' : 'receita' }).eq('id', t.id));
		await Promise.all([carregarFora(), carregarFila(), contarPendentes()]);
	}

	async function carregarFila() {
		fila = ok(
			await sb
				.from('transacoes')
				.select('*')
				.eq('residencia_id', app.res!.id)
				.eq('natureza', 'gasto')
				.eq('projetada', false)
				.is('categoria_id', null)
				.order('data', { ascending: false })
				.limit(100)
		) as Transacao[];
	}

	async function carregarHistorico() {
		historico = ok(
			await sb.from('importacoes').select('*').eq('residencia_id', app.res!.id).order('created_at', { ascending: false }).limit(20)
		) as Importacao[];
	}

	async function desfazer(i: Importacao) {
		if (!confirm(`Desfazer a importação de "${i.arquivo}"? As transações serão removidas e os lançamentos reabertos.`)) return;
		ok(await sb.rpc('desfazer_importacao', { p_imp: i.id }));
		await Promise.all([carregarHistorico(), carregarFila(), carregarFora(), contarPendentes()]);
	}

	carregarFila();
	carregarHistorico();

	const lancDe = (id: string | null) => lancs.find((l) => l.id === id);
	// iOS esmaece .ofx quando há filtro por extensão: conta corrente aceita qualquer arquivo (validado em lerArquivo)
	const cartao = $derived(conta?.tipo === 'cartao');
</script>

{#snippet linha(t: Item | Transacao, onclick: () => void)}
	{@const fora = ('duplicada' in t && t.duplicada) || !contaNoTotal(t.natureza)}
	<li class="flex items-center">
		<button class="flex min-w-0 flex-1 items-center gap-3 py-3 pl-3 text-left {fora ? 'opacity-45' : ''}" {onclick}>
			<Icone c={cat(t.categoria_id)} />
			<div class="min-w-0 flex-1">
				<p class="truncate text-sm font-medium">{t.descricao}</p>
				{#if t.nota}<p class="truncate text-xs text-zinc-500 italic">📝 {t.nota}</p>{/if}
				<p class="flex flex-wrap items-center gap-1 text-xs text-zinc-500">
					<span>{dataCurta(t.data)}</span>
					<span class="chip bg-zinc-500/15">{MEIOS[t.meio]}</span>
					{#if t.parcela}<span class="chip bg-zinc-500/15">{t.parcela}/{t.parcelas}</span>{/if}
					{#if t.cartao}<span class="chip bg-zinc-500/15">•• {t.cartao}</span>{/if}
					{#if 'duplicada' in t && t.duplicada}
						<span>já importada</span>
					{:else if t.natureza !== 'gasto' && t.natureza !== 'receita'}
						<span class="chip bg-sky-500/15 text-sky-600">{NATUREZAS[t.natureza]}</span>
					{:else if !t.categoria_id}
						<span class="chip bg-amber-500/15 text-amber-600">Sem categoria</span>
					{/if}
					{#if t.lancamento_id && lancDe(t.lancamento_id)}
						<span class="chip bg-brand/15 text-brand">🔗 {lancDe(t.lancamento_id)?.descricao}{'sugerido' in t && t.sugerido ? ' ?' : ''}</span>
					{/if}
				</p>
			</div>
			<p class="text-sm font-semibold tabular-nums {t.valor > 0 ? 'text-receita' : ''} {fora ? 'line-through' : ''}">{brl(t.valor)}</p>
		</button>
		{#if 'duplicada' in t && !t.duplicada}
			<button
				class="grid size-11 shrink-0 place-items-center text-lg {t.natureza === 'ignorada' ? 'text-zinc-400' : 'text-zinc-300 dark:text-zinc-600'}"
				onclick={() => alternarContar(t)}
				aria-label={t.natureza === 'ignorada' ? 'Voltar a contar' : 'Não contar'}
				title={t.natureza === 'ignorada' ? 'Voltar a contar' : 'Não contar'}>{t.natureza === 'ignorada' ? '↺' : '⊘'}</button
			>
		{:else if 'id' in t && t.natureza === 'ignorada'}
			<button
				class="grid size-11 shrink-0 place-items-center text-lg text-zinc-400"
				onclick={() => voltarAContar(t)}
				aria-label="Voltar a contar"
				title="Voltar a contar">↺</button
			>
		{:else if 'id' in t && contaNoTotal(t.natureza)}
			<button
				class="grid size-11 shrink-0 place-items-center text-lg text-zinc-300 dark:text-zinc-600"
				onclick={() => descartar(t)}
				aria-label="Descartar (não contar)"
				title="Descartar (não contar)">⊘</button
			>
		{:else}
			<span class="w-3"></span>
		{/if}
	</li>
{/snippet}

<h1 class="text-2xl font-bold">Importar</h1>

{#if !app.contas.length}
	<div class="card mt-4 text-sm text-zinc-500">Cadastre suas contas e cartões em <b>Ajustes</b> para importar extratos e faturas.</div>
{:else if !leitura}
	<section class="card mt-4 space-y-4">
		<div>
			<label class="label" for="conta">Conta ou cartão</label>
			<select id="conta" class="input" bind:value={contaId}>
				{#each app.contas as c (c.id)}<option value={c.id}>{c.nome}</option>{/each}
			</select>
		</div>
		<label class="btn btn-primary w-full {ocupado ? 'opacity-50' : ''}">
			{ocupado ? 'Lendo arquivo…' : cartao ? 'Escolher fatura (PDF)' : 'Escolher extrato (OFX)'}
			<input type="file" accept={cartao ? '.pdf,application/pdf' : undefined} class="hidden" onchange={escolher} disabled={ocupado} />
		</label>
		<p class="text-xs text-zinc-500">
			O arquivo é lido no próprio aparelho. Contas BB e Caixa: exporte o extrato em OFX. Cartão Caixa: PDF da fatura.
		</p>
		{#if erro}<p class="text-sm text-despesa">{erro}</p>{/if}
		{#if aviso}<p class="text-sm text-receita">{aviso}</p>{/if}
	</section>

	{#if descartadas.length}
		<div class="card mt-4 flex items-center justify-between py-3 text-sm">
			<span>{descartadas.length} {descartadas.length === 1 ? 'transação descartada' : 'transações descartadas'}</span>
			<button class="font-semibold text-brand" onclick={desfazerDescarte}>Desfazer</button>
		</div>
	{/if}

	{#if fila.length}
		<h2 class="mt-6 mb-2 px-1 text-sm font-semibold text-zinc-500">A classificar ({app.pendentes})</h2>
		<p class="mb-2 px-1 text-xs text-zinc-500">Toque para classificar; ⊘ descarta (não conta nos totais).</p>
		<ul class="card divide-y divide-zinc-100 p-0 dark:divide-zinc-800">
			{#each fila as t (t.id)}{@render linha(t, () => (filaAlvo = t))}{/each}
		</ul>
	{/if}

	<h2 class="mt-6 mb-2 px-1 text-sm font-semibold text-zinc-500">Não contam nos totais</h2>
	<div class="card space-y-3 p-3">
		<MonthPicker bind:value={app.mes} />
		{#if gruposFora.length}
			<p class="text-xs text-zinc-500">Toque para reclassificar; ↺ volta a contar uma descartada.</p>
			<ul class="divide-y divide-zinc-100 rounded-xl bg-zinc-50 dark:divide-zinc-800 dark:bg-zinc-950/40">
				{#each gruposFora as g (g.natureza)}
					<li>
						<button class="flex w-full items-center gap-2 px-3 py-2.5 text-left text-sm" onclick={() => (grupoForaAberto = grupoForaAberto === g.natureza ? null : g.natureza)}>
							<span class="flex-1 font-medium">{g.rotulo} <span class="text-xs font-normal text-zinc-500">({g.ts.length})</span></span>
							<span class="text-zinc-400">{grupoForaAberto === g.natureza ? '▴' : '▾'}</span>
						</button>
						{#if grupoForaAberto === g.natureza}
							<ul class="divide-y divide-zinc-100 dark:divide-zinc-800">
								{#each g.ts as t (t.id)}{@render linha(t, () => (filaAlvo = t))}{/each}
							</ul>
						{/if}
					</li>
				{/each}
			</ul>
		{:else}
			<p class="text-center text-sm text-zinc-500">Nada fora dos totais neste mês.</p>
		{/if}
	</div>

	{#if historico.length}
		<h2 class="mt-6 mb-2 px-1 text-sm font-semibold text-zinc-500">Importações recentes</h2>
		<ul class="card divide-y divide-zinc-100 p-0 dark:divide-zinc-800">
			{#each historico as i (i.id)}
				<li class="flex items-center gap-3 px-3 py-3">
					<div class="min-w-0 flex-1">
						<p class="truncate text-sm font-medium">{i.arquivo}</p>
						<p class="text-xs text-zinc-500">
							{contaDe(i.conta_id)?.nome} · {i.qtd} transações · {dataCurta(i.created_at.slice(0, 10))}
							{#if i.competencia}· fatura {mesLabel(i.competencia)}{/if}
						</p>
					</div>
					<button class="text-sm text-despesa" onclick={() => desfazer(i)}>Desfazer</button>
				</li>
			{/each}
		</ul>
	{/if}
{:else}
	{@const contam = novos.filter((i) => contaNoTotal(i.natureza))}
	{@const saidas = contam.filter((i) => i.valor < 0).reduce((s, i) => s + i.valor, 0)}
	{@const entradas = contam.filter((i) => i.valor > 0).reduce((s, i) => s + i.valor, 0)}
	<section class="card mt-4 space-y-1 text-sm">
		<p class="font-semibold">{arquivo?.name}</p>
		<p class="text-zinc-500">
			{novos.length} novas · {itens.length - novos.length} já importadas · {novos.length - contam.length} não contam (transferências, investimentos, ignoradas)
		</p>
		{#if leitura.fatura}
			{@const soma = -itens.reduce((s, i) => s + i.valor, 0)}
			<p>Fatura que vence em {dataCurta(leitura.fatura.vencimento)} · total <b>{brl(leitura.fatura.total)}</b></p>
			<p class="text-zinc-500">Gastos contam em <b>{mesLabel(addMes(competenciaFatura!, -1))}</b>; o pagamento, em {mesLabel(competenciaFatura!)}.</p>
			{#if Math.abs(soma - leitura.fatura.total) > 0.01}
				<p class="text-amber-600">Atenção: soma dos itens ({brl(soma)}) difere do total da fatura.</p>
			{/if}
			{#if Object.keys(leitura.fatura.cartoes ?? {}).length > 1}
				<ul class="mt-2 space-y-0.5 text-xs">
					{#each Object.entries(leitura.fatura.cartoes!) as [final, total] (final)}
						{@const lido = -itens.filter((i) => i.cartao === final).reduce((s, i) => s + i.valor, 0)}
						<li class="flex justify-between">
							<span>{rotuloCartao(contaId, final)}</span>
							<span class="tabular-nums">{brl(lido)}{Math.abs(lido - total) > 0.01 ? ` ⚠ PDF: ${brl(total)}` : ''}</span>
						</li>
					{/each}
				</ul>
			{/if}
		{:else}
			<p>Saídas <b>{brl(saidas)}</b> · Entradas <b class="text-receita">{brl(entradas)}</b></p>
		{/if}
	</section>

	<p class="mt-4 mb-2 px-1 text-xs text-zinc-500">
		Toque num item para ajustar categoria, natureza ou conciliação. Use ⊘ para não contar um item (ele fica riscado); para lembrar nas próximas, escolha a natureza "Não contar" e marque "Lembrar".
	</p>
	<ul class="card divide-y divide-zinc-100 p-0 dark:divide-zinc-800">
		{#each itens as t (t.hash)}{@render linha(t, () => ((alvo = t), (aberto = true)))}{/each}
	</ul>

	{#if erro}<p class="mt-3 text-sm text-despesa">{erro}</p>{/if}
	<div class="sticky bottom-[calc(4.5rem+env(safe-area-inset-bottom))] mt-4 grid grid-cols-[1fr_2fr] gap-3">
		<button class="btn btn-ghost" onclick={cancelar} disabled={ocupado}>Cancelar</button>
		<button class="btn btn-primary shadow-lg" onclick={confirmar} disabled={ocupado || !novos.length}>
			{ocupado ? 'Importando…' : `Importar ${novos.length}`}
		</button>
	</div>
{/if}

<Sheet bind:open={aberto} title="Classificar">
	{#if alvo}
		<Classificar t={alvo} lancs={cartao ? undefined : lancs.filter((l) => l.competencia === alvo?.competencia)} onsalvar={salvarClassificacao} />
	{/if}
</Sheet>

<Reclassificar
	bind:t={filaAlvo}
	onfeito={() => {
		carregarFila();
		carregarFora();
	}}
/>
