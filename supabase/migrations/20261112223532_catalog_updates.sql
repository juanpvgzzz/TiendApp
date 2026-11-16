create function public.update_product(p_product uuid,p_category uuid,p_name text,p_price bigint,p_active boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_admin() or length(trim(p_name)) not between 1 and 100
     or p_price is null or p_price<0 or p_active is null then
    raise exception 'invalid request';
  end if;
  update public.products set category_id=p_category,name=trim(p_name),
    price_cop=p_price,active=p_active where id=p_product;
  if not found then raise exception 'product unavailable'; end if;
  insert into private.audit(actor,action,entity_id,details)
    values(auth.uid(),'product_updated',p_product,
           jsonb_build_object('category_id',p_category,'name',trim(p_name),
                              'price_cop',p_price,'active',p_active));
end $$;
revoke all on function public.update_product(uuid,uuid,text,bigint,boolean)
  from public,anon,authenticated;
grant execute on function public.update_product(uuid,uuid,text,bigint,boolean)
  to authenticated;
