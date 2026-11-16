import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { randomBytes, randomUUID } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';

const status = JSON.parse(execFileSync('npx', ['--no-install','supabase','status','--output','json'], { encoding:'utf8' }));
assert.equal(status.API_URL, 'http://127.0.0.1:54321');
assert.match(status.DB_URL, /@127\.0\.0\.1:54322\//);
const root = createClient(status.API_URL,status.SERVICE_ROLE_KEY,{auth:{persistSession:false}});
const client = () => createClient(status.API_URL,status.PUBLISHABLE_KEY,{auth:{persistSession:false}});
const admin = client();
const employee = client();
const customer = client();
const outsider = client();
const password = randomBytes(24).toString('base64url');
async function user(label) {
  const email = `${label}-${randomUUID()}@tiendapp.test`;
  const result = await root.auth.admin.createUser({email,password,email_confirm:true});
  if (result.error || !result.data.user) throw result.error ?? new Error('Auth user missing');
  return {email,id:result.data.user.id};
}
async function rpc(db,name,args={}) {
  const result = await db.rpc(name,args);
  if (result.error) throw new Error(`${name}: ${result.error.message}`);
  return result.data;
}
async function rejects(task,label) {
  await assert.rejects(task,label);
}
const adminUser = await user('admin');
const staffUser = await user('employee');
const sql = (query) => execFileSync('docker',['exec','-i','supabase_db_tiendapp','psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-Atc',query],{encoding:'utf8'}).trim();
sql(`insert into public.staff(user_id,role,display_name) values ('${adminUser.id}','admin','Admin test')`);
assert.equal((await admin.auth.signInWithPassword({email:adminUser.email,password})).error,null);
assert.equal((await employee.auth.signInWithPassword({email:staffUser.email,password})).error,null);
assert.equal((await customer.auth.signInAnonymously()).error,null);
assert.equal((await outsider.auth.signInAnonymously()).error,null);
await rejects(() => rpc(employee,'set_employee',{p_user:staffUser.id,p_name:'Empleado test',p_active:true}),'employee cannot grant role');
await rpc(admin,'set_employee',{p_user:staffUser.id,p_name:'Empleado test',p_active:true});
const shift = await rpc(admin,'start_shift');
await rejects(() => rpc(employee,'start_shift'),'employee cannot open shift');
const phone = `3${randomBytes(5).toString('hex').replaceAll(/[a-f]/g,'1').slice(0,9)}`;
const customerId = await rpc(employee,'register_customer',{p_name:'Nombre repetido',p_phone:phone});
await rejects(() => rpc(employee,'register_customer',{p_name:'Otro nombre',p_phone:phone}),'duplicate phone blocked');
const sameName = await rpc(employee,'register_customer',{p_name:'Nombre repetido',p_phone:null});
assert.notEqual(sameName,customerId);
const searched = await rpc(employee,'search_customers',{p_query:'Nombre repetido'});
assert.ok(searched.some((row) => row.id===customerId));
const category = await rpc(admin,'save_category',{p_name:`Prueba ${randomUUID()}`});
const product = await rpc(admin,'save_product',{p_category:category,p_name:'Refresco',p_price:4000});
await rejects(() => rpc(employee,'save_product',{p_category:category,p_name:'Intruso',p_price:1}),'employee cannot edit catalog');
const account = await rpc(employee,'open_account',{p_shift:shift,p_customer:customerId,p_guest:null,p_key:randomUUID()});
await rejects(() => rpc(admin,'open_account',{p_shift:shift,p_customer:customerId,p_guest:null,p_key:randomUUID()}),'two active accounts blocked');
await rejects(() => rpc(admin,'close_shift',{p_shift:shift}),'active account blocks shift closure');
const revoked = await rpc(employee,'create_link_code',{p_account:account});
await rpc(employee,'revoke_link_codes',{p_account:account});
assert.equal(await rpc(customer,'link_account',{p_code:revoked}),null);
const code = await rpc(employee,'create_link_code',{p_account:account});
assert.equal(await rpc(customer,'link_account',{p_code:code}),account);
assert.equal(await rpc(outsider,'link_account',{p_code:code}),null);
for (let attempt=0;attempt<6;attempt++) {
  assert.equal(await rpc(outsider,'link_account',{p_code:'FFFFFFFFFFFFFFFFFF'}),null);
}
assert.deepEqual((await outsider.from('accounts').select('id').eq('id',account)).data,[]);
await rejects(() => rpc(outsider,'account_summary',{p_account:account}),'IDOR blocked');
await rejects(() => rpc(customer,'audit_history'),'customer audit blocked');
const order = await rpc(customer,'create_order',{p_account:account,p_items:[{product_id:product,quantity:2}],p_key:randomUUID()});
const item = (await employee.from('order_items').select('id').eq('order_id',order).single()).data.id;
await rpc(employee,'take_order',{p_order:order});
const delivery = await rpc(employee,'confirm_delivery',{p_item:item,p_quantity:1,p_key:randomUUID()});
await rejects(() => rpc(admin,'correct_delivery',{p_delivery:delivery,p_delta:2,p_reason:'Cantidad excesiva',p_key:randomUUID()}),'correction cannot exceed ordered quantity');
let eventResolve;
const event = new Promise((resolve) => {eventResolve=resolve;});
const channel = customer.channel(`correction-${randomUUID()}`)
  .on('postgres_changes',{event:'INSERT',schema:'public',table:'account_events',filter:`account_id=eq.${account}`},
    (payload) => eventResolve(payload.new.kind));
await new Promise((resolve,reject) => channel.subscribe((state) => {
  if (state==='SUBSCRIBED') resolve();
  if (state==='CHANNEL_ERROR' || state==='TIMED_OUT') reject(new Error(state));
}));
const correctionKey = randomUUID();
await rejects(() => rpc(employee,'correct_delivery',{p_delivery:delivery,p_delta:-1,p_reason:'Error de entrega',p_key:correctionKey}),'correction admin only');
const correction = await rpc(admin,'correct_delivery',{p_delivery:delivery,p_delta:-1,p_reason:'Error de entrega',p_key:correctionKey});
assert.equal(await rpc(admin,'correct_delivery',{p_delivery:delivery,p_delta:-1,p_reason:'Error de entrega',p_key:correctionKey}),correction);
await rejects(() => rpc(admin,'correct_delivery',{p_delivery:delivery,p_delta:1,p_reason:'Error de entrega',p_key:correctionKey}),'correction key reuse blocked');
assert.equal(await Promise.race([event,new Promise((_,reject)=>setTimeout(()=>reject(new Error('Realtime timeout')),15000))]),'consumption_corrected');
await customer.removeChannel(channel);
assert.equal((await rpc(customer,'account_summary',{p_account:account})).total_cop,0);
await rpc(employee,'cancel_order',{p_order:order,p_key:randomUUID()});
const direct = await rpc(employee,'record_direct_delivery',{p_account:account,p_product:product,p_quantity:1,p_key:randomUUID()});
assert.equal((await rpc(customer,'account_summary',{p_account:account})).total_cop,4000,'state recovered after channel disconnect');
await rpc(admin,'save_product',{p_category:category,p_name:'Refresco',p_price:5000});
const details = await rpc(customer,'account_delivery_details',{p_account:account});
assert.equal(details.find((row)=>row.id===direct).unit_price_cop,4000);
const request = await rpc(customer,'request_payment',{p_account:account});
assert.equal(await rpc(customer,'request_payment',{p_account:account}),request);
const recovered = client();
assert.equal((await recovered.auth.signInAnonymously()).error,null);
const recoveryCode = await rpc(employee,'create_link_code',{p_account:account});
assert.equal(await rpc(recovered,'link_account',{p_code:recoveryCode}),account);
assert.equal((await rpc(recovered,'account_summary',{p_account:account})).status,'paying');
await rejects(() => rpc(customer,'create_order',{p_account:account,p_items:[{product_id:product,quantity:1}],p_key:randomUUID()}),'paying account blocks orders');
await rpc(employee,'take_payment_request',{p_request:request});
assert.equal(await rpc(employee,'confirm_payment',{p_account:account,p_method:'transfer'}),4000);
await rejects(() => rpc(employee,'confirm_payment',{p_account:account,p_method:'transfer'}),'single payment');
await rejects(() => rpc(admin,'correct_delivery',{p_delivery:direct,p_delta:1,p_reason:'Cambio posterior',p_key:randomUUID()}),'closed immutable');
const history = await rpc(admin,'account_history',{p_customer:customerId});
assert.equal(history[0].account_id,account);
assert.equal(history[0].paid_cop,4000);
assert.ok((await rpc(admin,'account_history',{p_shift:shift})).some((row)=>row.account_id===account));
const report = await rpc(admin,'basic_report',{p_from:'2020-01-01T00:00:00Z',p_to:'2100-01-01T00:00:00Z'});
assert.ok(report.total_cop>=4000);
assert.ok(report.methods.transfer>=4000);
const audit = await rpc(admin,'audit_history',{p_limit:100});
assert.ok(audit.some((row)=>row.action==='delivery_corrected' && row.entity_id===delivery));
assert.ok(audit.some((row)=>row.action==='employee_changed' && row.entity_id===staffUser.id));
const midnight = sql(`begin; update public.shifts set opened_at=now()-interval '2 days' where id='${shift}'; set local role authenticated; select set_config('request.jwt.claim.sub','${adminUser.id}',true); select public.open_account('${shift}',null,'Mesa madrugada',gen_random_uuid()); rollback;`);
assert.match(midnight,/Mesa madrugada|[0-9a-f]{8}-[0-9a-f]{4}/);
const closedShift = sql(`begin; update public.accounts set status='closed',closed_at=now() where shift_id='${shift}' and status<>'closed'; set local role authenticated; select set_config('request.jwt.claim.sub','${adminUser.id}',true); select public.close_shift('${shift}'); select closed_at is not null from public.shifts where id='${shift}'; rollback;`);
assert.match(closedShift,/\nt\n/);
await rpc(admin,'set_employee',{p_user:staffUser.id,p_name:'Empleado test',p_active:false});
await rejects(() => rpc(employee,'open_account',{p_shift:shift,p_customer:null,p_guest:'Inactivo',p_key:randomUUID()}),'inactive employee blocked');
console.log(JSON.stringify({passed:true,account,checks:['roles','customers','shift','link revocation','RLS','orders','delivery','correction Realtime','historical price','payment','history','report','audit']}));
await Promise.all([admin.removeAllChannels(),employee.removeAllChannels(),customer.removeAllChannels(),outsider.removeAllChannels(),recovered.removeAllChannels()]);
process.exit(0);
