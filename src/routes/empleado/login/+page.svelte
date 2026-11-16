<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  onMount(() => { void goto('/admin/login', { replaceState: true }); });
</script>
<p role="status" class="muted">Abriendo inicio de sesión…</p>
