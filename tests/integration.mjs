import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { randomBytes, randomUUID } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';

const status = JSON.parse(execFileSync('npx', ['--no-install', 'supabase', 'status', '--output', 'json'], { encoding: 'utf8' }));
assert.equal(status.API_URL, 'http://127.0.0.1:54321', 'Integration only runs against local Supabase');
assert.match(status.DB_URL, /@127\.0\.0\.1:54322\//);
const sql = (query) => execFileSync('docker', ['exec', '-i', 'supabase_db_tiendapp', 'psql', '-U', 'postgres', '-d', 'postgres', '-Atc', query], { encoding: 'utf8' }).trim();
const root = createClient(status.API_URL, status.SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const makeClient = () => createClient(status.API_URL, status.PUBLISHABLE_KEY, { auth: { persistSession: false } });
const admin = makeClient();
const customer = makeClient();
const outsider = makeClient();
const email = `admin-${randomUUID()}@tiendapp.test`;
const password = randomBytes(24).toString('base64url');
const created = await root.auth.admin.createUser({ email, password, email_confirm: true });
if (created.error || !created.data.user) throw created.error ?? new Error('Auth user missing');
const adminId = created.data.user.id;
assert.match(adminId, /^[0-9a-f-]{36}$/);
sql(`insert into public.staff(user_id,role,display_name) values ('${adminId}','admin','Administrador de prueba')`);

async function rpc(client, name, args) {
  const result = await client.rpc(name, args);
  if (result.error) throw new Error(`${name}: ${result.error.message}`);
  return result.data;
}
async function fails(task, label) {
  let failed = false;
  try { await task(); } catch { failed = true; }
  assert.equal(failed, true, label);
}
const auth = await admin.auth.signInWithPassword({ email, password });
assert.equal(auth.error, null);
const categoryId = await rpc(admin, 'save_category', { p_name: `Bebidas ${randomUUID().slice(0,8)}` });
const productId = await rpc(admin, 'save_product', { p_category: categoryId, p_name: 'Cerveza', p_price: 5000 });
const shiftId = await rpc(admin, 'start_shift', {});
const customerId = await rpc(admin, 'register_customer', { p_name: 'Juancho', p_phone: null });
const accountId = await rpc(admin, 'open_account', { p_shift: shiftId, p_customer: customerId, p_guest: null, p_key: randomUUID() });
const otherAccount = await rpc(admin, 'open_account', { p_shift: shiftId, p_customer: null, p_guest: 'Otra mesa', p_key: randomUUID() });
const code = await rpc(admin, 'create_link_code', { p_account: accountId });
assert.match(code, /^[0-9A-F]{18}$/);
assert.equal((await customer.auth.signInAnonymously()).error, null);
assert.equal(await rpc(customer, 'link_account', { p_code: code }), accountId);
const expiredCode = await rpc(admin, 'create_link_code', { p_account: accountId });
sql(`update private.link_codes set expires_at=now()-interval '1 minute' where code_hash=sha256(convert_to('${expiredCode}','UTF8'))`);
assert.equal(await rpc(customer, 'link_account', { p_code: expiredCode }), null, 'expired code blocked');
assert.equal((await outsider.auth.signInAnonymously()).error, null);
await fails(() => rpc(outsider, 'account_summary', { p_account: accountId }), 'other account blocked');
await fails(() => rpc(customer, 'account_summary', { p_account: otherAccount }), 'other account blocked');
await fails(() => rpc(customer, 'open_account', { p_shift:shiftId,p_customer:null,p_guest:'Intruso',p_key:randomUUID() }), 'customer cannot open account');
const visible = await customer.from('accounts').select('id');
assert.equal(visible.error, null);
assert.deepEqual(visible.data?.map((row) => row.id), [accountId]);
const linkedCustomer = await customer.from('customers').select('name').eq('id',customerId).single();
assert.equal(linkedCustomer.data?.name, 'Juancho');
const hiddenCustomer = await outsider.from('customers').select('id').eq('id',customerId);
assert.deepEqual(hiddenCustomer.data, []);
const forbiddenWrite = await customer.from('products').update({ price_cop: 1 }).eq('id', productId);
assert.ok(forbiddenWrite.error, 'client cannot edit prices');

let realtimeSeen;
const realtimeEvent = new Promise((resolve) => { realtimeSeen = resolve; });
const channel = admin.channel(`integration-${randomUUID()}`)
  .on('postgres_changes', { event:'INSERT', schema:'public', table:'orders' }, (payload) => {
    if (payload.new.account_id === accountId) realtimeSeen(payload.new.id);
  });
await new Promise((resolve, reject) => {
  channel.subscribe((state) => {
    if (state === 'SUBSCRIBED') resolve();
    if (state === 'CHANNEL_ERROR' || state === 'TIMED_OUT') reject(new Error(`Realtime: ${state}`));
  });
});

const orderKey = randomUUID();
const orderId = await rpc(customer, 'create_order', { p_account: accountId, p_items: [{ product_id: productId, quantity: 2 }], p_key: orderKey });
assert.equal(await Promise.race([realtimeEvent, new Promise((_, reject) => setTimeout(() => reject(new Error('Realtime order timeout')), 15000))]), orderId);
await admin.removeChannel(channel);
assert.equal(await rpc(customer, 'create_order', { p_account: accountId, p_items: [{ product_id: productId, quantity: 2 }], p_key: orderKey }), orderId);
await fails(() => rpc(customer, 'create_order', { p_account: accountId, p_items: [{ product_id: productId, quantity: 1 }], p_key: orderKey }), 'order key reuse blocked');
await rpc(admin, 'take_order', { p_order: orderId });
const itemResult = await admin.from('order_items').select('id').eq('order_id', orderId).single();
if (itemResult.error || !itemResult.data) throw itemResult.error ?? new Error('order item missing');
const itemId = itemResult.data.id;
let deliverySeen;
const deliveryEvent = new Promise((resolve) => { deliverySeen = resolve; });
const customerChannel = customer.channel(`delivery-${randomUUID()}`)
  .on('postgres_changes', { event:'INSERT', schema:'public', table:'deliveries', filter:`account_id=eq.${accountId}` }, (payload) => deliverySeen(payload.new.id));
await new Promise((resolve, reject) => {
  customerChannel.subscribe((state) => {
    if (state === 'SUBSCRIBED') resolve();
    if (state === 'CHANNEL_ERROR' || state === 'TIMED_OUT') reject(new Error(`Realtime customer: ${state}`));
  });
});
const deliveryKey = randomUUID();
const deliveryId = await rpc(admin, 'confirm_delivery', { p_item: itemId, p_quantity: 1, p_key: deliveryKey });
assert.equal(await Promise.race([deliveryEvent, new Promise((_, reject) => setTimeout(() => reject(new Error('Realtime delivery timeout')), 15000))]), deliveryId);
await customer.removeChannel(customerChannel);
assert.equal(await rpc(admin, 'confirm_delivery', { p_item: itemId, p_quantity: 1, p_key: deliveryKey }), deliveryId);
await fails(() => rpc(admin, 'confirm_delivery', { p_item: itemId, p_quantity: 2, p_key: deliveryKey }), 'delivery key reuse blocked');
const parallel = await Promise.allSettled([1,2].map(() => rpc(admin, 'confirm_delivery', { p_item: itemId, p_quantity: 1, p_key: randomUUID() })));
assert.equal(parallel.filter((result) => result.status === 'fulfilled').length, 1, 'one remaining unit delivered');
assert.equal((await rpc(customer, 'account_summary', { p_account: accountId })).total_cop, 10000);

const directKey = randomUUID();
const directId = await rpc(admin, 'record_direct_delivery', { p_account:accountId,p_product:productId,p_quantity:1,p_key:directKey });
assert.equal(await rpc(admin, 'record_direct_delivery', { p_account:accountId,p_product:productId,p_quantity:1,p_key:directKey }), directId);
await fails(() => rpc(admin, 'record_direct_delivery', { p_account:otherAccount,p_product:productId,p_quantity:1,p_key:directKey }), 'direct key reuse blocked');
await rpc(admin, 'save_product', { p_category:categoryId,p_name:'Cerveza',p_price:6000 });
assert.equal((await rpc(customer, 'account_summary', { p_account:accountId })).total_cop, 15000, 'stored delivery price preserved');

const cancelOrder = await rpc(customer, 'create_order', { p_account:accountId,p_items:[{product_id:productId,quantity:1}],p_key:randomUUID() });
const cancelKey = randomUUID();
await rpc(admin, 'cancel_order', { p_order:cancelOrder,p_key:cancelKey });
await rpc(admin, 'cancel_order', { p_order:cancelOrder,p_key:cancelKey });
const cancelledItem = await admin.from('order_items').select('id').eq('order_id',cancelOrder).single();
if (cancelledItem.error || !cancelledItem.data) throw cancelledItem.error ?? new Error('cancelled item missing');
await fails(() => rpc(admin, 'confirm_delivery', { p_item:cancelledItem.data.id,p_quantity:1,p_key:randomUUID() }), 'cancelled order cannot be delivered');
const raceOrder = await rpc(customer, 'create_order', { p_account:accountId,p_items:[{product_id:productId,quantity:1}],p_key:randomUUID() });
const raceItem = await admin.from('order_items').select('id').eq('order_id',raceOrder).single();
if (raceItem.error || !raceItem.data) throw raceItem.error ?? new Error('race item missing');
const race = await Promise.allSettled([
  rpc(admin, 'cancel_order', { p_order:raceOrder,p_key:randomUUID() }),
  rpc(admin, 'confirm_delivery', { p_item:raceItem.data.id,p_quantity:1,p_key:randomUUID() })
]);
assert.equal(race.filter((result) => result.status === 'fulfilled').length, 1, 'cancel/delivery race serialized');
const raceRow = await admin.from('orders').select('status').eq('id',raceOrder).single();
assert.equal(raceRow.data?.status, race[0].status === 'fulfilled' ? 'cancelled' : 'done');
const expectedTotal = raceRow.data?.status === 'done' ? 21000 : 15000;
await rpc(customer, 'request_payment', { p_account:accountId });
assert.equal(await rpc(admin, 'confirm_payment', { p_account:accountId,p_method:'cash' }), expectedTotal);
await fails(() => rpc(admin, 'confirm_payment', { p_account:accountId,p_method:'cash' }), 'double payment blocked');
const summary = await rpc(customer, 'account_summary', { p_account:accountId });
assert.equal(summary.status, 'closed');
assert.equal(summary.paid_cop, expectedTotal);
assert.equal(sql(`select count(*) from public.payments where account_id='${accountId}'`), '1');
assert.equal(sql(`select method from public.payments where account_id='${accountId}'`), 'cash');
assert.equal(sql(`select count(*) from private.audit where entity_id='${accountId}' and action='payment_confirmed'`), '1');
console.log(JSON.stringify({ passed: true, accountId, checks: ['auth','admin role','link code and expiry','RLS isolation','price write denied','realtime order and delivery events','order idempotency','partial and concurrent delivery','direct delivery','stored prices','cancellation and delivery race','payment and audit'] }));
await Promise.all([admin.removeAllChannels(), customer.removeAllChannels(), outsider.removeAllChannels()]);
process.exit(0);
