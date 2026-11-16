<script lang="ts">
  import { onMount } from 'svelte';
  import { requireSupabase } from '$lib/supabase';
  import { money } from '$lib/format';
  import { friendlyError } from '$lib/errors';
  import Notice from '$lib/ui/Notice.svelte';
  import Empty from '$lib/ui/Empty.svelte';
  type Category = { id:string; name:string };
  type Product = { id:string; category_id:string; name:string; price_cop:number; active:boolean; photo_path:string|null };
  let categories = $state<Category[]>([]);
  let products = $state<Product[]>([]);
  let search = $state('');
  let filter = $state('');
  let categoryName = $state('');
  let categoryId = $state('');
  let productName = $state('');
  let price = $state<number|null>(null);
  let editing = $state<Product|null>(null);
  let active = $state(true);
  let photoFile = $state<File|null>(null);
  let busy = $state(false);
  let error = $state('');
  let success = $state('');
  let loading = $state(true);
  let visible = $derived(products.filter((product) =>
    (!filter || product.category_id===filter) && product.name.toLocaleLowerCase('es-CO').includes(search.trim().toLocaleLowerCase('es-CO'))
  ));

  async function load() {
    const db=requireSupabase();
    const [c,p]=await Promise.all([
      db.from('categories').select('id,name').order('name'),
      db.from('products').select('id,category_id,name,price_cop,active,photo_path').order('name').limit(300)
    ]);
    if (c.error || p.error) throw c.error ?? p.error;
    categories=c.data ?? []; products=p.data ?? []; loading=false;
  }
  async function action(operation:()=>Promise<void>,message:string) {
    if (busy) return;
    busy=true; error=''; success='';
    try { await operation(); await load(); success=message; }
    catch (cause) { error=friendlyError(cause); }
    finally { busy=false; }
  }
  function edit(product:Product) {
    editing=product; productName=product.name; categoryId=product.category_id;
    price=product.price_cop; active=product.active; photoFile=null;
    document.getElementById('product-form')?.scrollIntoView({behavior:'smooth'});
  }
  function clear() { editing=null; productName=''; price=null; active=true; photoFile=null; }
  const photoUrl=(path:string)=>requireSupabase().storage.from('product-photos').getPublicUrl(path).data.publicUrl;
  const artworkFor=(product:Product)=>/cerveza|beer|pola/i.test(`${categories.find((category)=>category.id===product.category_id)?.name ?? ''} ${product.name}`)?'/images/beer-placeholder.svg':'/images/snack-placeholder.svg';
  async function uploadPhoto() {
    if (!editing || !photoFile) return;
    const product=editing;
    const file=photoFile;
    await action(async()=>{
      if (!['image/jpeg','image/png','image/webp'].includes(file.type) || file.size>10485760) throw new Error('invalid photo');
      const bitmap=await createImageBitmap(file);
      const scale=Math.min(1,1000/Math.max(bitmap.width,bitmap.height));
      const canvas=document.createElement('canvas');
      canvas.width=Math.max(1,Math.round(bitmap.width*scale));canvas.height=Math.max(1,Math.round(bitmap.height*scale));
      const context=canvas.getContext('2d');
      if (!context) throw new Error('invalid photo');
      context.drawImage(bitmap,0,0,canvas.width,canvas.height);bitmap.close();
      const photo=await new Promise<Blob|null>((resolve)=>canvas.toBlob(resolve,'image/webp',.82));
      if (!photo || photo.size>2097152) throw new Error('invalid photo');
      const path=`${product.id}/${crypto.randomUUID()}.webp`;
      const storage=requireSupabase().storage.from('product-photos');
      const uploaded=await storage.upload(path,photo,{contentType:'image/webp',upsert:false});
      if (uploaded.error) throw uploaded.error;
      const saved=await requireSupabase().rpc('set_product_photo',{p_product:product.id,p_path:path});
      if (saved.error) { await storage.remove([path]); throw saved.error; }
      if (product.photo_path) await storage.remove([product.photo_path]);
      photoFile=null;
      editing={...product,photo_path:path};
    },'Fotografía actualizada.');
  }
  onMount(() => { void load().catch((cause)=>{error=friendlyError(cause);loading=false;}); });
</script>

<div class="page-head"><div><p class="eyebrow">Administración</p><h1>Catálogo</h1><p>Productos y precios disponibles para esta jornada.</p></div><a class="button ghost small" href="/admin">Volver al inicio</a></div>
<Notice message={error} /><Notice message={success} kind="success" />
<div class="grid catalog-editor-grid"><section class="card"><h2>Nueva categoría</h2>
  <form class="inline" onsubmit={(event)=>{event.preventDefault();void action(async()=>{const result=await requireSupabase().rpc('save_category',{p_name:categoryName.trim()});if(result.error)throw result.error;categoryId=result.data;categoryName='';},'Categoría guardada.');}}>
    <label>Nombre<input bind:value={categoryName} maxlength="100" required placeholder="Ej. Cervezas" /></label><button disabled={busy}>Guardar</button>
  </form>
</section><section class="card" id="product-form"><h2>{editing ? 'Editar producto' : 'Nuevo producto'}</h2>
  <form class="form-grid" onsubmit={(event)=>{event.preventDefault();void action(async()=>{
    if (!categoryId || price===null || !Number.isInteger(price) || price<0) throw new Error('invalid request');
    const result=editing
      ? await requireSupabase().rpc('update_product',{p_product:editing.id,p_category:categoryId,p_name:productName.trim(),p_price:price,p_active:active})
      : await requireSupabase().rpc('save_product',{p_category:categoryId,p_name:productName.trim(),p_price:price});
    if (result.error) throw result.error;
    clear();
  },editing ? 'Producto actualizado.' : 'Producto creado.');}}>
    <label>Categoría<select bind:value={categoryId} required><option value="">Seleccionar</option>{#each categories as category}<option value={category.id}>{category.name}</option>{/each}</select></label>
    <label>Nombre<input bind:value={productName} maxlength="100" required /></label>
    <label>Precio en COP<input type="number" bind:value={price} min="0" step="1" required /></label>
    {#if editing}<label class="checkbox"><input type="checkbox" bind:checked={active} /> Disponible para pedidos</label>{/if}
    <div class="row-actions"><button disabled={busy || !categoryId}>{busy ? 'Guardando…' : editing ? 'Guardar cambios' : 'Crear producto'}</button>{#if editing}<button type="button" class="ghost" onclick={clear}>Cancelar edición</button>{/if}</div>
  </form>
  {#if editing}<div class="catalog-photo-editor"><h3>Fotografía del producto</h3><div class="catalog-photo-row"><div class="catalog-thumb"><img src={editing.photo_path?photoUrl(editing.photo_path):artworkFor(editing)} alt={editing.photo_path?editing.name:'Ilustración: producto sin fotografía'} /></div><div class="catalog-photo-fields"><label>Seleccionar foto<input type="file" accept="image/jpeg,image/png,image/webp" onchange={(event)=>photoFile=event.currentTarget.files?.[0] ?? null} /></label><p class="muted">{editing.photo_path?'Fotografía asignada.':'Sin fotografía real.'} La imagen se ajusta a 1000 px y se guarda en WebP.</p><button disabled={busy || !photoFile} onclick={()=>void uploadPhoto()}>{busy?'Subiendo…':'Guardar fotografía'}</button></div></div></div>{/if}
</section></div>
<section><div class="section-head"><h2>Productos</h2><span class="muted">{visible.length} encontrados</span></div>
  <div class="inline" style="margin-bottom:1rem"><label>Buscar<input bind:value={search} placeholder="Nombre del producto" /></label><label>Categoría<select bind:value={filter}><option value="">Todas</option>{#each categories as category}<option value={category.id}>{category.name}</option>{/each}</select></label></div>
  {#if loading}<p role="status" class="muted">Cargando catálogo…</p>{:else}<div class="list">{#if !visible.length}<Empty title="Sin productos" detail="Crea uno o cambia el filtro de búsqueda." />{/if}
    {#each visible as product}<div class="list-row"><div class="catalog-product"><div class="catalog-thumb"><img src={product.photo_path?photoUrl(product.photo_path):artworkFor(product)} alt={product.photo_path?product.name:'Ilustración: producto sin fotografía'} loading="lazy" /></div><div><h3>{product.name}</h3><p class="muted">{categories.find((category)=>category.id===product.category_id)?.name ?? 'Categoría'} · {product.active ? 'Disponible' : 'No disponible'}</p></div></div><div style="text-align:right"><strong>{money(product.price_cop)}</strong><div><button class="ghost small" onclick={()=>edit(product)}>Editar</button></div></div></div>{/each}</div>{/if}
</section>
