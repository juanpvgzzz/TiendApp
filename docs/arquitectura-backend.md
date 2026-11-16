# Arquitectura
SvelteKit sirve la futura interfaz. PostgreSQL almacena el estado definitivo. Supabase Auth proporciona identidad, RLS protege lecturas y RPCs privilegiadas encapsulan escrituras. Cada entrega conserva precio en COP. Los totales se calculan desde entregas y correcciones, no se guardan en cuentas. No hay polling ni procesos permanentes.

Estado: faltan integración SSR, Realtime, pruebas PostgreSQL y despliegue.
