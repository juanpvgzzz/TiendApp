create or replace function public.record_direct_delivery(p_account uuid,p_product uuid,p_quantity int,p_key uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_price bigint; v_existing public.deliveries%rowtype; v_id uuid;
begin
  if not private.is_staff() or p_key is null or p_quantity not between 1 and 100 then
    raise exception 'not authorized';
  end if;
  select * into v_existing from public.deliveries
    where delivered_by=auth.uid() and idempotency_key=p_key;
  if found then
    if v_existing.account_id<>p_account or v_existing.product_id<>p_product
       or v_existing.quantity<>p_quantity or v_existing.order_item_id is not null then
      raise exception 'key reused';
    end if;
    return v_existing.id;
  end if;
  perform 1 from public.accounts where id=p_account and status='open' for update;
  if not found then raise exception 'account unavailable'; end if;
  select * into v_existing from public.deliveries
    where delivered_by=auth.uid() and idempotency_key=p_key;
  if found then
    if v_existing.account_id<>p_account or v_existing.product_id<>p_product
       or v_existing.quantity<>p_quantity or v_existing.order_item_id is not null then
      raise exception 'key reused';
    end if;
    return v_existing.id;
  end if;
  select price_cop into v_price from public.products where id=p_product and active;
  if not found then raise exception 'product unavailable'; end if;
  insert into public.deliveries(account_id,product_id,quantity,unit_price_cop,delivered_by,idempotency_key)
    values(p_account,p_product,p_quantity,v_price,auth.uid(),p_key) returning id into v_id;
  return v_id;
end $$;
