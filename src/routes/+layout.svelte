<script lang="ts">
  import '../app.css';
  import { onMount } from 'svelte';
  import { page } from '$app/state';
  import NavIcon from '$lib/ui/NavIcon.svelte';
  let { children } = $props();
  let path = $derived(page.url.pathname);
  let hash = $derived(page.url.hash);
  let admin = $derived(path.startsWith('/admin'));
  let employee = $derived(path.startsWith('/empleado'));
  let staff = $derived(admin || employee);
  let showNav = $derived(path === '/mi-cuenta' || (staff && !path.endsWith('/login')));
  let online=$state(true);
  const adminLinks=[
    {href:'/admin',label:'Inicio'}, {href:'/admin/clientes',label:'Abrir checa'},
    {href:'/admin/historial',label:'Historial'}, {href:'/admin/jornadas',label:'Jornadas'},
    {href:'/admin/personal',label:'Personal'}, {href:'/admin/catalogo',label:'Catálogo'},
    {href:'/admin/informes',label:'Informes'}, {href:'/admin/auditoria',label:'Auditoría'}
  ];
  const employeeLinks=[
    {href:'/empleado',label:'Inicio'}, {href:'/empleado/clientes',label:'Abrir checa'},
    {href:'/empleado/historial',label:'Historial'}
  ];
  let sideLinks=$derived(admin?adminLinks:employeeLinks);
  let bottomLinks=$derived(admin?
    [{href:'/admin',label:'Inicio',icon:'home' as const},{href:'/admin/clientes',label:'Checas',icon:'account' as const},{href:'/admin/historial',label:'Historial',icon:'history' as const},{href:'/admin/gestion',label:'Gestión',icon:'manage' as const}]
    :[{href:'/empleado',label:'Inicio',icon:'home' as const},{href:'/empleado/clientes',label:'Abrir checa',icon:'account' as const},{href:'/empleado/historial',label:'Historial',icon:'history' as const}]);
  onMount(()=>{
    const update=()=>online=navigator.onLine;
    update();window.addEventListener('online',update);window.addEventListener('offline',update);
    return ()=>{window.removeEventListener('online',update);window.removeEventListener('offline',update);};
  });
</script>

<header class="topbar"><div class="topbar-inner"><a class="brand" href="/">TiendApp<span aria-hidden="true">.</span></a>{#if staff && showNav}<span class="header-context">{admin?'Administración':'Operación'}</span>{/if}{#if !staff && showNav}<nav class="topnav" aria-label="Navegación principal"><a href="/mi-cuenta#inicio" aria-current={path==='/mi-cuenta' && (!hash || hash==='#inicio')?'page':undefined}>Inicio</a><a href="/mi-cuenta#mis-pedidos" aria-current={hash==='#mis-pedidos'?'page':undefined}>Pedidos</a><a href="/mi-cuenta#consumos" aria-current={hash==='#consumos'?'page':undefined}>Mi cuenta</a></nav>{/if}</div></header>
{#if !online}<div class="offline-banner" role="status">Sin conexión. Comprueba tu red antes de registrar operaciones.</div>{/if}
<div class:staff-shell={staff && showNav}>
  {#if staff && showNav}<aside class="side-nav" aria-label="Navegación principal"><nav>{#each sideLinks as link}<a href={link.href} aria-current={path===link.href?'page':undefined}>{link.label}</a>{/each}</nav></aside>{/if}
  <main>{@render children()}</main>
</div>
{#if showNav}<nav class="bottom-nav" aria-label="Navegación móvil">
  {#if staff}{#each bottomLinks as link}<a href={link.href} aria-current={path===link.href?'page':undefined}><NavIcon name={link.icon} />{link.label}</a>{/each}
  {:else}<a href="/mi-cuenta#inicio" aria-current={path==='/mi-cuenta' && (!hash || hash==='#inicio')?'page':undefined}><NavIcon name="home" />Inicio</a><a href="/mi-cuenta#mis-pedidos" aria-current={hash==='#mis-pedidos'?'page':undefined}><NavIcon name="orders" />Pedidos</a><a href="/mi-cuenta#consumos" aria-current={hash==='#consumos'?'page':undefined}><NavIcon name="account" />Mi cuenta</a>{/if}
</nav>{/if}
