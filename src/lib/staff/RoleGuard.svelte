<script lang="ts">
  import type { Snippet } from 'svelte';
  import { onMount } from 'svelte';
  import { afterNavigate, goto } from '$app/navigation';
  import { page } from '$app/state';
  import { requireSupabase } from '$lib/supabase';
  import { friendlyError } from '$lib/errors';
  import Notice from '$lib/ui/Notice.svelte';

  let { role, loginPath, children }: { role: 'admin' | 'employee'; loginPath: string; children: Snippet } = $props();
  let allowed = $state(false);
  let error = $state('');
  let checkId = 0;

  async function check() {
    const current = ++checkId;
    if (page.url.pathname === loginPath) { allowed=true;error='';return; }
    allowed=false;
    try {
      const db=requireSupabase();
      const identity=await db.auth.getUser();
      if (identity.error || !identity.data.user) { await goto(loginPath);return; }
      const result=await db.from('staff').select('role,active').eq('user_id',identity.data.user.id).single();
      if (result.error || result.data?.role!==role || !result.data.active) { await goto(loginPath);return; }
      if (current===checkId) {allowed=true;error='';}
    } catch (cause) {if(current===checkId) error=friendlyError(cause);}
  }
  afterNavigate(()=>{void check();});
  onMount(()=>{
    const db=requireSupabase();
    const listener=db.auth.onAuthStateChange((event)=>{
      if (event==='SIGNED_OUT' || event==='SIGNED_IN' || event==='TOKEN_REFRESHED' || event==='USER_UPDATED') void check();
    });
    const visibility=()=>{if(!document.hidden) void check();};
    document.addEventListener('visibilitychange',visibility);
    return ()=>{listener.data.subscription.unsubscribe();document.removeEventListener('visibilitychange',visibility);};
  });
</script>

{#if page.url.pathname === loginPath}{@render children()}
{:else}
  {#if error}<Notice message={error} /><button class="secondary" onclick={()=>void check()}>Reintentar</button>{/if}
  {#if allowed}{@render children()}{:else if !error}<p class="muted" role="status">Verificando acceso…</p>{/if}
{/if}
