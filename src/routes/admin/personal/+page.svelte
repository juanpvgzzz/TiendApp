<script lang="ts">
  import { onMount } from 'svelte';
  import { requireSupabase } from '$lib/supabase';
  import { friendlyError } from '$lib/errors';
  import Notice from '$lib/ui/Notice.svelte';
  import Empty from '$lib/ui/Empty.svelte';
  type Staff={user_id:string;display_name:string|null;role:'admin'|'employee';active:boolean};
  let staff=$state<Staff[]>([]);
  let userId=$state('');
  let name=$state('');
  let busy=$state(false);
  let loading=$state(true);
  let error=$state('');
  let success=$state('');
  async function load(){const result=await requireSupabase().from('staff').select('user_id,display_name,role,active').order('created_at',{ascending:false}).limit(100);if(result.error)throw result.error;staff=result.data ?? [];loading=false;}
  async function save(id:string,displayName:string,active:boolean){
    if(busy)return;
    busy=true;error='';success='';
    try{const result=await requireSupabase().rpc('set_employee',{p_user:id,p_name:displayName.trim(),p_active:active});if(result.error)throw result.error;await load();userId='';name='';success=active?'Empleado activo.':'Empleado desactivado.';}
    catch(cause){error=friendlyError(cause);}finally{busy=false;}
  }
  onMount(()=>{void load().catch((cause)=>{error=friendlyError(cause);loading=false;});});
</script>

<div class="page-head"><div><p class="eyebrow">Administración</p><h1>Personal</h1><p>Activa o desactiva empleados con una identidad de Auth verificada.</p></div><a class="button ghost small" href="/admin/gestion">Volver</a></div>
<Notice message={error} /><Notice message={success} kind="success" />
<section class="card"><h2>Agregar empleado verificado</h2><p class="muted">Primero crea y confirma su usuario en Supabase Auth desde el entorno administrativo. Luego usa su identificador aquí. Este formulario no crea contraseñas.</p>
  <form class="form-grid" onsubmit={(event)=>{event.preventDefault();void save(userId,name,true);}}><label>UUID del usuario Auth<input bind:value={userId} required pattern={'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'} autocomplete="off" /></label><label>Nombre visible<input bind:value={name} minlength="2" maxlength="80" required /></label><button disabled={busy}>Activar empleado</button></form>
</section>
<section><div class="section-head"><h2>Equipo</h2></div>{#if loading}<p role="status" class="muted">Cargando personal…</p>{:else}<div class="list">{#if !staff.length}<Empty title="Sin personal registrado" />{/if}
  {#each staff as person}<div class="list-row"><div><h3>{person.display_name ?? 'Sin nombre visible'}</h3><p class="muted">{person.role==='admin'?'Administrador':'Empleado'} · {person.active?'Activo':'Inactivo'}</p><small class="muted">{person.user_id}</small></div>{#if person.role==='employee'}<button class={person.active?'danger':'secondary'} disabled={busy} onclick={()=>{if(confirm(person.active?'¿Desactivar a este empleado?':'¿Activar a este empleado?'))void save(person.user_id,person.display_name ?? 'Empleado',!person.active);}}>{person.active?'Desactivar':'Activar'}</button>{/if}</div>{/each}
</div>{/if}</section>
