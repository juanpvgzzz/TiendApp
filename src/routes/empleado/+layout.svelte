<script lang="ts">
  import RoleGuard from '$lib/staff/RoleGuard.svelte';
  let {children}=$props();
</script>
<RoleGuard role="employee" loginPath="/empleado/login">{@render children()}</RoleGuard>
