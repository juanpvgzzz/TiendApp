<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { signInStaff } from '$lib/supabase';
  import { staffLoginError } from '$lib/errors';
  import BrandCurves from '$lib/ui/BrandCurves.svelte';
  let email = $state('');
  let password = $state('');
  let showPassword = $state(false);
  let error = $state('');
  let busy = $state(false);
  let ready = $state(false);
  onMount(() => { ready = true; });

  async function login() {
    if (busy) return;
    busy = true;
    error = '';
    try {
      const role = await signInStaff(email, password);
      await goto(role === 'admin' ? '/admin' : '/empleado');
    } catch (cause) { error = staffLoginError(cause); }
    finally { busy = false; }
  }
</script>

<div class="staff-login">
  <div class="staff-login-intro"><BrandCurves /><div><p class="eyebrow">TiendApp</p><h2>Gestiona las checas de tu tienda.</h2></div></div>
  <div class="staff-login-form"><h1>Iniciar sesión</h1>
    {#if ready}<form onsubmit={(event) => { event.preventDefault(); void login(); }}>
      <label>Correo electrónico<input type="email" bind:value={email} required autocomplete="email" /></label>
      <div><label>Contraseña<input type={showPassword ? 'text' : 'password'} bind:value={password} required autocomplete="current-password" /></label><button class="ghost password-toggle" type="button" onclick={() => showPassword = !showPassword}>{showPassword ? 'Ocultar contraseña' : 'Mostrar contraseña'}</button></div>
      {#if error}<p class="notice" role="alert">{error}</p>{/if}
      <button class="full login-submit" disabled={busy}>{#if busy}<span class="spinner" aria-hidden="true"></span>{/if}Ingresar</button>
    </form>{/if}
  </div>
</div>
