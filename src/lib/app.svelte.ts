import type { User } from '@supabase/supabase-js';
import { mesAtual } from './format.ts';
import { ok, sb } from './supabase.ts';
import type { Categoria, Membro, Residencia } from './types.ts';

/** Estado global da sessão: usuário, residência ativa e cadastros auxiliares. */
export const app = $state({
	user: null as User | null,
	res: null as Residencia | null,
	membros: [] as Membro[],
	cats: [] as Categoria[],
	mes: mesAtual()
});

export async function carregarResidencia(user: User) {
	app.user = user;
	const m = ok(
		await sb.from('membros').select('residencias(*)').eq('user_id', user.id).limit(1).maybeSingle()
	) as { residencias: Residencia } | null;
	app.res = m?.residencias ?? null;
	if (app.res) await carregarCadastros();
}

export async function carregarCadastros() {
	const id = app.res!.id;
	const [membros, cats] = await Promise.all([
		sb.from('membros').select('*').eq('residencia_id', id).order('created_at'),
		sb.from('categorias').select('*').eq('residencia_id', id).order('nome')
	]);
	app.membros = ok(membros) as Membro[];
	app.cats = ok(cats) as Categoria[];
}

export function limpar() {
	Object.assign(app, { user: null, res: null, membros: [], cats: [] });
}

export const cat = (id: string | null) => app.cats.find((c) => c.id === id);
export const membro = (id: string | null) => app.membros.find((m) => m.id === id);
