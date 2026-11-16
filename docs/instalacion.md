# Instalación
El entorno local usa Node 22, npm, Docker Engine y Supabase CLI 3.0.0. Docker se instaló fuera de esta sesión; el usuario `jamp` pertenece al grupo `docker`, pero una sesión antigua puede necesitar `newgrp docker` o volver a iniciar sesión.

La instancia se inició en la red `tiendapp-loopback`, que enlaza sus puertos solo a `127.0.0.1`. Si la red no existe, créela antes de iniciar Supabase:

```sh
docker network create -o com.docker.network.bridge.host_binding_ipv4=127.0.0.1 tiendapp-loopback
npx supabase start --network-id tiendapp-loopback
npx supabase db push
npx supabase status
```

Use únicamente la URL API y la clave publicable de `status` en `.env.local`; nunca copie `SECRET_KEY` ni `SERVICE_ROLE_KEY` al navegador. El archivo está ignorado por Git. Ejecute `npm run dev` y abra `http://127.0.0.1:5173`.

Para crear el primer administrador local sin imprimir la contraseña:

```sh
read -r -s -p 'Contraseña del administrador: ' TIENDAPP_ADMIN_PASSWORD; echo
export TIENDAPP_ADMIN_PASSWORD
TIENDAPP_ADMIN_EMAIL=admin@tiendapp.local TIENDAPP_ADMIN_NAME='Nombre del administrador' node scripts/create-dev-admin.mjs
unset TIENDAPP_ADMIN_PASSWORD
```

El script usa Auth Admin API y registra el rol en PostgreSQL; rechaza cualquier URL que no sea la instancia local. El correo es un ejemplo y se puede cambiar. No hay contraseña predeterminada.

Para dar de alta a un empleado, un administrador de Auth crea primero su usuario con correo confirmado desde una operación de servidor o el panel de Supabase. Luego un administrador de TiendAPP introduce el UUID en `/admin/personal`; la interfaz usa `set_employee(p_user, p_name, p_active)` para activarlo o desactivarlo. La RPC solo permite el rol `employee`. Nunca se envía la clave de servicio al navegador ni se ofrece autorregistro privilegiado. La autenticación anónima de Supabase debe estar habilitada para sesiones de clientes invitados; en este entorno local ya lo está.

En `/admin/catalogo`, edite un producto para asignar su fotografía real. Se aceptan JPG, PNG o WebP de hasta 10 MB; el navegador la reduce a 1000 px y la convierte a WebP. Supabase Storage guarda el archivo en el bucket público `product-photos` con subida restringida a administradores. Aplique las migraciones nuevas con `npx supabase db push` en el entorno deseado antes de usar esta pantalla. No use fotos de otro producto para llenar huecos: el catálogo muestra «Foto pendiente» hasta que se cargue la foto correcta.

Ejecute `node tests/integration.mjs` y `node tests/backend-completion.mjs` solo en la base local. Dejan datos de prueba persistidos para inspección. No ejecute `db reset` si hay datos que conservar.

Para verificar el frontend, mantenga `npm run dev -- --host 127.0.0.1` activo y ejecute `npm run check`, `npm test`, `npm run build` y `npm run test:browser`. Playwright requiere Chromium instalado. Las rutas de acceso son `/empleado/login`, `/admin/login` y `/vincular` para clientes.
