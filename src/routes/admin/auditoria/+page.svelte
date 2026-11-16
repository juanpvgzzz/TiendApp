<script lang="ts">
  import { requireSupabase } from '$lib/supabase';
  import { dateTime, money } from '$lib/format';
  import { friendlyError } from '$lib/errors';
  import Notice from '$lib/ui/Notice.svelte';
  import Empty from '$lib/ui/Empty.svelte';
  type Entry={id:string;actor:string|null;action:string;entity_id:string;details:Record<string,unknown>;created_at:string};
  const labels:Record<string,string>={account_opened:'Cuenta abierta',account_linked:'Cuenta vinculada',link_code_created:'Código generado',link_codes_revoked:'Códigos revocados',customer_registered:'Cliente registrado',employee_changed:'Empleado actualizado',delivery_corrected:'Consumo corregido',payment_confirmed:'Cobro confirmado',shift_closed:'Jornada cerrada',order_cancelled:'Pedido cancelado',product_saved:'Producto guardado',product_updated:'Producto actualizado',product_availability_changed:'Disponibilidad cambiada'};
  let entries=$state<Entry[]>([]);
  let limit=$state(50);
  let loading=$state(false);
  let loaded=$state(false);
  let error=$state('');
  async function load(){
    loading=true;error='';
    try{const result=await requireSupabase().rpc('audit_history',{p_limit:limit});if(result.error)throw result.error;entries=result.data ?? [];loaded=true;}
    catch(cause){error=friendlyError(cause);}finally{loading=false;}
  }
</script>

<div class="page-head"><div><p class="eyebrow">Administración</p><h1>Auditoría</h1><p>Registro de cambios sensibles de la tienda.</p></div><a class="button ghost small" href="/admin/gestion">Volver</a></div>
<form class="inline card" onsubmit={(event)=>{event.preventDefault();void load();}}><label>Últimos registros<select bind:value={limit}><option value={50}>50</option><option value={100}>100</option><option value={200}>200</option></select></label><button disabled={loading}>{loading?'Cargando…':'Consultar'}</button></form>
<Notice message={error} />
{#if loaded}<div class="list" style="margin-top:1rem">{#if !entries.length}<Empty title="Sin eventos registrados" />{/if}{#each entries as entry}<div class="list-row"><div><h3>{labels[entry.action] ?? entry.action}</h3><p class="muted">{dateTime(entry.created_at)} · Actor {entry.actor?.slice(0,8) ?? 'Sistema'}</p><p class="muted">Registro {entry.entity_id.slice(0,8)}</p>{#if entry.action==='delivery_corrected'}<p>Unidades: {String(entry.details.delta ?? '')} · Motivo: {String(entry.details.reason ?? '')}</p>{:else if entry.action==='payment_confirmed'}<p>{money(Number(entry.details.amount_cop ?? 0))} · {entry.details.method==='cash'?'Efectivo':'Transferencia'}</p>{/if}</div></div>{/each}</div>{/if}
