# Realtime

La publicación `supabase_realtime` incluye `accounts`, `orders`, `deliveries`, `payment_requests` y `account_events`. `account_events` avisa correcciones de consumo sin publicar el motivo; RLS restringe cada evento a personal activo o usuarios vinculados a la cuenta. Las tablas de cuenta notifican cierre y solicitud de pago. Al suscribirse o reconectar, consulte las tablas o RPC autorizadas para reconstruir el estado real. No use sondeo permanente.

Al borrar una vinculación de `account_access`, un trigger audita la revocación y envía un Broadcast privado al tema del usuario afectado. La política de `realtime.messages` permite escuchar únicamente el tema de la propia identidad. El cliente vuelve a consultar la autorización y oculta la cuenta si ya no tiene acceso.
