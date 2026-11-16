import { test, expect } from '@playwright/test';
import { execFileSync } from 'node:child_process';
import { randomBytes, randomUUID } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';

test.use({actionTimeout:10_000});
test('empleado, cliente y administrador operan una checa',async({browser})=>{
  test.setTimeout(180_000);
  const status=JSON.parse(execFileSync('npx',['--no-install','supabase','status','--output','json'],{encoding:'utf8'}));
  expect(status.API_URL).toBe('http://127.0.0.1:54321');
  expect(status.DB_URL).toMatch(/@127\.0\.0\.1:54322\//);
  const root=createClient(status.API_URL,status.SERVICE_ROLE_KEY,{auth:{persistSession:false}});
  const adminApi=createClient(status.API_URL,status.PUBLISHABLE_KEY,{auth:{persistSession:false}});
  const password=randomBytes(24).toString('base64url');
  async function makeUser(label:string){
    const email=`${label}-${randomUUID()}@tiendapp.test`;
    const result=await root.auth.admin.createUser({email,password,email_confirm:true});
    if(result.error || !result.data.user)throw result.error ?? new Error('Auth user missing');
    return {email,id:result.data.user.id};
  }
  const adminUser=await makeUser('frontend-admin');
  const employeeUser=await makeUser('frontend-employee');
  execFileSync('docker',['exec','-i','supabase_db_tiendapp','psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-c',
    `insert into public.staff(user_id,role,display_name) values ('${adminUser.id}','admin','Administrador navegador')`],{stdio:'pipe'});
  expect((await adminApi.auth.signInWithPassword({email:adminUser.email,password})).error).toBeNull();
  const category=await adminApi.rpc('save_category',{p_name:`Mecatos ${randomUUID().slice(0,6)}`});
  expect(category.error).toBeNull();
  const productName=`Mecato ${randomUUID().slice(0,6)}`;
  const product=await adminApi.rpc('save_product',{p_category:category.data,p_name:productName,p_price:4500});
  expect(product.error).toBeNull();
  expect((await adminApi.rpc('start_shift')).error).toBeNull();

  const admin=await browser.newContext({viewport:{width:390,height:844}});
  const employee=await browser.newContext({viewport:{width:390,height:844}});
  const customer=await browser.newContext({viewport:{width:390,height:844}});
  const a=await admin.newPage();const e=await employee.newPage();const c=await customer.newPage();
  const errors:string[]=[];
  for(const [label,page] of [['admin',a],['empleado',e],['cliente',c]] as const){
    page.on('pageerror',(error)=>errors.push(`${label}: ${error.message}`));
    page.on('console',(message)=>{if(message.type()==='error')errors.push(`${label} consola: ${message.text()}`);});
    page.on('dialog',(dialog)=>void dialog.accept());
  }
  const base='http://127.0.0.1:5173';
  await a.goto(`${base}/admin/login`);
  await a.getByRole('textbox',{name:'Correo electrónico'}).fill(adminUser.email);
  await a.getByLabel('Contraseña').fill(password);
  await a.getByRole('button',{name:'Ingresar'}).click();
  await expect(a.getByRole('heading',{name:'Lo que necesita atención'})).toBeVisible();
  await a.goto(`${base}/admin/personal`);
  await a.getByLabel('UUID del usuario Auth').fill(employeeUser.id);
  await a.getByLabel('Nombre visible').fill('Empleado navegador');
  await a.getByRole('button',{name:'Activar empleado'}).click();
  await expect(a.getByText('Empleado activo.')).toBeVisible();
  await expect(a.getByRole('heading',{name:'Empleado navegador'}).first()).toBeVisible();
  await a.goto(`${base}/admin/jornadas`);
  await expect(a.getByRole('heading',{name:'Jornada actual'})).toBeVisible();

  await e.goto(`${base}/empleado`);
  await expect(e).toHaveURL(/\/admin\/login$/);
  await e.getByRole('textbox',{name:'Correo electrónico'}).fill(employeeUser.email);
  await e.getByLabel('Contraseña').fill(password);
  await e.getByRole('button',{name:'Ingresar'}).click();
  await expect(e.getByRole('heading',{name:'Lo que necesita atención'})).toBeVisible();
  await expect(e.locator('#pedidos')).toBeVisible();
  await e.screenshot({path:'/tmp/tiendapp-empleado-inicio.png',fullPage:true,animations:'disabled'});
  await e.setViewportSize({width:1440,height:900});
  await e.screenshot({path:'/tmp/tiendapp-empleado-dashboard.png',fullPage:true,animations:'disabled'});
  await e.setViewportSize({width:390,height:844});
  await e.goto(`${base}/admin/personal`);
  await expect(e).toHaveURL(/\/admin\/login$/);
  await e.goto(`${base}/empleado/clientes`);
  const guestName=`Mesa ${randomUUID().slice(0,6)}`;
  await e.getByRole('checkbox',{name:'Cuenta de invitado sin registro'}).check();
  await e.getByLabel('Nombre del invitado').fill(guestName);
  await e.getByRole('button',{name:'Abrir cuenta',exact:true}).click();
  await expect(e).toHaveURL(/\/empleado\/cuentas\/[0-9a-f-]+$/);
  const accountUrl=e.url();
  await expect(e.getByRole('heading',{name:guestName})).toBeVisible();
  await e.getByLabel('Buscar producto').fill(productName);
  await e.locator('.product-choice').filter({hasText:productName}).click();
  await e.getByLabel('Cantidad',{exact:true}).fill('2');
  await e.getByRole('button',{name:'Registrar entrega'}).click();
  await expect(e.locator('.metric')).toContainText('9.000');
  await e.screenshot({path:'/tmp/tiendapp-empleado.png',fullPage:true});
  await e.getByRole('button',{name:'Generar código temporal'}).click();
  const code=(await e.locator('.code').textContent())?.trim();
  expect(code).toMatch(/^[0-9A-F]{18}$/);

  await c.goto(`${base}/vincular`);
  await c.getByLabel('Código de 18 caracteres').fill(code!);
  await c.getByRole('button',{name:'Continuar'}).click();
  await expect(c.getByRole('heading',{name:`Hola, ${guestName}`})).toBeVisible();
  await expect(c.locator('.metric')).toContainText('9.000');
  await c.getByRole('button',{name:'MECATOS'}).click();
  await c.getByRole('searchbox',{name:'Buscar productos'}).fill(productName);
  await expect(c.locator('.shop-card').filter({hasText:productName}).getByRole('img',{name:/foto del producto no disponible/})).toHaveAttribute('src','/images/snack-placeholder.svg');
  expect(await c.locator('.shop-card img').first().evaluate((img)=>(img as HTMLImageElement).naturalWidth)).toBeGreaterThan(0);
  await c.screenshot({path:'/tmp/tiendapp-cliente-catalogo.png',fullPage:true,animations:'disabled'});
  await c.setViewportSize({width:1440,height:900});
  await c.screenshot({path:'/tmp/tiendapp-cliente-catalogo-escritorio.png',fullPage:true,animations:'disabled'});
  await c.setViewportSize({width:390,height:844});
  await c.reload();
  await expect(c.locator('.metric')).toContainText('9.000');
  await customer.setOffline(true);
  await expect(c.getByText('Sin conexión. Comprueba tu red antes de registrar operaciones.')).toBeVisible();

  await a.goto(accountUrl.replace('/empleado/','/admin/'));
  await a.getByRole('button',{name:'Corregir'}).click();
  await a.getByLabel('Unidades a ajustar').fill('-1');
  await a.getByLabel('Motivo').fill('Una unidad no fue entregada');
  await a.getByRole('button',{name:'Confirmar corrección'}).click();
  await customer.setOffline(false);
  await expect(c.locator('.metric')).toContainText('4.500');
  await c.getByRole('button',{name:'Solicitar pagar'}).click();
  await c.getByRole('button',{name:'Confirmar solicitud'}).click();
  await e.goto(`${base}/empleado`);
  await expect(e.locator('#pagos')).toContainText(guestName);
  await e.goto(accountUrl);
  await e.getByLabel('Medio de pago').selectOption('cash');
  await e.getByRole('button',{name:'Confirmar cobro y cerrar'}).click();
  await expect(e.getByText('Cuenta cerrada.')).toBeVisible();
  await expect(c.getByText('Pago confirmado:',{exact:false})).toBeVisible();
  await e.goto(`${base}/empleado/historial`);
  await expect(e.getByText(guestName)).toBeVisible();
  await a.goto(`${base}/admin/informes`);
  await a.getByRole('button',{name:'Consultar informe'}).click();
  await expect(a.getByRole('heading',{name:'Productos consumidos'})).toBeVisible();
  await a.screenshot({path:'/tmp/tiendapp-admin-informes.png',fullPage:true});
  await a.goto(`${base}/admin/auditoria`);
  await a.getByRole('button',{name:'Consultar'}).click();
  await expect(a.getByText('Consumo corregido').first()).toBeVisible();

  for(const [width,height] of [[320,568],[375,812],[390,844],[430,932],[768,1024],[1024,768],[1440,900],[1920,1080]]){
    for(const page of [a,e,c]){await page.setViewportSize({width,height});
      expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),`overflow at ${width}`).toBe(true);}
    if(width===1440){await e.screenshot({path:'/tmp/tiendapp-empleado-escritorio.png',fullPage:true});await c.screenshot({path:'/tmp/tiendapp-cliente-escritorio.png',fullPage:true});}
  }
  await e.goto(`${base}/empleado`);
  await e.getByRole('button',{name:'Cerrar sesión'}).click();
  await expect(e).toHaveURL(/\/admin\/login$/);
  await e.getByRole('textbox',{name:'Correo electrónico'}).fill(employeeUser.email);
  await e.getByLabel('Contraseña').fill(password);
  await e.getByRole('button',{name:'Ingresar'}).click();
  await expect(e.getByRole('heading',{name:'Lo que necesita atención'})).toBeVisible();
  await a.goto(`${base}/admin/personal`);
  await a.locator('.list-row').filter({hasText:employeeUser.id}).getByRole('button',{name:'Desactivar'}).click();
  await expect(a.getByText('Empleado desactivado.')).toBeVisible();
  await e.reload();
  await expect(e).toHaveURL(/\/admin\/login$/);
  expect(errors.filter((error)=>!error.includes('401 (Unauthorized)'))).toEqual([]);
  await Promise.all([admin.close(),employee.close(),customer.close()]);
});
