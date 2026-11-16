<script lang="ts">
  import { onMount } from 'svelte';
  import { requireSupabase } from '$lib/supabase';
  import { dateTime, money } from '$lib/format';
  import { friendlyError } from '$lib/errors';
  import Empty from '$lib/ui/Empty.svelte';
  import Notice from '$lib/ui/Notice.svelte';
  let { basePath }: { basePath: '/admin' | '/empleado' } = $props();
  type Account = { id:string; customer_id:string|null; guest_name:string|null; opened_at:string; closed_at:string|null };
  let accounts=$state<Account[]>([]);
  let names=$state<Record<string,string>>({});
  let payments=$state<Record<string,{amount_cop:number;method:string|null}>>({});
  let pageIndex=$state(0);
  let total=$state(0);
  let search=$state('');
  let fromDate=$state('');
  let toDate=$state('');
  let shiftId=$state('');
  let shifts=$state<{id:string;opened_at:string}[]>([]);
  let customerQuery=$state('');
  let customerMatches=$state<{id:string;name:string;phone:string|null}[]>([]);
  let selectedCustomer=$state<{id:string;name:string}|null>(null);
  let error=$state('');
  let loading=$state(true);
  const size=20;
  let visible=$derived(accounts.filter((account)=>(account.guest_name ?? names[account.customer_id ?? ''] ?? '').toLocaleLowerCase('es-CO').includes(search.trim().toLocaleLowerCase('es-CO'))));
  async function load() {
    loading=true;
    const db=requireSupabase();
    let request=db.from('accounts').select('id,customer_id,guest_name,opened_at,closed_at',{count:'exact'}).eq('status','closed');
    if (selectedCustomer) request=request.eq('customer_id',selectedCustomer.id);
    if (shiftId) request=request.eq('shift_id',shiftId);
    if (fromDate) request=request.gte('opened_at',`${fromDate}T00:00:00-05:00`);
    if (toDate) request=request.lte('opened_at',`${toDate}T23:59:59-05:00`);
    const result=await request.order('closed_at',{ascending:false}).range(pageIndex*size,pageIndex*size+size-1);
    if (result.error) throw result.error;
    accounts=result.data ?? [];total=result.count ?? 0;
    const ids=accounts.map((account)=>account.id);
    const customerIds=[...new Set(accounts.map((account)=>account.customer_id).filter((id):id is string=>!!id))];
    const [c,p]=await Promise.all([
      customerIds.length ? db.from('customers').select('id,name').in('id',customerIds) : Promise.resolve({data:[],error:null}),
      ids.length ? db.from('payments').select('account_id,amount_cop,method').in('account_id',ids) : Promise.resolve({data:[],error:null})
    ]);
    if (c.error || p.error) throw c.error ?? p.error;
    names=Object.fromEntries((c.data ?? []).map((customer)=>[customer.id,customer.name]));
    payments=Object.fromEntries((p.data ?? []).map((payment)=>[payment.account_id,payment]));
    loading=false;
  }
  async function findCustomers(){
    if(customerQuery.trim().length<2){customerMatches=[];return;}
    const result=await requireSupabase().rpc('search_customers',{p_query:customerQuery.trim(),p_limit:20});
    if(result.error){error=friendlyError(result.error);return;}
    customerMatches=result.data ?? [];
  }
  function refresh(){void load().catch((cause)=>{error=friendlyError(cause);loading=false;});}
  onMount(()=>{void (async()=>{try{const s=await requireSupabase().from('shifts').select('id,opened_at').order('opened_at',{ascending:false}).limit(30);if(s.error)throw s.error;shifts=s.data ?? [];await load();}catch(cause){error=friendlyError(cause);loading=false;}})();});
</script>

<div class="page-head"><div><p class="eyebrow">Historial</p><h1>Cuentas cerradas</h1><p>Consumos y pagos que ya quedaron registrados.</p></div><a class="button ghost small" href={basePath}>Volver al inicio</a></div>
<Notice message={error} />
<form class="inline card" onsubmit={(event)=>{event.preventDefault();void findCustomers();}}><label>Cliente identificado<input type="search" bind:value={customerQuery} placeholder="Buscar por nombre" minlength="2" /></label><button class="secondary">Buscar cliente</button></form>
{#if customerMatches.length}<div class="list" style="margin-top:.5rem">{#each customerMatches as person}<button class="list-row ghost full" style="border:0;border-top:1px solid var(--line);border-radius:0;justify-content:space-between;text-align:left" onclick={()=>{selectedCustomer=person;customerMatches=[];pageIndex=0;refresh();}}><span>{person.name}{person.phone ? ` · ${person.phone}` : ''}</span><span>Filtrar</span></button>{/each}</div>{/if}
{#if selectedCustomer}<p class="muted">Cliente: {selectedCustomer.name} <button class="ghost small" onclick={()=>{selectedCustomer=null;customerQuery='';pageIndex=0;refresh();}}>Quitar filtro</button></p>{/if}
<form class="form-grid card" onsubmit={(event)=>{event.preventDefault();pageIndex=0;refresh();}}><label>Desde<input type="date" bind:value={fromDate} /></label><label>Hasta<input type="date" bind:value={toDate} /></label><label>Jornada<select bind:value={shiftId}><option value="">Todas</option>{#each shifts as shift}<option value={shift.id}>{dateTime(shift.opened_at)}</option>{/each}</select></label><button>Aplicar filtros</button></form>
<label style="max-width:22rem">Buscar en esta página<input bind:value={search} placeholder="Nombre del cliente" /></label>
{#if loading}<p role="status" class="muted">Cargando historial…</p>{:else}<div class="list" style="margin-top:1rem">{#if !visible.length}<Empty title="Sin cuentas en esta página" detail="Cambia la búsqueda o avanza a otra página." />{/if}
  {#each visible as account}<a class="list-row" href={`${basePath}/cuentas/${account.id}`} style="text-decoration:none"><div><h3>{account.guest_name ?? names[account.customer_id ?? ''] ?? 'Cliente'}</h3><p class="muted">Cerrada {account.closed_at ? dateTime(account.closed_at) : ''}</p><p class="muted">{payments[account.id]?.method==='cash' ? 'Efectivo' : payments[account.id]?.method==='transfer' ? 'Transferencia' : 'Medio no registrado'}</p></div><strong>{money(payments[account.id]?.amount_cop ?? 0)}</strong></a>{/each}</div>
  <div class="row-actions" style="margin-top:1rem"><button class="ghost" disabled={pageIndex===0} onclick={()=>{pageIndex--;refresh();}}>Anterior</button><span class="muted">{total ? pageIndex*size+1 : 0}–{Math.min((pageIndex+1)*size,total)} de {total}</span><button class="ghost" disabled={(pageIndex+1)*size>=total} onclick={()=>{pageIndex++;refresh();}}>Siguiente</button></div>
{/if}
