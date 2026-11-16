# RPC

Las operaciones existentes de cuenta, pedido, entrega y cobro permanecen. Las migraciones de finalización añaden `close_shift`, `set_employee`, `revoke_link_codes`, `account_history`, `basic_report`, `audit_history` y la corrección `correct_delivery(p_delivery,p_delta,p_reason,p_key)`. La variante anterior de corrección, así como las variantes anteriores de apertura de cuenta y confirmación de pago, no tienen permiso `EXECUTE` para `authenticated`. Las RPC usan `auth.uid()`, permisos de `staff`, RLS para lecturas y bloqueos de filas en cambios de cuenta.
