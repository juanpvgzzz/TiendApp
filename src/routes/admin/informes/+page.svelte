<script lang="ts">
  import { requireSupabase } from '$lib/supabase';
  import { friendlyError } from '$lib/errors';
  import { money } from '$lib/format';
  import Notice from '$lib/ui/Notice.svelte';
  import Empty from '$lib/ui/Empty.svelte';
  type Product={product_id:string;name:string;quantity:number;amount_cop:number};
  type Responsible={user_id:string;name:string|null;payments:number;amount_cop:number};
  type Report={total_cop:number;payments:number;methods:Record<string,number>;products:Product[];responsibles:Responsible[]};
  const today=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Bogota',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
  let fromDate=$state(today);
  let toDate=$state(today);
  let report=$state<Report|null>(null);
  let busy=$state(false);
  let error=$state('');
  async function load(){
    if(busy)return;
    busy=true;error='';
    try{
      if(!fromDate || !toDate || fromDate>toDate)throw new Error('invalid request');
      const end=new Date(`${toDate}T00:00:00-05:00`);end.setUTCDate(end.getUTCDate()+1);
      const result=await requireSupabase().rpc('basic_report',{p_from:`${fromDate}T00:00:00-05:00`,p_to:end.toISOString()});
      if(result.error)throw result.error;
      report=result.data as Report;
    }catch(cause){error=friendlyError(cause);}finally{busy=false;}
  }
</script>

<div class="page-head"><div><p class="eyebrow">Administración</p><h1>Informes</h1><p>Cobros confirmados en el período seleccionado.</p></div><a class="button ghost small" href="/admin/gestion">Volver</a></div>
<form class="form-grid card" onsubmit={(event)=>{event.preventDefault();void load();}}><label>Desde<input type="date" bind:value={fromDate} required /></label><label>Hasta<input type="date" bind:value={toDate} required /></label><button disabled={busy}>{busy?'Consultando…':'Consultar informe'}</button></form>
<Notice message={error} />
{#if report}<div class="grid" style="margin-top:1rem"><section class="card stat"><span class="muted">Total cobrado</span><strong>{money(report.total_cop)}</strong></section><section class="card stat"><span class="muted">Cobros confirmados</span><strong>{report.payments}</strong></section></div>
  <div class="grid"><section><div class="section-head"><h2>Medios de pago</h2></div><div class="list">{#if !Object.keys(report.methods).length}<Empty title="Sin cobros en el período" />{/if}{#each Object.entries(report.methods) as [method,amount]}<div class="list-row"><span>{method==='cash'?'Efectivo':method==='transfer'?'Transferencia':'Sin especificar'}</span><strong>{money(amount)}</strong></div>{/each}</div></section>
  <section><div class="section-head"><h2>Responsables</h2></div><div class="list">{#if !report.responsibles.length}<Empty title="Sin cobros" />{/if}{#each report.responsibles as person}<div class="list-row"><div><strong>{person.name ?? 'Personal'}</strong><p class="muted">{person.payments} {person.payments===1?'cobro':'cobros'}</p></div><strong>{money(person.amount_cop)}</strong></div>{/each}</div></section></div>
  <section><div class="section-head"><h2>Productos consumidos</h2></div><div class="list">{#if !report.products.length}<Empty title="Sin productos cobrados" />{/if}{#each report.products as product}<div class="list-row"><div><strong>{product.name}</strong><p class="muted">{product.quantity} unidades</p></div><strong>{money(product.amount_cop)}</strong></div>{/each}</div></section>
{/if}
