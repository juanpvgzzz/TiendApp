import { describe,it,expect } from 'vitest';
import { orderInput } from '../src/lib/server/validation';
describe('order input',()=>{it('rejects invalid quantity',()=>expect(orderInput.safeParse({accountId:crypto.randomUUID(),idempotencyKey:crypto.randomUUID(),items:[{product_id:crypto.randomUUID(),quantity:0}]}).success).toBe(false));});
