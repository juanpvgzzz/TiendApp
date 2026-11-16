create or replace function public.correct_delivery(p_delivery uuid,p_delta int,p_reason text,p_key uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v public.deliveries%rowtype; v_existing public.delivery_corrections%rowtype;
  v_account uuid; v_id uuid; v_corrected int; v_item_total bigint;
begin
  if not private.is_admin() or p_key is null or p_delta is null or p_delta=0 or p_reason is null
    or length(trim(p_reason)) not between 5 and 500 then raise exception 'not authorized'; end if;
  select * into v_existing from public.delivery_corrections
    where corrected_by=auth.uid() and idempotency_key=p_key;
  if found then
    if v_existing.delivery_id<>p_delivery or v_existing.quantity_delta<>p_delta
      or v_existing.reason<>trim(p_reason) then raise exception 'key reused'; end if;
    return v_existing.id;
  end if;
  select account_id into v_account from public.deliveries where id=p_delivery;
  perform 1 from public.accounts where id=v_account and status<>'closed' for update;
  if not found then raise exception 'account closed'; end if;
  select * into v_existing from public.delivery_corrections
    where corrected_by=auth.uid() and idempotency_key=p_key;
  if found then
    if v_existing.delivery_id<>p_delivery or v_existing.quantity_delta<>p_delta
      or v_existing.reason<>trim(p_reason) then raise exception 'key reused'; end if;
    return v_existing.id;
  end if;
  select * into v from public.deliveries where id=p_delivery for update;
  select v.quantity+coalesce(sum(quantity_delta),0) into v_corrected
    from public.delivery_corrections where delivery_id=p_delivery;
  if v_corrected+p_delta<0 then raise exception 'invalid correction'; end if;
  if v.order_item_id is not null and p_delta>0 then
    select coalesce(sum(d.quantity+coalesce((select sum(c.quantity_delta)
      from public.delivery_corrections c where c.delivery_id=d.id),0)),0)
      into v_item_total from public.deliveries d where d.order_item_id=v.order_item_id;
    if v_item_total+p_delta>(select quantity from public.order_items where id=v.order_item_id) then
      raise exception 'invalid correction';
    end if;
  end if;
  insert into public.delivery_corrections(delivery_id,quantity_delta,reason,corrected_by,idempotency_key)
    values(p_delivery,p_delta,trim(p_reason),auth.uid(),p_key) returning id into v_id;
  insert into public.account_events(account_id,kind) values(v_account,'consumption_corrected');
  insert into private.audit(actor,action,entity_id,details)
    values(auth.uid(),'delivery_corrected',p_delivery,jsonb_build_object('delta',p_delta,'reason',trim(p_reason)));
  return v_id;
end $$;
