alter table public.staff add column display_name text
  check (display_name is null or length(trim(display_name)) between 2 and 80);
alter table public.payments add column method text
  check (method in ('cash','transfer'));

create function public.set_product_active(p_product uuid, p_active boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_admin() or p_active is null then raise exception 'not authorized'; end if;
  update public.products set active=p_active where id=p_product;
  if not found then raise exception 'product unavailable'; end if;
  insert into private.audit(actor,action,entity_id,details)
    values(auth.uid(),'product_availability_changed',p_product,jsonb_build_object('active',p_active));
end $$;

create function public.account_delivery_details(p_account uuid)
returns table(id uuid, product_name text, quantity int, unit_price_cop bigint,
              delivered_at timestamptz, delivered_by text, ordered_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not private.can_access(p_account) then raise exception 'not authorized'; end if;
  return query
    select d.id,p.name,
           (d.quantity+coalesce((select sum(c.quantity_delta) from public.delivery_corrections c
                                 where c.delivery_id=d.id),0))::int,
           d.unit_price_cop,d.delivered_at,
           coalesce(nullif(trim(s.display_name),''),'Administrador'),o.created_at
    from public.deliveries d
    join public.products p on p.id=d.product_id
    join public.staff s on s.user_id=d.delivered_by
    left join public.order_items i on i.id=d.order_item_id
    left join public.orders o on o.id=i.order_id
    where d.account_id=p_account order by d.delivered_at desc,d.id;
end $$;

create function public.confirm_payment(p_account uuid,p_method text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare v_total bigint;
begin
  if not private.is_admin() or p_method not in ('cash','transfer') then
    raise exception 'not authorized';
  end if;
  perform 1 from public.accounts where id=p_account and status='paying' for update;
  if not found then raise exception 'account unavailable'; end if;
  if exists(select 1 from public.orders where account_id=p_account and status in ('pending','taken')) then
    raise exception 'pending orders';
  end if;
  select coalesce(sum((d.quantity+coalesce((select sum(c.quantity_delta)
                                          from public.delivery_corrections c
                                          where c.delivery_id=d.id),0))*d.unit_price_cop),0)
    into v_total from public.deliveries d where d.account_id=p_account;
  insert into public.payments(account_id,amount_cop,received_by,method)
    values(p_account,v_total,auth.uid(),p_method);
  update public.accounts set status='closed',closed_at=now() where id=p_account;
  insert into private.audit(actor,action,entity_id,details)
    values(auth.uid(),'payment_confirmed',p_account,
           jsonb_build_object('amount_cop',v_total,'method',p_method));
  return v_total;
end $$;

revoke all on function public.confirm_payment(uuid) from authenticated;
revoke all on function public.set_product_active(uuid,boolean),
  public.account_delivery_details(uuid),public.confirm_payment(uuid,text)
  from public,anon,authenticated;
grant execute on function public.set_product_active(uuid,boolean),
  public.account_delivery_details(uuid),public.confirm_payment(uuid,text) to authenticated;
