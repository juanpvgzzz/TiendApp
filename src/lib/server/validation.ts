import { z } from 'zod';
export const orderInput = z.object({accountId:z.string().uuid(),idempotencyKey:z.string().uuid(),items:z.array(z.object({product_id:z.string().uuid(),quantity:z.number().int().min(1).max(100)})).min(1).max(20)});
