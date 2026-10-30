# CLAUDE.md

App de finanças da residência (PWA mobile-first). SvelteKit 3 + Svelte 5 (runes) como SPA estática, Tailwind v4, Supabase (Postgres, Auth, RLS). Deploy no GitHub Pages via `.github/workflows/deploy.yml`.

## Comandos
- `npm run dev` — dev server (requer `.env`, ver `.env.example`)
- `npm run check` — svelte-check (tipos)
- `npm run build` — gera `build/` (com `BASE_PATH=/app_financas` no CI)
- `npx supabase link --project-ref <ref>` e depois `npx supabase db push` — aplica `supabase/migrations`

## Arquitetura
- SvelteKit 3: config fica em `vite.config.ts` (não existe `svelte.config.js`); `$app/environment` virou `$app/env`; `$lib` virou `#lib` (campo `imports` do package.json; importe `.ts` com extensão, ex. `#lib/format.ts`); variáveis de ambiente declaradas em `src/env.ts` e lidas de `$app/env/public`; links com `resolve()` de `$app/paths`.
- `src/routes/+layout.ts`: `ssr = false`, guarda de rota (login → onboarding → app) e carrega o estado global `app` (`src/lib/app.svelte.ts`).
- Multi-usuário por **residência**: toda tabela tem `residencia_id` e policy `sou_membro(residencia_id)`. Criar/entrar só via RPC (`criar_residencia`, `entrar_residencia`).
- **Recorrências → lançamentos**: `gerar_mes(res, competencia)` é idempotente e chamada ao abrir o mês. Variável: previsto = média dos últimos `janela_media` valores reais. Editar/excluir recorrência apaga lançamentos futuros intocados (trigger `limpar_futuros`), regerados no próximo `gerar_mes`.
- Datas como string `YYYY-MM-DD`; competência sempre dia 01. Helpers em `src/lib/format.ts`.

## Convenções
- Código e UI em português; tabs; aspas simples.
- Mínimo de código: estilos utilitários + classes `.card .input .btn .btn-primary .label .chip .fab` em `src/app.css`; formulários em `Sheet` (bottom sheet).
- Inputs com fonte ≥16px (evita zoom no iOS) e `inputmode="decimal"` para valores.

## Roadmap
1. ✅ Recorrências e controle mensal
2. Importar faturas de cartão e classificar gastos por perfil (fatura = recorrência variável "Cartão de crédito")
3. Investimentos, patrimônio e cenários
