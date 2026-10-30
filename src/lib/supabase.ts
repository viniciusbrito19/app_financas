import { createClient } from '@supabase/supabase-js';
import { PUBLIC_SUPABASE_ANON_KEY, PUBLIC_SUPABASE_URL } from '$app/env/public';

export const sb = createClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY);

/** Lança o erro do Supabase ou devolve os dados. */
export function ok<T>({ data, error }: { data: T; error: unknown }): T {
	if (error) throw error;
	return data;
}
