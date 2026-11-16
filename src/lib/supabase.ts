import { env } from '$env/dynamic/public';
import { createClient } from '@supabase/supabase-js';

const url = env.PUBLIC_SUPABASE_URL;
const key = env.PUBLIC_SUPABASE_PUBLISHABLE_KEY;

export const supabase = url && key ? createClient(url, key) : null;

export function requireSupabase() {
  if (!supabase) throw new Error('Configura PUBLIC_SUPABASE_URL y PUBLIC_SUPABASE_PUBLISHABLE_KEY.');
  return supabase;
}

export async function customerAccountId(): Promise<string | null> {
  const db = requireSupabase();
  const session = await db.auth.getSession();
  if (session.error) throw session.error;
  if (!session.data.session) return null;
  const identity = await db.auth.getUser();
  if (identity.error) throw identity.error;
  if (!identity.data.user) return null;
  const access = await db.from('account_access').select('account_id').eq('user_id', identity.data.user.id).order('created_at', { ascending: false }).limit(1);
  if (access.error) throw access.error;
  const accountId = access.data?.[0]?.account_id;
  if (!accountId) return null;
  const summary = await db.rpc('account_summary', { p_account: accountId });
  if (summary.error) {
    if (/not authorized|permission denied/i.test(summary.error.message)) return null;
    throw summary.error;
  }
  return accountId;
}

export async function signInStaff(email: string, password: string): Promise<'admin' | 'employee'> {
  const db = requireSupabase();
  const auth = await db.auth.signInWithPassword({ email, password });
  if (auth.error) throw auth.error;
  const identity = await db.auth.getUser();
  if (identity.error) throw identity.error;
  const staff = await db.from('staff').select('role,active').eq('user_id', identity.data.user?.id ?? '').maybeSingle();
  if (staff.error) throw staff.error;
  if (!staff.data?.active || (staff.data.role !== 'admin' && staff.data.role !== 'employee')) {
    await db.auth.signOut();
    throw new Error('staff access denied');
  }
  return staff.data.role;
}
