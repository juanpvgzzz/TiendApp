export const money = (value: number) =>
  new Intl.NumberFormat('es-CO', { style: 'currency', currency: 'COP', maximumFractionDigits: 0 }).format(value);

export const dateTime = (value: string) =>
  new Intl.DateTimeFormat('es-CO', {
    timeZone: 'America/Bogota', day: 'numeric', month: 'short', year: 'numeric',
    hour: 'numeric', minute: '2-digit'
  }).format(new Date(value));

export const time = (value: string) =>
  new Intl.DateTimeFormat('es-CO', { timeZone: 'America/Bogota', hour: 'numeric', minute: '2-digit' }).format(new Date(value));

const labels: Record<string, string> = {
  open: 'Abierta', paying: 'Pago solicitado', closed: 'Cerrada',
  pending: 'Pendiente', taken: 'En atención', done: 'Entregado', cancelled: 'Cancelado'
};
export const statusLabel = (status: string) => labels[status] ?? status;
