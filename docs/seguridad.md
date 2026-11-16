# Seguridad
RLS deniega escrituras directas. Las RPCs comprueban `auth.uid()`, rol de `staff` y estado de cuenta; usan `security definer` con `search_path` vacío. Nunca se confía en `user_metadata` para roles. La clave publicable puede ir al cliente; la service role nunca.

Bootstrap: crear usuario administrador en Supabase Auth y ejecutar manualmente, con privilegios de propietario, `insert into public.staff(user_id,role) values ('UUID_DEL_USUARIO','admin');`. Verificar identidad fuera de banda antes de hacerlo.

La migración 004 limita a cinco intentos de vinculación por usuario y ventana de quince minutos, incluidos códigos inexistentes. No se han probado permisos RLS ni resistencia a cuentas anónimas masivas; no habilitar vinculación en producción antes de esas pruebas.
