import { execFileSync } from 'node:child_process';
import { createClient } from '@supabase/supabase-js';

const email = process.env.TIENDAPP_ADMIN_EMAIL;
const password = process.env.TIENDAPP_ADMIN_PASSWORD;
const displayName = process.env.TIENDAPP_ADMIN_NAME?.trim();
if (!email || !password || password.length < 12) {
  throw new Error('Define TIENDAPP_ADMIN_EMAIL y TIENDAPP_ADMIN_PASSWORD (mínimo 12 caracteres).');
}
if (!displayName || displayName.length < 2 || displayName.length > 80) {
  throw new Error('Define TIENDAPP_ADMIN_NAME (2 a 80 caracteres).');
}
const status = JSON.parse(execFileSync('npx', ['--no-install','supabase','status','--output','json'], { encoding:'utf8' }));
if (status.API_URL !== 'http://127.0.0.1:54321' || !/^postgresql:\/\/[^@]+@127\.0\.0\.1:54322\//.test(status.DB_URL)) {
  throw new Error('Este script solo admite el Supabase local de TiendApp.');
}
const root = createClient(status.API_URL, status.SERVICE_ROLE_KEY, { auth:{persistSession:false} });
const { data, error } = await root.auth.admin.createUser({email,password,email_confirm:true});
if (error || !data.user) throw error ?? new Error('No se creó el usuario.');
const id = data.user.id;
if (!/^[0-9a-f-]{36}$/.test(id)) throw new Error('Identificador Auth inválido.');
const safeName = displayName.replaceAll("'", "''");
try {
  execFileSync('docker',['exec','-i','supabase_db_tiendapp','psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-c',
    `insert into public.staff(user_id,role,display_name) values ('${id}','admin','${safeName}')`],{stdio:'pipe'});
} catch (cause) {
  await root.auth.admin.deleteUser(id);
  throw cause;
}
console.log(`Administrador local creado: ${email}`);
