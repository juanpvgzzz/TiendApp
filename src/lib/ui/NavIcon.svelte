<script lang="ts">
  let { name }: { name: 'home'|'orders'|'account'|'history'|'manage' } = $props();
</script>

<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
  {#if name==='home'}<path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1z"/><path d="M9 21v-7h6v7"/>
  {:else if name==='orders'}<path d="M5 4h14v16H5z"/><path d="M8 8h8M8 12h8M8 16h5"/>
  {:else if name==='account'}<path d="M4 4h16v16H4z"/><path d="M8 9h8M8 13h8M8 17h5"/><path d="M17 4v16"/>
  {:else if name==='history'}<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>
  {:else}<path d="M4 7h16M4 12h16M4 17h16"/><circle cx="9" cy="7" r="2" fill="currentColor" stroke="none"/><circle cx="15" cy="12" r="2" fill="currentColor" stroke="none"/><circle cx="10" cy="17" r="2" fill="currentColor" stroke="none"/>{/if}
</svg>
