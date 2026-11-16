alter table public.orders
  add column cancelled_by uuid references public.staff(user_id),
  add column cancellation_key uuid,
  add column cancelled_at timestamptz;

create unique index orders_cancellation_key on public.orders(cancelled_by, cancellation_key)
  where cancellation_key is not null;

create function public.cancel_order(p_order uuid, p_key uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_account uuid;
  v_order public.orders%rowtype;
begin
  if not private.is_staff() or p_key is null then raise exception 'not authorized'; end if;

  select account_id into v_account from public.orders where id = p_order;
  if v_account is null then raise exception 'order unavailable'; end if;

  perform 1 from public.accounts where id = v_account for update;
  select * into v_order from public.orders where id = p_order for update;
  if v_order.status = 'cancelled' and v_order.cancelled_by = auth.uid()
     and v_order.cancellation_key = p_key then return; end if;
  if v_order.status not in ('pending', 'taken') or
     not exists (select 1 from public.accounts where id = v_account and status = 'open') then
    raise exception 'order unavailable';
  end if;

  update public.orders set status = 'cancelled', cancelled_by = auth.uid(),
    cancellation_key = p_key, cancelled_at = now() where id = p_order;
  insert into private.audit(actor, action, entity_id)
    values (auth.uid(), 'order_cancelled', p_order);
end $$;

create or replace function public.confirm_delivery(p_item uuid, p_quantity int, p_key uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_item public.order_items%rowtype;
  v_account uuid;
  v_price bigint;
  v_id uuid;
  v_existing public.deliveries%rowtype;
begin
  if not private.is_staff() or p_key is null or p_quantity not between 1 and 100 then
    raise exception 'not authorized';
  end if;

  select * into v_existing from public.deliveries
    where delivered_by = auth.uid() and idempotency_key = p_key;
  if found then
    if v_existing.order_item_id is distinct from p_item or v_existing.quantity <> p_quantity then
      raise exception 'key reused';
    end if;
    return v_existing.id;
  end if;

  select o.account_id into v_account from public.order_items i
    join public.orders o on o.id = i.order_id where i.id = p_item;
  if v_account is null then raise exception 'item unavailable'; end if;

  perform 1 from public.accounts where id = v_account and status = 'open' for update;
  if not found then raise exception 'account unavailable'; end if;

  select * into v_existing from public.deliveries
    where delivered_by = auth.uid() and idempotency_key = p_key;
  if found then
    if v_existing.order_item_id is distinct from p_item or v_existing.quantity <> p_quantity then
      raise exception 'key reused';
    end if;
    return v_existing.id;
  end if;

  select * into v_item from public.order_items where id = p_item for update;
  if not exists (select 1 from public.orders where id = v_item.order_id
                 and account_id = v_account and status in ('pending', 'taken')) then
    raise exception 'order unavailable';
  end if;
  if v_item.delivered_quantity + p_quantity > v_item.quantity then
    raise exception 'excess quantity';
  end if;

  select price_cop into v_price from public.products where id = v_item.product_id;
  update public.order_items set delivered_quantity = delivered_quantity + p_quantity where id = p_item;
  insert into public.deliveries(account_id, order_item_id, product_id, quantity,
    unit_price_cop, delivered_by, idempotency_key)
    values (v_account, p_item, v_item.product_id, p_quantity, v_price, auth.uid(), p_key)
    returning id into v_id;
  if not exists (select 1 from public.order_items
                 where order_id = v_item.order_id and delivered_quantity < quantity) then
    update public.orders set status = 'done' where id = v_item.order_id;
  end if;
  return v_id;
end $$;

revoke all on function public.cancel_order(uuid, uuid) from public, anon, authenticated;
grant execute on function public.cancel_order(uuid, uuid) to authenticated;
