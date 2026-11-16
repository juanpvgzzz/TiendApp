<script lang="ts">
  import { goto } from '$app/navigation';
  import { customerAccountId, requireSupabase } from '$lib/supabase';
  import BrandCurves from '$lib/ui/BrandCurves.svelte';
  let busy = $state(false);
  let error = $state('');

  async function access() {
    if (busy) return;
    busy = true;
    error = '';
    try {
      const db = requireSupabase();
      const accountId = await customerAccountId();
      if (accountId) { await goto('/mi-cuenta'); return; }
      const session = await db.auth.getSession();
      if (session.error) throw session.error;
      if (!session.data.session) {
        const anonymous = await db.auth.signInAnonymously();
        if (anonymous.error) throw anonymous.error;
      }
      await goto('/vincular');
    } catch {
      error = 'No pudimos conectar. Intenta nuevamente.';
    } finally { busy = false; }
  }
</script>

<div class="welcome-shell">
  <section class="welcome-hero">
    <div class="welcome-mobile-curves"><BrandCurves /></div>
    <div class="welcome-copy">
      <h1>Tu checa, siempre al día.</h1>
      <p>Consulta tus consumos, pide productos y solicita pagar desde tu celular.</p>
      {#if error}<p class="notice" role="alert">{error}</p>{/if}
      <button class="welcome-primary" disabled={busy} onclick={()=>void access()}>{busy ? 'Comprobando acceso…' : 'Acceder a mi checa'} <span aria-hidden="true">→</span></button>
      <div class="welcome-access"><span>Personal de la tienda</span><a href="/admin/login">Iniciar sesión</a></div>
    </div>
    <div class="welcome-display" aria-hidden="true"><BrandCurves /><div class="welcome-display-card">TiendApp · Tu checa digital</div></div>
  </section>
</div>
