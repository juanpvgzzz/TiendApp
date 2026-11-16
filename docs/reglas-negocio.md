# Reglas de negocio

El administrador abre y cierra jornadas, gestiona personal y catálogo, corrige consumos y consulta historial, informes y auditoría. El empleado activo registra clientes, abre cuentas, atiende pedidos, registra entregas y confirma cobros presenciales. El cliente vinculado consulta su cuenta, solicita productos y pide pagar. El personal se autoriza desde `staff`, nunca desde metadatos editables del navegador.

Una persona identificada tiene como máximo una cuenta sin cerrar. Los invitados usan nombre libre; los nombres de clientes pueden repetirse y el teléfono normalizado evita altas accidentales duplicadas. No se fusionan clientes. La jornada permanece abierta después de medianoche y solo se cierra si todas sus cuentas están cerradas.

Cada código de vinculación dura diez minutos, se usa una vez y los códigos anteriores se revocan al emitir uno nuevo. La sesión Auth y `account_access` mantienen el acceso; el personal puede emitir un nuevo código mientras la cuenta no esté cerrada, incluso durante el cobro. Hay cinco intentos por usuario cada quince minutos. Las cuentas ajenas quedan fuera de RLS y RPC.

Los pedidos no suman al cobro; solo las cantidades entregadas, con precio almacenado al entregar. El personal puede cancelar pedidos pendientes o tomados; lo ya entregado permanece cobrable. Los consumos directos se registran como entregas. La corrección exige administrador, motivo e idempotencia, y no se permite después del cierre. Durante el cobro no se aceptan pedidos ni entregas nuevos. El cierre exige pedidos resueltos, calcula el total en PostgreSQL y registra un único pago en efectivo o transferencia.

La vista del cliente presenta dos grupos visuales: CERVEZAS cuando el nombre del producto o de su categoría contiene «cerveza», «beer» o «pola», y MECATOS para los demás productos activos. Este agrupamiento no cambia las categorías de PostgreSQL ni el precio aplicado al entregar. Solo el administrador asigna fotografías de productos; si faltan, se indica «Foto pendiente».
