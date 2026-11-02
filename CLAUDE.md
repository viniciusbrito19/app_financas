# CLAUDE.md

App de finanças da residência (PWA mobile-first). SvelteKit 3 + Svelte 5 (runes) como SPA estática, Tailwind v4, Supabase (Postgres, Auth, RLS). Deploy no GitHub Pages via `.github/workflows/deploy.yml`.

## Comandos
- `npm run dev` — dev server (requer `.env`, ver `.env.example`)
- `npm run check` — svelte-check (tipos)
- `npm test` — vitest (parsers e prévia de importação)
- `npm run build` — gera `build/` (com `BASE_PATH=/app_financas` no CI)
- `npx supabase link --project-ref <ref>` e depois `npx supabase db push` — aplica `supabase/migrations`

## Arquitetura
- SvelteKit 3: config fica em `vite.config.ts` (não existe `svelte.config.js`); `$app/environment` virou `$app/env`; `$lib` virou `#lib` (campo `imports` do package.json; importe `.ts` com extensão, ex. `#lib/format.ts`); variáveis de ambiente declaradas em `src/env.ts` e lidas de `$app/env/public`; links com `resolve()` de `$app/paths`.
- `src/routes/+layout.ts`: `ssr = false`, guarda de rota (login → onboarding → app) e carrega o estado global `app` (`src/lib/app.svelte.ts`).
- Multi-usuário por **residência**: toda tabela tem `residencia_id` e policy `sou_membro(residencia_id)`. Criar/entrar só via RPC (`criar_residencia`, `entrar_residencia`).
- **Recorrências → lançamentos**: `gerar_mes(res, competencia)` é idempotente e chamada ao abrir o mês. Variável: previsto = média dos últimos `janela_media` valores reais. Editar/excluir recorrência apaga lançamentos futuros intocados (trigger `limpar_futuros`), regerados no próximo `gerar_mes`.
- **Importação (etapa 2)**: parsers rodam no navegador em `src/lib/importacao/` (contas correntes BB e Caixa em OFX — a Caixa grava valores como "-12.856.13", ver `valorOFX`; fatura do cartão Caixa em PDF via pdf.js carregado sob demanda). `previa.ts` monta os itens (normalização, meio, natureza, regra, hash de deduplicação `unique(conta_id, hash)`), sugere conciliação e projeta parcelas. Depois de gravar, a RPC `conciliar_importacao` neutraliza transferências entre contas, aplica a fatura do cartão (lançamento da fatura no mês do vencimento; as compras contam no mês anterior: fatura paga em novembro = gastos de outubro), liga o pagamento de fatura e baixa os lançamentos. `desfazer_importacao` reverte.
- Recorrência com `acumula` ("paga em várias vezes no mês", ex.: faxina em saques): várias transações ligadas ao mesmo lançamento; `recalcular_lancamento` só marca pago quando a soma atinge o previsto (antes disso o Mês mostra "Parcial").
- Fatura com vários cartões (titular/adicionais): o PDF é lido em duas colunas (`agruparColunas`), cada item guarda `transacoes.cartao` (final) e a soma por cartão é conferida com o "Total final (cartão XXXX)". `cartoes` associa final → membro; `v_gastos_categoria.membro_id` permite filtrar a Análise por pessoa.
- Fatura do cartão = recorrência variável ligada em `contas.recorrencia_id`. Na análise (`v_gastos_categoria`) ela é substituída pelos itens da fatura, para não contar em dobro. A análise conta sempre pela transação (e pela categoria dela) quando existe; o lançamento só entra quando pago à mão, sem transação de conta corrente ligada.
- Natureza `ignorada` ("Não contar"): a transação fica gravada (deduplicação), mas fora de totais, análise, fila e pareamento de transferências. Qualquer transação gravada pode ser reclassificada com o componente `Reclassificar` (Mês, Análise, fila); para conta corrente ele também troca a conciliação via RPC `vincular_transacao` (reabre o lançamento anterior com `recalcular_lancamento`).
- Regras (`regras`): o padrão mais longo contido em `descricao_norm` define categoria/natureza/recorrência. São criadas pelo usuário ao classificar (`lembrarRegra`).
- Amostras reais de extratos/faturas ficam em `amostras/` (fora do git); testes em `src/lib/importacao/*.test.ts`.
- Datas como string `YYYY-MM-DD`; competência sempre dia 01. Helpers em `src/lib/format.ts`.

## Convenções
- Código e UI em português; tabs; aspas simples.
- Mínimo de código: estilos utilitários + classes `.card .input .btn .btn-primary .label .chip .fab` em `src/app.css`; formulários em `Sheet` (bottom sheet).
- Inputs com fonte ≥16px (evita zoom no iOS) e `inputmode="decimal"` para valores.

## Roadmap
1. ✅ Recorrências e controle mensal
2. ✅ Importação (OFX BB/Caixa, fatura PDF Caixa), classificação por regras, conciliação e análise
3. Investimentos, patrimônio e cenários
