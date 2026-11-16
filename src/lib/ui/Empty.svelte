<script lang="ts">
  let { title, detail = '' }: { title: string; detail?: string } = $props();
</script>
<div class="empty"><strong>{title}</strong>{#if detail}<p>{detail}</p>{/if}</div>
