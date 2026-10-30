import { resolve } from '$app/paths';
import { app, carregarResidencia } from '#lib/app.svelte.ts';
import { sb } from '#lib/supabase.ts';
import { redirect } from '@sveltejs/kit';
import type { LayoutLoad } from './$types';

export const ssr = false;

const livres = ['/login', '/onboarding'];

export const load: LayoutLoad = async ({ route }) => {
	const user = (await sb.auth.getSession()).data.session?.user;
	if (!user) {
		if (route.id !== '/login') redirect(307, resolve('/login'));
		return;
	}
	if (app.user?.id !== user.id) await carregarResidencia(user);
	if (!app.res && route.id !== '/onboarding') redirect(307, resolve('/onboarding'));
	if (app.res && livres.includes(route.id ?? '')) redirect(307, resolve('/'));
};
