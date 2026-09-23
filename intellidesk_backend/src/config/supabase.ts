import { createClient, SupabaseClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.SUPABASE_URL || 'https://placeholder-domain.supabase.co';
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY || 'mock-service-role-key';

if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
  console.warn('Supabase credentials are not set. Ensure SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are in your environment.');
}

export const supabase: SupabaseClient = createClient(supabaseUrl, supabaseServiceKey, {
  auth: { persistSession: false },
  global: {
    fetch: (url, options) => {
      // Pass signal with timeout to prevent undici connect hangs
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 15000); // 15s timeout
      return fetch(url, {
        ...options,
        signal: options?.signal || controller.signal,
      }).finally(() => clearTimeout(timeoutId));
    },
  },
});

export const supabaseAdmin = supabase;

