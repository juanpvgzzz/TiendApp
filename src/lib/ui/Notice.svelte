<script lang="ts">
  let { message, kind = 'error' }: { message: string; kind?: 'error' | 'success' | 'info' } = $props();
</script>
{#if message}<p class="notice" data-kind={kind} role={kind === 'error' ? 'alert' : 'status'}>{message}</p>{/if}
