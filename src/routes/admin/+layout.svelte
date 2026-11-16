<script lang="ts">
  import RoleGuard from '$lib/staff/RoleGuard.svelte';
  let {children}=$props();
</script>
<RoleGuard role="admin" loginPath="/admin/login">{@render children()}</RoleGuard>
