<script lang="ts">
  import { goto } from '$app/navigation';
  import { requireSupabase } from '$lib/supabase';
  let code = $state('');
  let error = $state('');
  let busy = $state(false);

  async function link() {
    if (busy) return;
    busy = true;
    error = '';
    try {
      const db = requireSupabase();
      const session = await db.auth.getSession();
      if (session.error) throw session.error;
      if (!session.data.session) {
        const anonymous = await db.auth.signInAnonymously();
        if (anonymous.error) throw anonymous.error;
      }
      const result = await db.rpc('link_account', { p_code: code.trim().toUpperCase() });
      if (result.error) throw result.error;
      if (!result.data) throw new Error('invalid code');
      await goto('/mi-cuenta');
    } catch (cause) {
      const message = cause instanceof Error ? cause.message : '';
      error = /failed to fetch|network|fetch failed/i.test(message)
        ? 'No pudimos conectar. Intenta nuevamente.'
        : 'El código es inválido, ya se usó o venció. Solicita uno nuevo al personal.';
    } finally { busy = false; }
  }
</script>

<div class="link-shell">
  <h1>Vincula tu checa</h1>
  <p>Ingresa el código que te dio el personal de la tienda.</p>
  <form onsubmit={(event) => { event.preventDefault(); void link(); }}>
    <label>Código de 18 caracteres<input bind:value={code} maxlength="18" minlength="18" required autocomplete="one-time-code" autocapitalize="characters" spellcheck="false" placeholder="Código de vinculación" /></label>
    {#if error}<p class="notice" role="alert">{error}</p>{/if}
    <button class="full" disabled={busy || code.trim().length !== 18}>{busy ? 'Validando…' : 'Continuar'}</button>
  </form>
  <a class="link-back" href="/">Volver al inicio</a>
</div>
