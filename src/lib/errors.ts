export function friendlyError(cause: unknown): string {
  const message = cause instanceof Error ? cause.message : '';
  if (/failed to fetch|network|fetch failed/i.test(message)) return 'No hay conexión. Revisa tu red e inténtalo de nuevo.';
  if (/phone already registered/i.test(message)) return 'Este teléfono ya está registrado. Busca al cliente antes de crear otro.';
  if (/active accounts/i.test(message)) return 'Cierra las cuentas activas antes de cerrar la jornada.';
  if (/verified Auth user required/i.test(message)) return 'El usuario debe existir y tener el correo confirmado en Supabase Auth.';
  if (/admin role cannot be changed/i.test(message)) return 'El rol de administrador no puede cambiarse desde este formulario.';
  if (/invalid correction/i.test(message)) return 'El ajuste supera la cantidad válida de este consumo.';
  if (/invalid photo/i.test(message)) return 'Selecciona una foto JPG, PNG o WebP de hasta 10 MB.';
  if (/shift closed|shift unavailable/i.test(message)) return 'La jornada ya no está disponible.';
  if (/jwt|session|token.*expired|not authorized/i.test(message)) return 'Tu sesión venció o no tienes permiso para esta acción.';
  if (/invalid login credentials/i.test(message)) return 'Correo o contraseña incorrectos.';
  if (/account unavailable|account closed/i.test(message)) return 'Esta cuenta ya no permite la operación.';
  if (/pending orders/i.test(message)) return 'Resuelve los pedidos pendientes antes de confirmar el pago.';
  if (/excess quantity/i.test(message)) return 'La cantidad supera lo pendiente por entregar.';
  if (/key reused/i.test(message)) return 'La operación ya se envió con otros datos. Actualiza la página.';
  if (/duplicate|unique|already exists/i.test(message)) return 'Este registro ya existe. Revisa los datos antes de continuar.';
  if (/invalid items|invalid request|invalid customer|invalid phone/i.test(message)) return 'Revisa los datos ingresados.';
  return 'No pudimos completar la operación. Inténtalo de nuevo.';
}

export function staffLoginError(cause: unknown): string {
  const message = cause instanceof Error ? cause.message : '';
  if (/staff access denied|not authorized|permission denied/i.test(message)) return 'Tu usuario no tiene acceso al personal.';
  if (/failed to fetch|network|fetch failed/i.test(message)) return 'No pudimos conectar. Intenta nuevamente.';
  if (/invalid login credentials/i.test(message)) return 'Correo o contraseña incorrectos.';
  return 'No pudimos conectar. Intenta nuevamente.';
}
