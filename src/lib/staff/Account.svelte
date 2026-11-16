<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/state';
  import { requireSupabase } from '$lib/supabase';
  import { dateTime, money } from '$lib/format';
  import { friendlyError } from '$lib/errors';
  import Badge from '$lib/ui/Badge.svelte';
  import Notice from '$lib/ui/Notice.svelte';
  import Empty from '$lib/ui/Empty.svelte';
  let { basePath, canCorrect = false }: { basePath: '/admin' | '/empleado'; canCorrect?: boolean } = $props();

  type Account = { id:string; status:string; guest_name:string|null; customer_id:string|null; opened_at:string; closed_at:string|null };
  type Product = { id:string; name:string; price_cop:number; active:boolean };
  type Delivery = { id:string; product_name:string; quantity:number; unit_price_cop:number; delivered_at:string; delivered_by:string; ordered_at:string|null };
  type Order = { id:string; status:string; created_at:string };
  type Item = { id:string; order_id:string; product_id:string; quantity:number; delivered_quantity:number };
  type PaymentRequest = { id:string; taken_by:string|null; requested_at:string };
  type Payment = { amount_cop:number; method:string|null; received_at:string };
  let account = $state<Account|null>(null);
  let name = $state('Cuenta');
  let summary = $state<{total_cop:number;paid_cop:number}|null>(null);
  let deliveries = $state<Delivery[]>([]);
  let orders = $state<Order[]>([]);
  let items = $state<Item[]>([]);
  let products = $state<Product[]>([]);
  let request = $state<PaymentRequest|null>(null);
  let payment = $state<Payment|null>(null);
  let productId = $state('');
  let quantity = $state(1);
  let paymentMethod = $state<'cash'|'transfer'>('cash');
  let code = $state('');
  let busy = $state('');
  let loading = $state(true);
  let error = $state('');
  let success = $state('');
  let connection = $state('');
  let directKey = $state(crypto.randomUUID());
  let productQuery = $state('');
  let correctionId = $state('');
  let correctionDelta = $state(-1);
  let correctionReason = $state('');
  let correctionKey = $state(crypto.randomUUID());
  let visibleProducts = $derived(products.filter((product)=>product.active && product.name.toLocaleLowerCase('es-CO').includes(productQuery.trim().toLocaleLowerCase('es-CO'))).slice(0,productQuery.trim()?30:12));
  let selectedProduct = $derived(products.find((product)=>product.id===productId));
  const id = $derived(page.params.id ?? '');
  let loadId=0;

  async function load() {
    const current=++loadId;
    const accountId=id;
    const db=requireSupabase();
    const [a,s,d,o,p,r,paid]=await Promise.all([
      db.from('accounts').select('id,status,guest_name,customer_id,opened_at,closed_at').eq('id',accountId).single(),
      db.rpc('account_summary',{p_account:accountId}),
      db.rpc('account_delivery_details',{p_account:accountId}),
      db.from('orders').select('id,status,created_at').eq('account_id',accountId).order('created_at',{ascending:false}).limit(100),
      db.from('products').select('id,name,price_cop,active').order('name').limit(300),
      db.from('payment_requests').select('id,taken_by,requested_at').eq('account_id',accountId).is('cancelled_at',null).maybeSingle(),
      db.from('payments').select('amount_cop,method,received_at').eq('account_id',accountId).maybeSingle()
    ]);
    const failed=[a,s,d,o,p,r,paid].find((result)=>result.error);
    if (failed?.error) throw failed.error;
    let nextName=a.data?.guest_name ?? 'Cliente';
    if (a.data?.customer_id) {
      const customer=await db.from('customers').select('name').eq('id',a.data.customer_id).single();
      if(customer.error) throw customer.error;
      nextName=customer.data?.name ?? nextName;
    }
    const orderIds=(o.data ?? []).map((order)=>order.id);
    let nextItems:Item[]=[];
    if (orderIds.length) {
      const result=await db.from('order_items').select('id,order_id,product_id,quantity,delivered_quantity').in('order_id',orderIds);
      if (result.error) throw result.error;
      nextItems=result.data ?? [];
    }
    if(current!==loadId) return;
    account=a.data;summary=s.data;deliveries=d.data ?? [];orders=o.data ?? [];
    products=p.data ?? [];request=r.data;payment=paid.data;name=nextName;items=nextItems;
    loading=false; error='';
  }
  async function run(action:string,operation:()=>Promise<string>) {
    if (busy) return;
    busy=action; error=''; success='';
    try { const message=await operation(); await load(); if(action==='direct')directKey=crypto.randomUUID(); if(action==='correct'){correctionId='';correctionKey=crypto.randomUUID();} success=message; }
    catch (cause) { error=friendlyError(cause); }
    finally { busy=''; }
  }
  function refresh(){void load().catch((cause)=>connection=friendlyError(cause));}
  onMount(() => {
    void load().catch((cause)=>{error=friendlyError(cause);loading=false;});
    const db=requireSupabase();
    const filter=`account_id=eq.${id}`;
    const channel=db.channel(`admin-account-${id}`)
      .on('postgres_changes',{event:'*',schema:'public',table:'deliveries',filter},refresh)
      .on('postgres_changes',{event:'*',schema:'public',table:'orders',filter},refresh)
      .on('postgres_changes',{event:'*',schema:'public',table:'payment_requests',filter},refresh)
      .on('postgres_changes',{event:'*',schema:'public',table:'accounts',filter:`id=eq.${id}`},refresh)
      .on('postgres_changes',{event:'INSERT',schema:'public',table:'account_events',filter},refresh)
      .subscribe((state)=>{if(state==='SUBSCRIBED'){connection='';refresh();}else if(state==='CHANNEL_ERROR'||state==='TIMED_OUT')connection='Sin conexión en vivo. Actualiza la página.';});
    const visibility=()=>{if(!document.hidden)void load().catch(()=>connection='No se pudo recuperar la información.');};
    document.addEventListener('visibilitychange',visibility);
    window.addEventListener('online',visibility);
    return ()=>{document.removeEventListener('visibilitychange',visibility);window.removeEventListener('online',visibility);void db.removeChannel(channel);};
  });
</script>

<div class="page-head"><div><p class="eyebrow">Cuenta de consumo</p><h1>{name}</h1><p>{account ? `Abierta ${dateTime(account.opened_at)}` : 'Cargando…'}</p></div><a class="button ghost small" href={basePath}>Volver al inicio</a></div>
<Notice message={error} /><Notice message={success} kind="success" /><Notice message={connection} kind="info" />
{#if loading}<p role="status" class="muted">Cargando cuenta…</p>{:else if !account}<Empty title="Cuenta no disponible" />{:else}
<div class="grid"><section class="card account-summary-card"><div class="page-head" style="margin:0"><div><p class="eyebrow">Total confirmado</p><div class="metric">{money(summary?.total_cop ?? 0)}</div></div><Badge status={account.status} /></div>
  {#if account.status==='closed' && payment}<hr class="divider" /><p>Pago recibido: <strong>{money(payment.amount_cop)}</strong></p><p class="muted">{payment.method==='cash' ? 'Efectivo' : payment.method==='transfer' ? 'Transferencia' : 'Medio no registrado'} · {dateTime(payment.received_at)}</p>{/if}
</section><section class="card"><h2>Acciones de la cuenta</h2>
  {#if account.status!=='closed'}<button class="secondary" disabled={!!busy} onclick={()=>void run('code',async()=>{const result=await requireSupabase().rpc('create_link_code',{p_account:id});if(result.error)throw result.error;code=result.data;return 'Código creado. Caduca en 10 minutos.';})}>Generar código temporal</button>
    {#if code}<p class="code" aria-label={`Código ${code}`}>{code}</p><p class="muted">Compártelo solo con la persona de esta cuenta. Se usa una vez.</p><button class="ghost small" disabled={!!busy} onclick={()=>void run('revoke-code',async()=>{const result=await requireSupabase().rpc('revoke_link_codes',{p_account:id});if(result.error)throw result.error;code='';return 'Código revocado.';})}>Revocar código</button>{/if}
  {/if}
  {#if account.status==='paying'}<p>El cliente solicitó pagar. Revisa el total y confirma cuando recibas el dinero.</p>
    {#if request && !request.taken_by}<button class="secondary" disabled={!!busy} onclick={()=>void run('take-payment',async()=>{if(!request)throw new Error('Solicitud no disponible.');const result=await requireSupabase().rpc('take_payment_request',{p_request:request.id});if(result.error)throw result.error;return 'Solicitud en atención.';})}>Tomar solicitud</button>{/if}
    <label>Medio de pago<select bind:value={paymentMethod}><option value="cash">Efectivo</option><option value="transfer">Transferencia</option></select></label>
    <button disabled={!!busy || orders.some((order)=>order.status==='pending'||order.status==='taken')} onclick={()=>{if(confirm(`¿Confirmas que recibiste ${money(summary?.total_cop ?? 0)}?`))void run('pay',async()=>{const result=await requireSupabase().rpc('confirm_payment',{p_account:id,p_method:paymentMethod});if(result.error)throw result.error;return `Pago de ${money(result.data)} confirmado. Cuenta cerrada.`;});}}>{busy==='pay' ? 'Confirmando…' : 'Confirmar cobro y cerrar'}</button>
    {#if orders.some((order)=>order.status==='pending'||order.status==='taken')}<p class="muted">Resuelve los pedidos pendientes antes del cobro.</p>{/if}
  {:else if account.status==='closed'}<p class="muted">La cuenta está cerrada y su historial se conserva aquí.</p>{/if}
</section></div>
{#if account.status==='open'}<section class="card"><h2>Registrar consumo directo</h2><p class="muted">Para productos entregados sin pedido digital.</p>
  <label>Buscar producto<input type="search" bind:value={productQuery} placeholder="Nombre del producto" /></label>
  <div class="product-choices">{#each visibleProducts as product}<button type="button" class:chosen={productId===product.id} class="product-choice" onclick={()=>productId=product.id}><span>{product.name}</span><strong>{money(product.price_cop)}</strong></button>{/each}</div>
  <div class="inline"><p class="selected-product">{selectedProduct ? `${selectedProduct.name} · ${money(selectedProduct.price_cop)}` : 'Selecciona un producto'}</p>
    <label>Cantidad<input type="number" min="1" max="100" bind:value={quantity} style="width:7rem" /></label>
    <button disabled={!!busy || !productId} onclick={()=>{if(confirm('¿Confirmas que ya entregaste este producto?'))void run('direct',async()=>{if(!Number.isInteger(quantity)||quantity<1||quantity>100)throw new Error('invalid request');const result=await requireSupabase().rpc('record_direct_delivery',{p_account:id,p_product:productId,p_quantity:quantity,p_key:directKey});if(result.error)throw result.error;return 'Consumo registrado.';});}}>{busy==='direct' ? 'Guardando…' : 'Registrar entrega'}</button>
  </div></section>{/if}
<div class="grid"><section><div class="section-head"><h2>Consumos entregados</h2></div><div class="list">{#if !deliveries.length}<Empty title="Sin consumos aún" />{/if}
  {#each deliveries as delivery}<div class="list-row"><div><h3>{delivery.product_name}</h3><p class="muted">{dateTime(delivery.delivered_at)} · Entregó {delivery.delivered_by}</p>{#if delivery.ordered_at}<p class="muted">Solicitado {dateTime(delivery.ordered_at)}</p>{/if}{#if canCorrect && account.status!=='closed'}<button class="ghost small" onclick={()=>{correctionId=delivery.id;correctionDelta=-1;correctionReason='';correctionKey=crypto.randomUUID();}}>Corregir</button>{/if}</div><div style="text-align:right"><strong>{money(delivery.quantity*delivery.unit_price_cop)}</strong><p class="muted">{delivery.quantity} × {money(delivery.unit_price_cop)}</p></div></div>{/each}</div>
  {#if canCorrect && correctionId && account.status!=='closed'}<form class="card stack" style="margin-top:1rem" onsubmit={(event)=>{event.preventDefault();if(confirm('¿Confirmas esta corrección de consumo?'))void run('correct',async()=>{const result=await requireSupabase().rpc('correct_delivery',{p_delivery:correctionId,p_delta:correctionDelta,p_reason:correctionReason.trim(),p_key:correctionKey});if(result.error)throw result.error;return 'Corrección registrada y auditada.';});}}><h3>Corregir consumo</h3><label>Unidades a ajustar<input type="number" bind:value={correctionDelta} min="-100" max="100" step="1" required /></label><label>Motivo<input bind:value={correctionReason} minlength="5" maxlength="500" required /></label><div class="row-actions"><button disabled={!!busy || correctionDelta===0}>{busy==='correct' ? 'Guardando…' : 'Confirmar corrección'}</button><button type="button" class="ghost" onclick={()=>correctionId=''}>Cancelar</button></div></form>{/if}
  </section>
<section><div class="section-head"><h2>Pedidos</h2></div><div class="list">{#if !orders.length}<Empty title="Sin pedidos digitales" />{/if}
  {#each orders as order}<div class="list-row" style="display:block"><div class="page-head" style="margin:0"><p class="muted">{dateTime(order.created_at)}</p><Badge status={order.status} /></div>
    {#each items.filter((item)=>item.order_id===order.id) as item}<p>{products.find((product)=>product.id===item.product_id)?.name ?? 'Producto'} · {item.delivered_quantity}/{item.quantity} entregados</p>{/each}</div>{/each}</div></section></div>
{/if}
