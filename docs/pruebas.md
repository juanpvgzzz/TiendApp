# Pruebas locales

Verificado el 13 de noviembre de 2026 con Supabase local en `127.0.0.1:54321` y PostgreSQL local en `127.0.0.1:54322`. Se conservaron las nueve migraciones previas y se aplicaron siete nuevas. No se usó `db reset` ni se conectó a producción. Las pruebas dejan datos en la base local; las operaciones simuladas de madrugada y cierre de jornada se revierten con `ROLLBACK`.

- `node tests/integration.mjs`: pasó. Auth, administrador, códigos vencidos, RLS entre cuentas, idempotencia, entregas parciales y concurrentes, cancelación en carrera con entrega, precio histórico, pago único y eventos Realtime de pedido y entrega.
- `node tests/backend-completion.mjs`: pasó. Tres roles, alta y baja de empleado, clientes repetidos y teléfono duplicado, apertura de cuenta identificada, jornada pasada la medianoche y cierre, revocación y límite de códigos, recuperación con nuevo código durante el cobro, IDOR, corrección idempotente y limitada a la cantidad pedida, evento Realtime de cambio de consumo, recuperación del estado tras desconectar el canal, consumo verbal, precio histórico, solicitud de pago repetida, cierre por transferencia, historial, informe y auditoría.
- `npm run check`: 0 errores y 0 advertencias. `npm test`: 1 prueba unitaria aprobada. `npm run build`: terminó correctamente.
- `npx supabase db advisors --type security --level warn` y `--type performance --level warn`: sin avisos. Las 14 tablas públicas tienen RLS. Ninguna RPC pública concede `EXECUTE` a `anon`; las RPC antiguas de corrección, apertura y pago no conceden `EXECUTE` a `authenticated`.

Una ejecución de cada prueba Realtime del backend agotó su espera de 15 segundos; la repetición aislada pasó. La interfaz consulta el estado real al reconectar y al volver a una pestaña inactiva.

## Frontend

- `npm run check`: pasó con 0 errores y 0 advertencias. `npm test`: 1 prueba unitaria aprobada. `npm run build`: pasó. `npm run lint`: terminó sin errores; la configuración actual solo excluye archivos generados y no define reglas de estilo.
- `npm run test:browser`: 2 pruebas aprobadas en Chromium contra Supabase local. La prueba existente completó catálogo, cliente identificado, cuenta, pedido, entregas parciales, solicitud y confirmación de pago, recarga e historial filtrado. La prueba nueva completó alta y baja de empleado desde la interfaz, acceso por rol, cuenta invitada, consumo directo, vinculación, corrección administrativa, recuperación tras desconexión, cobro por empleado, historial, informes y auditoría. Se comprobaron 320, 360, 375, 390, 430, 768 y 1440 px sin desbordamiento horizontal; no hubo errores JavaScript en la ejecución final.
- Fallos iniciales corregidos antes de la ejecución final: selector de producto ambiguo en la prueba, selección de una vista equivocada para comprobar pagos, script Playwright que incluía una prueba Vitest y una actualización Realtime con rechazo sin manejar. La suite final pasó completa.

No se ejecutó una auditoría automática de lectores de pantalla ni contraste WCAG. La creación inicial de identidades Auth para empleados permanece como operación administrativa de servidor o de Supabase; la interfaz activa y desactiva únicamente usuarios ya verificados.

## Rediseño del catálogo visual

- Se aplicaron a Supabase local `20261113064654_product_photos.sql` y `20261113070056_fix_product_photo_policy.sql`. La segunda corrige la resolución de `name` en la política RLS de Storage; ninguna migración anterior se editó.
- `npm run check`: 0 errores y 0 advertencias. `npm test`: 1 prueba aprobada. `npm run build`: pasó. `npx supabase db advisors --type security --level warn`: sin avisos.
- `npm run test:browser`: 2 pruebas aprobadas en Chromium contra Supabase local. Se verificó carga de WebP desde Storage, rechazo de carga y cambio de foto sin rol administrador, búsqueda, cambio entre CERVEZAS y MECATOS, cantidad, pedido, entregas y total por Realtime, solicitud y cierre del pago, navegación inferior y ausencia de desbordamiento a 320, 360, 375, 390, 430, 768 y 1440 px. Se inspeccionaron capturas a 320 y 390 px.
- La imagen usada en la prueba es un archivo de prueba generado durante la ejecución. Las fotos reales de los productos de la tienda siguen pendientes de asignación desde `/admin/catalogo`; el cliente muestra «Foto pendiente» mientras falten. No se probaron fotos reales de todo el catálogo ni una auditoría automática de accesibilidad.
