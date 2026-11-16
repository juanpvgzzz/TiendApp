<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { requireSupabase } from '$lib/supabase';
  import { friendlyError } from '$lib/errors';
  import Notice from '$lib/ui/Notice.svelte';
  import Empty from '$lib/ui/Empty.svelte';
  let { basePath, canStartShift = false }: { basePath: '/admin' | '/empleado'; canStartShift?: boolean } = $props();
  type Customer = { id:string; name:string; phone:string|null };
  let query = $state('');
  let matches = $state<Customer[]>([]);
  let recent = $state<Customer[]>([]);
  let selected = $state<Customer|null>(null);
  let newName = $state('');
  let phone = $state('');
  let guest = $state(false);
  let shiftId = $state('');
  let busy = $state(false);
  let error = $state('');
  let success = $state('');
  let openingKey = $state(crypto.randomUUID());
  let loading = $state(true);

  async function load() {
    const db = requireSupabase();
    const [c,s] = await Promise.all([
      db.from('customers').select('id,name,phone').order('created_at',{ascending:false}).limit(20),
      db.from('shifts').select('id').is('closed_at',null).limit(1)
    ]);
    if (c.error || s.error) throw c.error ?? s.error;
    recent = c.data ?? []; shiftId = s.data?.[0]?.id ?? ''; loading=false;
  }
  async function search() {
    error = '';
    if (query.trim().length < 2) { matches=[]; return; }
    const { data, error: searchError } = await requireSupabase().rpc('search_customers',{p_query:query.trim(),p_limit:20});
    if (searchError) { error=friendlyError(searchError); return; }
    matches=data ?? [];
  }
  async function register() {
    if (busy) return;
    busy=true; error=''; success='';
    try {
      const normalized=newName.trim().toLocaleLowerCase('es-CO');
      if (normalized.length<2) throw new Error('invalid request');
      const { data: possible }=await requireSupabase().rpc('search_customers',{p_query:newName.trim(),p_limit:20});
      if (possible?.some((person:{name:string})=>person.name.trim().toLocaleLowerCase('es-CO')===normalized) && !confirm('Ya hay un cliente con este nombre. ¿Registrar otra persona?')) return;
      const { data, error: saveError }=await requireSupabase().rpc('register_customer',{p_name:newName.trim(),p_phone:phone.trim() || null});
      if (saveError) throw saveError;
      selected={id:data,name:newName.trim(),phone:phone.trim() || null};
      newName=''; phone=''; guest=false; success='Cliente registrado. Ahora puedes abrir su cuenta.';
      await load();
    } catch (cause) { error=friendlyError(cause); }
    finally { busy=false; }
  }
  async function openAccount() {
    if (busy) return;
    busy=true; error='';
    try {
      if (!shiftId) throw new Error('No hay jornada abierta.');
      if (!selected && !guest) throw new Error('Selecciona o registra un cliente.');
      const { data, error: openError }=await requireSupabase().rpc('open_account',{
        p_shift:shiftId,p_customer:guest ? null : selected?.id,p_guest:guest ? newName.trim() : null,p_key:openingKey
      });
      if (openError) throw openError;
      await goto(`${basePath}/cuentas/${data}`);
      openingKey=crypto.randomUUID();
    } catch (cause) { error=friendlyError(cause); }
    finally { busy=false; }
  }
  onMount(() => { void load().catch((cause)=>{error=friendlyError(cause);loading=false;}); });
</script>

<div class="page-head"><div><p class="eyebrow">Clientes</p><h1>Abre una cuenta</h1><p>Busca a alguien que ya nos visita o registra una persona nueva.</p></div><a class="button ghost small" href={basePath}>Volver al inicio</a></div>
<Notice message={error} /><Notice message={success} kind="success" />
{#if loading}<p role="status" class="muted">Cargando clientes y jornada…</p>{:else if !shiftId}<div class="card"><h2>Inicia la jornada</h2><p class="muted">{canStartShift ? 'Abre la jornada antes de crear cuentas.' : 'Pide al administrador que abra la jornada.'}</p>{#if canStartShift}<button disabled={busy} onclick={async()=>{busy=true;try{const result=await requireSupabase().rpc('start_shift');if(result.error)throw result.error;shiftId=result.data;}catch(cause){error=friendlyError(cause);}finally{busy=false;}}}>Abrir jornada</button>{/if}</div>{/if}
<div class="grid"><section class="card"><h2>Cliente recurrente</h2>
  <form class="inline" onsubmit={(event)=>{event.preventDefault();void search();}}><label>Buscar por nombre<input bind:value={query} placeholder="Ej. Juancho" minlength="2" /></label><button type="submit" class="secondary">Buscar</button></form>
  <div class="list" style="margin-top:1rem">{#if query && matches.length===0}<Empty title="Sin coincidencias" detail="Prueba otro nombre o registra una persona nueva." />{/if}
    {#each (query ? matches : recent) as person}<button class="list-row ghost full" style="border:0;border-top:1px solid var(--line);border-radius:0;justify-content:space-between;text-align:left" onclick={()=>{selected=person;guest=false;newName='';}}><span><strong>{person.name}</strong>{#if person.phone}<small class="muted"> · {person.phone}</small>{/if}</span><span>{selected?.id===person.id ? 'Seleccionado ✓' : 'Elegir'}</span></button>{/each}</div>
</section><section class="card"><h2>Persona nueva o invitado</h2>
  <label class="checkbox"><input type="checkbox" bind:checked={guest} onchange={()=>{selected=null;}} /> Cuenta de invitado sin registro</label>
  <form class="stack" onsubmit={(event)=>{event.preventDefault();if(!guest)void register();}}><label>{guest ? 'Nombre del invitado' : 'Nombre del cliente'}<input bind:value={newName} maxlength="120" required placeholder="Nombre o alias" /></label>
    {#if !guest}<label>Teléfono <span class="muted">(opcional)</span><input type="tel" bind:value={phone} autocomplete="tel" /></label><button class="secondary" type="submit" disabled={busy}>Registrar cliente</button>{/if}
  </form>
  <hr class="divider" />
  <p class="muted">{guest ? `Invitado: ${newName || 'sin nombre'}` : selected ? `Seleccionado: ${selected.name}` : 'Selecciona un cliente para continuar.'}</p>
  <button class="full" disabled={busy || !shiftId || (!selected && (!guest || !newName.trim()))} onclick={()=>void openAccount()}>{busy ? 'Guardando…' : 'Abrir cuenta'}</button>
</section></div>
