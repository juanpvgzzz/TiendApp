<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { requireSupabase } from '$lib/supabase';
  import { dateTime, money } from '$lib/format';
  import { friendlyError } from '$lib/errors';
  import Badge from '$lib/ui/Badge.svelte';
  import Notice from '$lib/ui/Notice.svelte';
  import Empty from '$lib/ui/Empty.svelte';
  let { basePath }: { basePath: '/admin' | '/empleado' } = $props();

  type Account = { id:string; status:string; guest_name:string|null; customer_id:string|null; opened_at:string };
  type Order = { id:string; account_id:string; status:string; created_at:string };
  type Item = { id:string; order_id:string; product_id:string; quantity:number; delivered_quantity:number };
  type Request = { id:string; account_id:string; requested_at:string; taken_by:string|null };
  let accounts = $state<Account[]>([]);
  let orders = $state<Order[]>([]);
  let items = $state<Item[]>([]);
  let requests = $state<Request[]>([]);
  let names = $state<Record<string,string>>({});
  let productNames = $state<Record<string,string>>({});
  let quantities = $state<Record<string,number>>({});
  let keys = $state<Record<string,string>>({});
  let busy = $state('');
  let loading = $state(true);
  let error = $state('');
  let success = $state('');
  let connection = $state('');
  let shift = $state<{id:string;opened_at:string}|null>(null);
  let search = $state('');
  let totals = $state<Record<string,number>>({});
  let visibleAccounts = $derived(accounts.filter((account)=>nameFor(account.id).toLocaleLowerCase('es-CO').includes(search.trim().toLocaleLowerCase('es-CO'))));

  const nameFor = (id:string) => {
    const account = accounts.find((entry) => entry.id === id);
    return account?.guest_name ?? (account?.customer_id ? names[account.customer_id] : undefined) ?? 'Cuenta';
  };
  const keyFor = (id:string) => keys[id] ?? (keys[id] = crypto.randomUUID());
  let loadId=0;
  async function load() {
    const current=++loadId;
    const db = requireSupabase();
    const [a,o,r,s] = await Promise.all([
      db.from('accounts').select('id,status,guest_name,customer_id,opened_at').in('status',['open','paying']).order('opened_at',{ascending:false}).limit(100),
      db.from('orders').select('id,account_id,status,created_at').in('status',['pending','taken']).order('created_at').limit(100),
      db.from('payment_requests').select('id,account_id,requested_at,taken_by').is('cancelled_at',null).order('requested_at').limit(100),
      db.from('shifts').select('id,opened_at').is('closed_at',null).limit(1)
    ]);
    const failed = [a,o,r,s].find((result) => result.error);
    if (failed?.error) throw failed.error;
    const nextAccounts=a.data ?? [];
    const nextOrders=o.data ?? [];
    const customerIds=[...new Set(nextAccounts.map((account)=>account.customer_id).filter((id):id is string=>!!id))];
    const orderIds=nextOrders.map((order)=>order.id);
    const [c,i]=await Promise.all([
      customerIds.length?db.from('customers').select('id,name').in('id',customerIds):Promise.resolve({data:[],error:null}),
      orderIds.length?db.from('order_items').select('id,order_id,product_id,quantity,delivered_quantity').in('order_id',orderIds):Promise.resolve({data:[],error:null})
    ]);
    if(c.error || i.error) throw c.error ?? i.error;
    const nextItems=i.data ?? [];
    const productIds=[...new Set(nextItems.map((item)=>item.product_id))];
    const [p,summaries] = await Promise.all([
      productIds.length?db.from('products').select('id,name').in('id',productIds):Promise.resolve({data:[],error:null}),
      Promise.all(nextAccounts.map(async (account) => {
      const result = await db.rpc('account_summary',{p_account:account.id});
      if (result.error) throw result.error;
      return [account.id,result.data?.total_cop ?? 0] as const;
      }))
    ]);
    if(p.error) throw p.error;
    if(current!==loadId) return;
    accounts = nextAccounts;orders=nextOrders;items=nextItems;
    requests = (r.data ?? []).filter((request) => nextAccounts.some((account) => account.id === request.account_id && account.status === 'paying'));
    names = Object.fromEntries((c.data ?? []).map((customer) => [customer.id,customer.name]));
    productNames = Object.fromEntries((p.data ?? []).map((product) => [product.id,product.name]));
    shift = s.data?.[0] ?? null;
    totals = Object.fromEntries(summaries);
    loading = false; error = '';
  }
  async function run(id:string, operation:() => Promise<void>, message:string) {
    if (busy) return;
    busy = id; error = ''; success = '';
    try { await operation(); await load(); delete keys[id]; success = message; }
    catch (cause) { error = friendlyError(cause); }
    finally { busy = ''; }
  }
  async function rpc(name:string,args:Record<string,unknown>) {
    const { error: rpcError } = await requireSupabase().rpc(name,args);
    if (rpcError) throw rpcError;
  }
  async function signOut() { await requireSupabase().auth.signOut(); await goto(`${basePath}/login`); }

  onMount(() => {
    void load().catch((cause) => { error = friendlyError(cause); loading = false; });
    const db = requireSupabase();
    const channel = db.channel(`staff-operations-${basePath}`)
      .on('postgres_changes',{event:'*',schema:'public',table:'orders'},() => { void load().catch(() => connection='Sin conexión en vivo. Actualiza la página.'); })
      .on('postgres_changes',{event:'*',schema:'public',table:'deliveries'},() => { void load().catch(() => connection='Sin conexión en vivo. Actualiza la página.'); })
      .on('postgres_changes',{event:'*',schema:'public',table:'payment_requests'},() => { void load().catch(() => connection='Sin conexión en vivo. Actualiza la página.'); })
      .on('postgres_changes',{event:'*',schema:'public',table:'accounts'},() => { void load().catch(() => connection='Sin conexión en vivo. Actualiza la página.'); })
      .on('postgres_changes',{event:'INSERT',schema:'public',table:'account_events'},() => { void load().catch(() => connection='Sin conexión en vivo. Actualiza la página.'); })
      .subscribe((state) => { if (state === 'SUBSCRIBED') { connection=''; void load().catch(() => connection='No se pudo recuperar la información.'); } else if (state === 'CHANNEL_ERROR' || state === 'TIMED_OUT') connection='Sin conexión en vivo. Actualiza la página.'; });
    const visibility = () => { if (!document.hidden) void load().catch(() => connection='No se pudo recuperar la información.'); };
    document.addEventListener('visibilitychange',visibility);
    window.addEventListener('online',visibility);
    return () => { document.removeEventListener('visibilitychange',visibility); window.removeEventListener('online',visibility); void db.removeChannel(channel); };
  });
</script>

<div class="operations-hero"><div class="page-head"><div><p class="eyebrow">Jornada actual</p><h1>Lo que necesita atención</h1><p>{shift ? `Abierta ${dateTime(shift.opened_at)}` : 'No hay jornada abierta.'}</p></div><button class="ghost small" onclick={signOut}>Cerrar sesión</button></div>
{#if !loading}<div class="operations-stats"><div class="stat"><span>Cuentas abiertas</span><strong>{accounts.filter((account) => account.status === 'open').length}</strong><a href={`${basePath}/clientes`}>Abrir una cuenta →</a></div><div class="stat"><span>Por atender</span><strong>{orders.length + requests.length}</strong><span>Pedidos y solicitudes de pago</span></div></div>{/if}</div>
<Notice message={error} /><Notice message={success} kind="success" /><Notice message={connection} kind="info" />
{#if loading}<p role="status" class="muted">Cargando actividad…</p>{:else}
<section id="pagos"><div class="section-head"><h2>Solicitudes de pago</h2><span class="badge" data-status="paying">{requests.length}</span></div>
  <div class="list">{#if !requests.length}<Empty title="Sin pagos pendientes" detail="Las solicitudes nuevas aparecerán aquí." />{/if}
    {#each requests as request}<div class="list-row"><div><h3>{nameFor(request.account_id)}</h3><p class="muted">{dateTime(request.requested_at)}</p></div><a class="button small" href={`${basePath}/cuentas/${request.account_id}`}>Revisar cobro</a></div>{/each}</div>
</section>
<section id="pedidos"><div class="section-head"><h2>Pedidos por atender</h2><span class="badge" data-status="pending">{orders.length}</span></div>
  <div class="list">{#if !orders.length}<Empty title="Sin pedidos pendientes" detail="Los pedidos de los clientes aparecerán en tiempo real." />{/if}
    {#each orders as order}<article class="list-row" style="display:block"><div class="page-head" style="margin:0 0 .6rem"><div><h3><a href={`${basePath}/cuentas/${order.account_id}`}>{nameFor(order.account_id)}</a></h3><p class="muted">{dateTime(order.created_at)}</p></div><Badge status={order.status} /></div>
      {#each items.filter((item) => item.order_id === order.id) as item}<div class="list-row" style="padding:.7rem 0"><div><strong>{productNames[item.product_id] ?? 'Producto'}</strong><p class="muted">{item.delivered_quantity} de {item.quantity} entregados</p></div>
        {#if item.delivered_quantity < item.quantity}<div class="inline"><label>Cantidad a entregar<input aria-label={`Cantidad de ${productNames[item.product_id] ?? 'producto'} a entregar`} type="number" min="1" max={item.quantity-item.delivered_quantity} value={quantities[item.id] ?? item.quantity-item.delivered_quantity} oninput={(event) => quantities[item.id]=Number(event.currentTarget.value)} style="width:5rem" /></label>
          <button class="small" disabled={!!busy} onclick={() => void run(`deliver-${item.id}`,async () => { const count=quantities[item.id] ?? item.quantity-item.delivered_quantity; if (!Number.isInteger(count) || count<1 || count>item.quantity-item.delivered_quantity) throw new Error('invalid request'); await rpc('confirm_delivery',{p_item:item.id,p_quantity:count,p_key:keyFor(`deliver-${item.id}`)}); },'Entrega confirmada.')}>{busy === `deliver-${item.id}` ? 'Guardando…' : 'Entregar'}</button></div>{/if}
      </div>{/each}
      <div class="row-actions" style="margin-top:.7rem">{#if order.status === 'pending'}<button class="secondary small" disabled={!!busy} onclick={() => void run(`take-${order.id}`,() => rpc('take_order',{p_order:order.id}),'Pedido en atención.')}>Tomar pedido</button>{/if}
        <button class="danger small" disabled={!!busy} onclick={() => { if (confirm('¿Cancelar lo que falta de este pedido?')) void run(`cancel-${order.id}`,() => rpc('cancel_order',{p_order:order.id,p_key:keyFor(`cancel-${order.id}`)}),'Pedido cancelado.'); }}>Cancelar pedido</button></div>
    </article>{/each}</div>
</section>
<section class="active-accounts"><div class="section-head"><h2>Cuentas activas</h2><a href={`${basePath}/clientes`}>Abrir cuenta →</a></div><label class="search-field">Buscar checa<input type="search" bind:value={search} placeholder="Nombre del cliente o mesa" /></label><div class="list" style="margin-top:.75rem">{#if !visibleAccounts.length}<Empty title={accounts.length ? 'Sin coincidencias' : 'No hay cuentas abiertas'} />{/if}
  {#each visibleAccounts as account}<a class="list-row account-link" href={`${basePath}/cuentas/${account.id}`}><div><h3>{nameFor(account.id)}</h3><p class="muted">Abierta {dateTime(account.opened_at)}</p><Badge status={account.status} /></div><strong class="account-total">{money(totals[account.id] ?? 0)}</strong></a>{/each}</div></section>
{/if}
