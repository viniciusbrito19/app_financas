import { defineEnvVars } from '@sveltejs/kit/env';

// Inlinadas no build (o app é estático); no CI vêm dos secrets do GitHub
export const variables = defineEnvVars({
	PUBLIC_SUPABASE_URL: { public: true, static: true },
	PUBLIC_SUPABASE_ANON_KEY: { public: true, static: true }
});
