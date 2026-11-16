<script lang="ts">
  import { onMount } from 'svelte';
  import { fade, fly } from 'svelte/transition';
  import { goto } from '$app/navigation';
  import { customerAccountId, requireSupabase } from '$lib/supabase';
  import { dateTime, money, statusLabel } from '$lib/format';
  import { friendlyError } from '$lib/errors';
  import Badge from '$lib/ui/Badge.svelte';
  import Notice from '$lib/ui/Notice.svelte';
  import Empty from '$lib/ui/Empty.svelte';

  type Account = { id:string; status:string; guest_name:string|null; customer_id:string|null; opened_at:string; closed_at:string|null };
  type Product = { id:string; name:string; category_id:string; price_cop:number; photo_path:string|null };
  type Category = { id:string; name:string };
  type Order = { id:string; status:string; created_at:string };
  type Item = { order_id:string; product_id:string; quantity:number; delivered_quantity:number };
  type Delivery = { id:string; product_name:string; quantity:number; unit_price_cop:number; delivered_at:string; delivered_by:string; ordered_at:string|null };
  let account=$state<Account|null>(null);
  let name=$state('Mi cuenta');
  let total=$state(0);
  let paid=$state(0);
  let products=$state<Product[]>([]);
  let categories=$state<Category[]>([]);
  let orders=$state<Order[]>([]);
  let items=$state<Item[]>([]);
  let deliveries=$state<Delivery[]>([]);
  let selection=$state<Record<string,number>>({});
  let categoryFilter=$state<'cervezas'|'mecatos'>('cervezas');
  let search=$state('');
  let shownCount=$state(12);
  let showOrder=$state(false);
  let orderKey=$state(crypto.randomUUID());
  let confirmPayment=$state(false);
  let busy=$state('');
  let loading=$state(true);
  let error=$state('');
  let success=$state('');
  let connection=$state('');
  let failedPhotos=$state<Record<string,boolean>>({});
  const sectionFor=(product:Product):'cervezas'|'mecatos'=>{
    const category=categories.find((entry)=>entry.id===product.category_id)?.name ?? '';
    if (/cerveza/i.test(category) || /cerveza|beer|pola/i.test(product.name)) return 'cervezas';
    return 'mecatos';
  };
  const isCatalogProduct=(product:Product)=>/cerveza|mecato/i.test(categories.find((entry)=>entry.id===product.category_id)?.name ?? '') || /cerveza|beer|pola/i.test(product.name);
  let visibleProducts=$derived(products.filter((product)=>isCatalogProduct(product) && sectionFor(product)===categoryFilter && product.name.toLocaleLowerCase('es-CO').includes(search.trim().toLocaleLowerCase('es-CO'))));
  let displayedProducts=$derived(visibleProducts.slice(0,shownCount));
  let selectedProducts=$derived(products.filter((product)=>selection[product.id]>0));
  let selectedCount=$derived(selectedProducts.reduce((count,product)=>count+selection[product.id],0));
  let loadId=0;
  const productName=(id:string)=>products.find((product)=>product.id===id)?.name ?? 'Producto no disponible';
  const photoUrl=(path:string|null)=>path ? requireSupabase().storage.from('product-photos').getPublicUrl(path).data.publicUrl : '';
  const artworkFor=(section:'cervezas'|'mecatos')=>section==='cervezas'?'/images/beer-placeholder.svg':'/images/snack-placeholder.svg';
  const categoryPhoto=(section:'cervezas'|'mecatos')=>photoUrl(products.find((product)=>isCatalogProduct(product) && sectionFor(product)===section && product.photo_path && !failedPhotos[product.id])?.photo_path ?? null) || artworkFor(section);
  function quantity(productId:string,change:number) {
    selection={...selection,[productId]:Math.max(0,Math.min(100,(selection[productId] ?? 0)+change))};
  }
  const orderState=(order:Order)=>{
    if (order.status==='cancelled') return 'Cancelado';
    if (order.status==='done') return 'Entregado';
    const orderItems=items.filter((item)=>item.order_id===order.id);
    if (orderItems.some((item)=>item.delivered_quantity>0)) return 'Parcialmente entregado';
    return statusLabel(order.status);
  };

  async function load() {
    const current=++loadId;
    loading=true;account=null;
    const db=requireSupabase();
    const accountId=await customerAccountId();
    if (!accountId) { await goto('/vincular'); return; }
    const [a,s,d,o,p,c]=await Promise.all([
      db.from('accounts').select('id,status,guest_name,customer_id,opened_at,closed_at').eq('id',accountId).single(),
      db.rpc('account_summary',{p_account:accountId}),
      db.rpc('account_delivery_details',{p_account:accountId}),
      db.from('orders').select('id,status,created_at').eq('account_id',accountId).order('created_at',{ascending:false}).limit(100),
      db.from('products').select('id,name,category_id,price_cop,photo_path').eq('active',true).order('name').limit(300),
      db.from('categories').select('id,name').order('name')
    ]);
    const failed=[a,s,d,o,p,c].find((result)=>result.error);
    if (failed?.error) throw failed.error;
    if (!a.data) { await goto('/vincular'); return; }
    let nextName=a.data?.guest_name ?? 'Mi cuenta';
    if (a.data?.customer_id) {
      const customer=await db.from('customers').select('name').eq('id',a.data.customer_id).single();
      if(customer.error) throw customer.error;
      nextName=customer.data?.name ?? nextName;
    }
    const ids=(o.data ?? []).map((order)=>order.id);
    let nextItems:Item[]=[];
    if (ids.length) {
      const result=await db.from('order_items').select('order_id,product_id,quantity,delivered_quantity').in('order_id',ids);
      if (result.error) throw result.error;
      nextItems=result.data ?? [];
    }
    if(current!==loadId) return;
    account=a.data; total=s.data?.total_cop ?? 0; paid=s.data?.paid_cop ?? 0;
    deliveries=d.data ?? []; orders=o.data ?? []; products=p.data ?? []; categories=c.data ?? [];
    name=nextName;items=nextItems;
    loading=false; error='';
  }
  async function sendOrder() {
    if (busy || !account) return;
    busy='order';error='';success='';
    try {
      const selected=selectedProducts.map((product)=>({product_id:product.id,quantity:selection[product.id]}));
      if (!selected.length || selected.some((item)=>!Number.isInteger(item.quantity)||item.quantity<1||item.quantity>100)) throw new Error('invalid items');
      const result=await requireSupabase().rpc('create_order',{p_account:account.id,p_items:selected,p_key:orderKey});
      if (result.error) throw result.error;
      await load();selection={};showOrder=false;orderKey=crypto.randomUUID();success='Pedido enviado. La tienda te avisará cuando lo entregue.';
      document.getElementById('mis-pedidos')?.scrollIntoView({behavior:'smooth'});
    } catch (cause) { error=friendlyError(cause); if (/not authorized|permission denied/i.test(cause instanceof Error ? cause.message : '')) refresh(); }
    finally { busy=''; }
  }
  async function requestPayment() {
    if (busy || !account) return;
    busy='payment';error='';success='';
    try {
      const result=await requireSupabase().rpc('request_payment',{p_account:account.id});
      if (result.error) throw result.error;
      confirmPayment=false;await load();success='Solicitud enviada. El personal confirmará cuando reciba el pago.';
    } catch (cause) { error=friendlyError(cause); if (/not authorized|permission denied/i.test(cause instanceof Error ? cause.message : '')) refresh(); }
    finally { busy=''; }
  }
  function refresh(){void load().catch((cause)=>connection=friendlyError(cause));}
  onMount(() => {
    const db=requireSupabase();
    let channel:ReturnType<typeof db.channel>|undefined;
    let revocationChannel:ReturnType<typeof db.channel>|undefined;
    let disposed=false;
    void load().then(async()=>{
      if (disposed || !account) return;
      const identity=await db.auth.getUser();
      if (disposed || !identity.data.user || !account) return;
      const accountId=account.id;
      revocationChannel=db.channel(`account-access:${identity.data.user.id}`,{config:{private:true}})
        .on('broadcast',{event:'revoked'},(message)=>{if(message.payload?.account_id===accountId)refresh();})
        .subscribe((state)=>{if(state==='SUBSCRIBED')refresh();});
      const filter=`account_id=eq.${account.id}`;
      channel=db.channel(`customer-account-${account.id}`)
        .on('postgres_changes',{event:'*',schema:'public',table:'orders',filter},refresh)
        .on('postgres_changes',{event:'*',schema:'public',table:'deliveries',filter},refresh)
        .on('postgres_changes',{event:'*',schema:'public',table:'payment_requests',filter},refresh)
        .on('postgres_changes',{event:'*',schema:'public',table:'accounts',filter:`id=eq.${account.id}`},refresh)
        .on('postgres_changes',{event:'INSERT',schema:'public',table:'account_events',filter},refresh)
        .subscribe((state)=>{if(state==='SUBSCRIBED'){connection='';refresh();}else if(state==='CHANNEL_ERROR'||state==='TIMED_OUT')connection='Sin conexión en vivo. Actualiza la página.';});
    }).catch((cause)=>{error=friendlyError(cause);loading=false;});
    const visibility=()=>{if(!document.hidden)void load().catch((cause)=>{error=friendlyError(cause);loading=false;});};
    const auth=db.auth.onAuthStateChange((event)=>{if(event==='SIGNED_OUT'||event==='SIGNED_IN'||event==='TOKEN_REFRESHED')queueMicrotask(()=>{if(!disposed)void load().catch((cause)=>{error=friendlyError(cause);loading=false;});});});
    document.addEventListener('visibilitychange',visibility);
    window.addEventListener('online',visibility);
    window.addEventListener('focus',visibility);
    return ()=>{disposed=true;auth.data.subscription.unsubscribe();document.removeEventListener('visibilitychange',visibility);window.removeEventListener('online',visibility);window.removeEventListener('focus',visibility);if(channel)void db.removeChannel(channel);if(revocationChannel)void db.removeChannel(revocationChannel);};
  });
</script>

<div class="customer-page">
  <div class="customer-greeting" id="inicio"><div><p class="eyebrow">Tu tienda de siempre</p><h1>Hola, {name}</h1></div><button class="ghost small" onclick={async()=>{await requireSupabase().auth.signOut();await goto('/vincular');}}>Salir</button></div>
  <Notice message={error} /><Notice message={success} kind="success" /><Notice message={connection} kind="info" />
  {#if loading}
    <div role="status" aria-label="Cargando tu cuenta" class="customer-skeleton"><div class="skeleton balance-skeleton"></div><div class="skeleton search-skeleton"></div><div class="product-grid">{#each [1,2,3,4] as _}<div class="skeleton card-skeleton"></div>{/each}</div></div>
  {:else if !account}<Empty title="Cuenta no disponible" detail="Vuelve a vincular tu cuenta o consulta al administrador." /><button class="secondary" onclick={()=>void load().catch((cause)=>{error=friendlyError(cause);loading=false;})}>Reintentar</button>
  {:else}
    <section class="balance-card" id="cuenta" aria-label="Resumen de mi cuenta"><div class="balance-copy"><p class="eyebrow">Tu checa al día</p><p class="balance-title">Total entregado</p><div class="metric">{money(total)}</div><p>Solo se suman los productos entregados</p></div><div class="balance-actions"><Badge status={account.status} />{#if account.status==='open'}<button class="small" disabled={!!busy} onclick={()=>{confirmPayment=true;document.getElementById('consumos')?.scrollIntoView({behavior:'smooth'});}}>Solicitar pagar</button>{/if}</div></section>
    {#if account.status==='open'}
      <section class="shop-section"><div class="section-head"><h2>¿Qué se te antoja?</h2><span class="muted">Precios en COP</span></div>
        <label class="shop-search"><span class="sr-only">Buscar productos</span><input type="search" bind:value={search} oninput={()=>shownCount=12} placeholder="Buscar productos" autocomplete="off" /></label>
        <div class="shop-tabs" role="group" aria-label="Categorías de productos"><button class:active={categoryFilter==='cervezas'} aria-pressed={categoryFilter==='cervezas'} onclick={()=>{categoryFilter='cervezas';shownCount=12;}}><img src={categoryPhoto('cervezas')} alt="" decoding="async" onerror={(event)=>{(event.currentTarget as HTMLImageElement).src=artworkFor('cervezas');}} /><span>CERVEZAS</span></button><button class:active={categoryFilter==='mecatos'} aria-pressed={categoryFilter==='mecatos'} onclick={()=>{categoryFilter='mecatos';shownCount=12;}}><img src={categoryPhoto('mecatos')} alt="" decoding="async" onerror={(event)=>{(event.currentTarget as HTMLImageElement).src=artworkFor('mecatos');}} /><span>MECATOS</span></button></div>
        {#key categoryFilter}<div class="product-grid" in:fade={{duration:160}}>{#if !visibleProducts.length}<div class="shop-empty"><Empty title={search ? 'No encontramos ese producto' : 'Aún no hay productos aquí'} detail={search ? 'Prueba con otro nombre.' : 'Consulta al personal por los productos disponibles.'} /></div>{/if}
          {#each displayedProducts as product, index (product.id)}<article class="shop-card" class:chosen={selection[product.id]>0} style={`--card-order:${Math.min(index,8)}`}><div class="shop-photo"><img src={product.photo_path && !failedPhotos[product.id] ? photoUrl(product.photo_path) : artworkFor(sectionFor(product))} alt={product.photo_path && !failedPhotos[product.id] ? product.name : `Ilustración de ${sectionFor(product)==='cervezas'?'cerveza':'mecato'}; foto del producto no disponible`} loading="lazy" decoding="async" onerror={()=>{failedPhotos={...failedPhotos,[product.id]:true};}} />{#if selection[product.id]>0}<span class="selected-mark" aria-label="Producto seleccionado">✓</span>{/if}</div><div class="shop-card-content"><h3>{product.name}</h3><strong>{money(product.price_cop)}</strong>{#if selection[product.id]>0}<div class="quantity-stepper" aria-label={`Cantidad de ${product.name}`}><button aria-label={`Quitar una unidad de ${product.name}`} disabled={!!busy} onclick={()=>quantity(product.id,-1)}>−</button>{#key selection[product.id]}<output aria-label={`Cantidad de ${product.name}`} class="quantity-value">{selection[product.id]}</output>{/key}<button aria-label={`Agregar una unidad de ${product.name}`} disabled={!!busy || selection[product.id]>=100} onclick={()=>quantity(product.id,1)}>+</button></div>{:else}<button class="add-product" disabled={!!busy} onclick={()=>quantity(product.id,1)} aria-label={`Agregar ${product.name}`}>Agregar <span aria-hidden="true">+</span></button>{/if}</div></article>{/each}
        </div>{/key}{#if visibleProducts.length>shownCount}<button class="ghost full load-more" onclick={()=>shownCount+=12}>Ver más productos</button>{/if}
      </section>
      {#if selectedCount>0}<div class="order-bar"><button class="order-open" aria-expanded={showOrder} onclick={()=>showOrder=!showOrder}><span class="order-counter" aria-live="polite">{#key selectedCount}<b>{selectedCount}</b>{/key} {selectedCount===1?'producto':'productos'} en tu pedido</span><strong>{showOrder?'Cerrar':'Revisar pedido'} ↑</strong></button>{#if showOrder}<div class="order-panel" transition:fly={{y:8,duration:200}}><h2>Tu pedido</h2>{#each selectedProducts as product}<div class="order-line"><span>{selection[product.id]} × {product.name}</span><strong>{money(selection[product.id]*product.price_cop)}</strong></div>{/each}<p>Precios de referencia. Tu checa aumenta cuando se entregan los productos.</p><button class="full" disabled={!!busy} onclick={()=>void sendOrder()}>{busy==='order'?'Enviando…':'Confirmar pedido'}</button></div>{/if}</div>{/if}
    {/if}
    <div class="customer-details"><section id="mis-pedidos"><div class="section-head"><h2>Mis pedidos</h2></div><div class="list">{#if !orders.length}<Empty title="Sin pedidos todavía" />{/if}{#each orders as order}<div class="list-row order-history"><div class="order-history-head"><span class="muted">{dateTime(order.created_at)}</span><span class="badge" data-status={order.status}>{orderState(order)}</span></div>{#each items.filter((item)=>item.order_id===order.id) as item}{@const orderProduct=products.find((product)=>product.id===item.product_id)}<div class="order-item">{#if orderProduct}<div class="order-item-photo"><img src={photoUrl(orderProduct.photo_path) || artworkFor(sectionFor(orderProduct))} alt="" loading="lazy" /></div>{/if}<div><p>{item.quantity} × {productName(item.product_id)}</p><span class="muted">{item.delivered_quantity} entregados</span><div class="progress-track"><span style={`width:${Math.min(100,item.delivered_quantity/item.quantity*100)}%`}></span></div></div></div>{/each}</div>{/each}</div></section>
    <section id="consumos"><div class="section-head"><h2>Mi cuenta</h2><Badge status={account.status} /></div><div class="list">{#if !deliveries.length}<Empty title="Aún no hay consumos" detail="Los pedidos pendientes no se suman al total." />{/if}{#each deliveries as delivery}<div class="list-row"><div><h3>{delivery.product_name}</h3><p class="muted">{delivery.quantity} × {money(delivery.unit_price_cop)}</p><p class="muted">Entregó {delivery.delivered_by} · {dateTime(delivery.delivered_at)}</p></div><strong>{money(delivery.quantity*delivery.unit_price_cop)}</strong></div>{/each}</div>
      <div class="customer-payment"><div class="payment-total"><span>Total confirmado</span><strong>{money(total)}</strong></div>{#if account.status==='open'}{#if confirmPayment}<div class="payment-confirm"><p>El personal revisará tu checa y confirmará el pago en persona.</p><div class="row-actions"><button disabled={!!busy} onclick={()=>void requestPayment()}>{busy==='payment'?'Enviando…':'Confirmar solicitud'}</button><button class="ghost" onclick={()=>confirmPayment=false}>Volver</button></div></div>{/if}{:else if account.status==='paying'}<p class="muted">Pago solicitado. Espera la confirmación del personal.</p>{:else}<p class="muted">Pago confirmado: {money(paid)}{account.closed_at ? ` · ${dateTime(account.closed_at)}` : ''}</p>{/if}</div>
    </section></div>
  {/if}
</div>
