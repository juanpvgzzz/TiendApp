<script lang="ts">
  import { statusLabel } from '$lib/format';
  let { status }: { status: string } = $props();
</script>
<span class="badge" data-status={status}>{statusLabel(status)}</span>
