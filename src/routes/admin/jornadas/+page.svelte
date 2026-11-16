<script lang="ts">
  import { onMount } from 'svelte';
  import { requireSupabase } from '$lib/supabase';
  import { dateTime } from '$lib/format';
  import { friendlyError } from '$lib/errors';
  import Notice from '$lib/ui/Notice.svelte';
  import Empty from '$lib/ui/Empty.svelte';
  type Shift={id:string;opened_at:string;closed_at:string|null};
  let shifts=$state<Shift[]>([]);
  let activeAccounts=$state(0);
  let busy=$state(false);
  let loading=$state(true);
  let error=$state('');
  let success=$state('');
  let current=$derived(shifts.find((shift)=>!shift.closed_at));

  async function load() {
    const db=requireSupabase();
    const [s,a]=await Promise.all([
      db.from('shifts').select('id,opened_at,closed_at').order('opened_at',{ascending:false}).limit(30),
      db.from('accounts').select('id',{count:'exact',head:true}).in('status',['open','paying'])
    ]);
    if(s.error || a.error) throw s.error ?? a.error;
    shifts=s.data ?? [];activeAccounts=a.count ?? 0;loading=false;error='';
  }
  async function run(name:'start_shift'|'close_shift',args:Record<string,string>,message:string) {
    if(busy) return;
    busy=true;error='';success='';
    try {const result=await requireSupabase().rpc(name,args);if(result.error)throw result.error;await load();success=message;}
    catch(cause){error=friendlyError(cause);}
    finally{busy=false;}
  }
  onMount(()=>{void load().catch((cause)=>{error=friendlyError(cause);loading=false;});});
</script>

<div class="page-head"><div><p class="eyebrow">Administración</p><h1>Jornadas</h1><p>La jornada sigue abierta después de medianoche hasta su cierre manual.</p></div><a class="button ghost small" href="/admin/gestion">Volver</a></div>
<Notice message={error} /><Notice message={success} kind="success" />
{#if loading}<p role="status" class="muted">Cargando jornadas…</p>{:else}
  <section class="card stack"><div><h2>Jornada actual</h2>{#if current}<p>Abierta {dateTime(current.opened_at)}</p><p class="muted">{activeAccounts} {activeAccounts===1?'cuenta activa':'cuentas activas'}</p>{:else}<p class="muted">No hay una jornada abierta.</p>{/if}</div>
    {#if current}<button class="secondary" disabled={busy || activeAccounts>0} onclick={()=>{if(confirm('¿Cerrar la jornada? No se podrán abrir más cuentas en ella.'))void run('close_shift',{p_shift:current.id},'Jornada cerrada.');}}>Cerrar jornada</button>
      {#if activeAccounts>0}<p class="muted">Cierra las cuentas activas antes de terminar la jornada.</p>{/if}
    {:else}<button disabled={busy} onclick={()=>void run('start_shift',{},'Jornada abierta.')}>Abrir jornada</button>{/if}
  </section>
  <section><div class="section-head"><h2>Jornadas recientes</h2></div><div class="list">{#if !shifts.length}<Empty title="Sin jornadas registradas" />{/if}
    {#each shifts as shift}<div class="list-row"><div><strong>{dateTime(shift.opened_at)}</strong><p class="muted">{shift.closed_at ? `Cerrada ${dateTime(shift.closed_at)}` : 'En curso'}</p></div><span class="badge" data-status={shift.closed_at ? 'closed' : 'open'}>{shift.closed_at ? 'Cerrada' : 'Abierta'}</span></div>{/each}
  </div></section>
{/if}
