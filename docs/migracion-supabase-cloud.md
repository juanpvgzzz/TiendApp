# Preparación de Supabase Cloud

Estado al 13 de noviembre de 2026: destino Cloud pendiente de confirmar. No se ha vinculado ningún proyecto remoto, aplicado migraciones remotas ni importado datos.

## Base local verificada

- Supabase CLI `3.0.0` y PostgreSQL local `17`. Hay **19 migraciones** versionadas en `supabase/migrations/`, desde `20261112000100_core.sql` hasta `20261113215702_account_access_revocation_broadcast.sql`; las 19 figuran aplicadas en la base local.
- El esquema contiene 14 tablas públicas (`account_access`, `account_events`, `accounts`, `categories`, `customers`, `deliveries`, `delivery_corrections`, `order_items`, `orders`, `payment_requests`, `payments`, `products`, `shifts`, `staff`) y 3 privadas (`audit`, `link_attempts`, `link_codes`). Las 14 tablas públicas tienen RLS. Hay 32 firmas de funciones públicas, 67 restricciones (28 claves foráneas, 16 `CHECK`, 6 `UNIQUE`), 36 índices y un trigger propio para revocar el acceso a cuentas.
- `supabase_realtime` publica únicamente `account_events`, `accounts`, `deliveries`, `orders` y `payment_requests`. La última migración añade una política de recepción de Broadcast privado en `realtime.messages` para avisar de revocaciones.
- `product-photos` es público para lectura y limita los objetos a WebP de 2 MB. Las políticas de `storage.objects` permiten insertar, leer como administrador y borrar al administrador activo. La interfaz sustituye una foto mediante una subida nueva y eliminación de la anterior; no hay política `UPDATE` para sobrescribir el mismo objeto.
- En local hay 91 categorías, 90 productos, 19 referencias a fotografías y 19 objetos del bucket. No hay referencias rotas ni objetos huérfanos en el recuento local. Los datos contienen numerosos registros de pruebas; **ninguno está autorizado para importar por defecto**.
- `supabase db advisors --type security --level warn` y `--type performance --level warn` no encontraron avisos locales. Ninguna función pública concede `EXECUTE` a `anon`.

## Antes de aplicar cambios remotos

1. Obtener el Project Reference del proyecto nuevo y completar `supabase login` mediante el flujo oficial. Confirmar que no corresponde a un proyecto existente de producción.
2. Ejecutar `npx --no-install supabase link --project-ref <ref>`, `npx --no-install supabase migration list --remote` y `npx --no-install supabase db push --dry-run --remote`. Revisar el destino y las migraciones pendientes con el propietario; solicitar autorización explícita antes de `db push --remote`.
3. Comprobar que PostgreSQL remoto usa una versión compatible y que la base nueva no contiene migraciones o tablas de aplicación ajenas. No usar `db reset` remoto ni `--include-seed`.

## Después de autorizar el despliegue

1. Aplicar las 19 migraciones en orden con `npx --no-install supabase db push --remote`; cualquier incompatibilidad se corrige mediante una migración nueva, sin editar las ya aplicadas.
2. Comparar historial, tablas, claves foráneas, restricciones, índices, funciones y permisos `EXECUTE`, trigger, RLS, publicación Realtime, política de canal privado y bucket contra el inventario local. Ejecutar los asesores de seguridad y rendimiento remotos.
3. Configurar Auth en Cloud. `config.toml` es local y sus URL `127.0.0.1` no sirven como URL pública. La aplicación necesita email/contraseña para personal y Anonymous Sign-Ins para clientes; confirmar URL del sitio y redirecciones antes de configurarlas. No desactivar globalmente los nuevos registros sin probar el flujo anónimo: Supabase Auth rechaza `signInAnonymously()` cuando el registro global está deshabilitado. Mantener límites de uso apropiados para los inicios anónimos. No copiar `auth.users` ni contraseñas locales.
4. Crear la primera identidad administrativa por invitación desde Authentication → Users, usando un correo controlado por el propietario. Una vez confirmado el correo, vincular su `auth.users.id` con una fila `public.staff` de rol `admin` desde una sesión administrativa de confianza. No establecer una contraseña predeterminada. Los empleados posteriores se crean como identidades verificadas y se habilitan desde la aplicación.
5. Importar solo las categorías, productos y fotografías reales que el propietario identifique y autorice. Preservar UUID de productos y categorías si se reutilizan las rutas `photo_path`; subir los objetos del bucket por separado y comprobar cada asociación. `db push` no transfiere objetos de Storage.
6. Ejecutar pruebas de integración con registros marcados como pruebas, limpiar únicamente esos registros y comprobar acceso por rol, vinculación anónima, Storage, pedidos, entregas, pagos y Realtime. No operar sobre datos reales.

No ejecutar `config push` directamente con la configuración local: contiene URL de desarrollo y ajustes de Auth que deben revisarse para Cloud.
