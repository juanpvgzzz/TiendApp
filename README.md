# TiendAPP

Aplicación web local para cuentas de consumo de una tienda. El administrador gestiona catálogo, clientes, cuentas, pedidos, entregas y cobros; el cliente vincula su cuenta con un código temporal, pide productos y solicita pagar. PostgreSQL de Supabase conserva datos y autorizaciones. No hay despliegue de producción.

## Instalación

Requisitos: Node.js 22, npm y Docker Engine. Active la pertenencia al grupo Docker en la sesión y siga [instalación](docs/instalacion.md) para crear la red local, configurar `.env.local` con la URL y clave publicable y crear el administrador inicial. No use una base de producción para pruebas.

```sh
npm install
npx supabase start --network-id tiendapp-loopback
npx supabase db push
npm run dev
```

Abra `http://127.0.0.1:5173` o `http://localhost:5173`. Rutas: `/admin/login`, `/admin`, `/admin/clientes`, `/admin/catalogo`, `/admin/historial`, `/vincular` y `/mi-cuenta`.

El administrador inicial de desarrollo se crea con `scripts/create-dev-admin.mjs` según [instalación](docs/instalacion.md); no hay contraseña predeterminada. Para verificar el proyecto, ejecute `npm run check`, `npm test`, `npm run build`, `node tests/integration.mjs` y `npm run test:browser` con Supabase y Vite activos. Los [resultados reales y límites](docs/pruebas.md) están documentados.
