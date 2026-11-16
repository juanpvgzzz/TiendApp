create or replace function private.is_staff() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.staff
                where user_id=auth.uid() and active and role='admin')
$$;

alter table public.accounts add column opening_key uuid;
grant select on public.account_access to authenticated;
create policy account_access_self on public.account_access for select to authenticated
  using (user_id = (select auth.uid()));
create policy customers_linked_account on public.customers for select to authenticated
  using (exists (
    select 1 from public.accounts a join public.account_access aa on aa.account_id=a.id
    where a.customer_id=customers.id and aa.user_id=(select auth.uid())
  ));
create unique index accounts_opening_key on public.accounts(opened_by, opening_key)
  where opening_key is not null;

create function public.start_shift() returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not private.is_admin() then raise exception 'not authorized'; end if;
  select id into v_id from public.shifts where closed_at is null order by opened_at limit 1 for update;
  if v_id is not null then return v_id; end if;
  insert into public.shifts(opened_by) values(auth.uid())
    on conflict do nothing returning id into v_id;
  if v_id is null then
    select id into v_id from public.shifts where closed_at is null;
  end if;
  return v_id;
end $$;
create unique index one_active_shift on public.shifts((true)) where closed_at is null;

create function public.register_customer(p_name text, p_phone text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not private.is_admin() or length(trim(p_name)) not between 1 and 120 then
    raise exception 'invalid request';
  end if;
  insert into public.customers(name, phone)
    values(trim(p_name), nullif(trim(p_phone), '')) returning id into v_id;
  return v_id;
end $$;

create function public.save_category(p_name text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not private.is_admin() or length(trim(p_name)) not between 1 and 100 then
    raise exception 'invalid request';
  end if;
  insert into public.categories(name) values(trim(p_name))
    on conflict(name) do update set name=excluded.name returning id into v_id;
  return v_id;
end $$;

create function public.save_product(p_category uuid, p_name text, p_price bigint) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not private.is_admin() or length(trim(p_name)) not between 1 and 100 or p_price < 0 then
    raise exception 'invalid request';
  end if;
  insert into public.products(category_id, name, price_cop)
    values(p_category, trim(p_name), p_price)
    on conflict(category_id, name) do update set price_cop=excluded.price_cop, active=true
    returning id into v_id;
  insert into private.audit(actor, action, entity_id, details)
    values(auth.uid(), 'product_saved', v_id, jsonb_build_object('price_cop', p_price));
  return v_id;
end $$;

create or replace function public.open_account(p_shift uuid, p_customer uuid, p_guest text, p_key uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not private.is_admin() or p_key is null then raise exception 'not authorized'; end if;
  select id into v_id from public.accounts where opened_by=auth.uid() and opening_key=p_key;
  if found then
    if not exists(select 1 from public.accounts where id=v_id and shift_id=p_shift
                  and customer_id is not distinct from p_customer
                  and guest_name is not distinct from nullif(trim(p_guest),'')) then
      raise exception 'key reused';
    end if;
    return v_id;
  end if;
  if (p_customer is null) = (nullif(trim(p_guest),'') is null) then
    raise exception 'invalid customer';
  end if;
  perform 1 from public.shifts where id=p_shift and closed_at is null for update;
  if not found then raise exception 'shift closed'; end if;
  insert into public.accounts(shift_id, customer_id, guest_name, opened_by, opening_key)
    values(p_shift, p_customer, nullif(trim(p_guest),''), auth.uid(), p_key)
    on conflict do nothing
    returning id into v_id;
  if v_id is null then
    select id into v_id from public.accounts where opened_by=auth.uid() and opening_key=p_key
      and shift_id=p_shift and customer_id is not distinct from p_customer
      and guest_name is not distinct from nullif(trim(p_guest),'');
    if v_id is null then raise exception 'account unavailable or key reused'; end if;
  end if;
  return v_id;
end $$;

revoke all on function public.open_account(uuid,uuid,text) from authenticated;
revoke all on function public.start_shift(), public.register_customer(text,text),
  public.save_category(text), public.save_product(uuid,text,bigint),
  public.open_account(uuid,uuid,text,uuid) from public, anon, authenticated;
grant execute on function public.start_shift(), public.register_customer(text,text),
  public.save_category(text), public.save_product(uuid,text,bigint),
  public.open_account(uuid,uuid,text,uuid) to authenticated;

do $$
declare v_table text;
begin
  foreach v_table in array array['accounts','orders','deliveries','payment_requests'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname='supabase_realtime' and schemaname='public' and tablename=v_table) then
      execute format('alter publication supabase_realtime add table public.%I', v_table);
    end if;
  end loop;
end $$;

create or replace function public.create_link_code(p_account uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare v_code text;
begin
  if not private.is_admin() or not exists (
    select 1 from public.accounts where id=p_account and status='open'
  ) then raise exception 'not authorized'; end if;
  v_code := upper(substr(replace(gen_random_uuid()::text,'-',''),1,12) ||
                  substr(replace(gen_random_uuid()::text,'-',''),1,6));
  insert into private.link_codes(account_id,code_hash,expires_at)
    values(p_account,sha256(convert_to(v_code,'UTF8')),now()+interval '10 minutes');
  insert into private.audit(actor,action,entity_id)
    values(auth.uid(),'link_code_created',p_account);
  return v_code;
end $$;

create or replace function public.link_account(p_code text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v private.link_codes%rowtype; v_attempts int;
begin
  if auth.uid() is null then return null; end if;
  insert into private.link_attempts(user_id) values(auth.uid()) on conflict do nothing;
  update private.link_attempts
    set attempts=case when window_started_at<now()-interval '15 minutes' then 1 else attempts+1 end,
        window_started_at=case when window_started_at<now()-interval '15 minutes' then now() else window_started_at end
    where user_id=auth.uid() returning attempts into v_attempts;
  if v_attempts>5 or p_code !~ '^[0-9A-F]{18}$' then return null; end if;
  select * into v from private.link_codes
    where code_hash=sha256(convert_to(p_code,'UTF8')) for update;
  if not found or v.used_at is not null or v.expires_at<now() then return null; end if;
  perform 1 from public.accounts where id=v.account_id and status='open' for update;
  if not found then return null; end if;
  update private.link_codes set used_at=now() where id=v.id;
  insert into public.account_access(account_id,user_id)
    values(v.account_id,auth.uid()) on conflict do nothing;
  insert into private.audit(actor,action,entity_id)
    values(auth.uid(),'account_linked',v.account_id);
  return v.account_id;
end $$;

create or replace function public.record_direct_delivery(p_account uuid,p_product uuid,p_quantity int,p_key uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_price bigint; v_existing public.deliveries%rowtype; v_id uuid;
begin
  if not private.is_admin() or p_key is null or p_quantity not between 1 and 100 then
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

create or replace function public.create_order(p_account uuid,p_items jsonb,p_key uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_requested jsonb; v_saved jsonb;
begin
  if auth.uid() is null or not private.can_access(p_account) or p_key is null then
    raise exception 'not authorized';
  end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 20 then
    raise exception 'invalid items';
  end if;
  if exists(select 1 from jsonb_to_recordset(p_items) as x(product_id uuid,quantity int)
            where x.product_id is null or x.quantity not between 1 and 100) then
    raise exception 'invalid items';
  end if;
  select jsonb_agg(jsonb_build_object('product_id',x.product_id,'quantity',x.quantity)
                   order by x.product_id,x.quantity) into v_requested
    from jsonb_to_recordset(p_items) as x(product_id uuid,quantity int);

  select id into v_id from public.orders where requested_by=auth.uid() and idempotency_key=p_key;
  if v_id is not null then
    select jsonb_agg(jsonb_build_object('product_id',i.product_id,'quantity',i.quantity)
                     order by i.product_id,i.quantity) into v_saved
      from public.order_items i where i.order_id=v_id;
    if v_requested is distinct from v_saved or not exists(
      select 1 from public.orders where id=v_id and account_id=p_account
    ) then raise exception 'key reused'; end if;
    return v_id;
  end if;

  perform 1 from public.accounts where id=p_account and status='open' for update;
  if not found then raise exception 'account unavailable'; end if;
  if exists(select 1 from jsonb_to_recordset(p_items) as x(product_id uuid,quantity int)
            where not exists(select 1 from public.products where id=x.product_id and active)) then
    raise exception 'invalid items';
  end if;
  insert into public.orders(account_id,requested_by,idempotency_key)
    values(p_account,auth.uid(),p_key)
    on conflict(requested_by,idempotency_key) do nothing returning id into v_id;
  if v_id is null then
    select id into v_id from public.orders where requested_by=auth.uid() and idempotency_key=p_key;
    select jsonb_agg(jsonb_build_object('product_id',i.product_id,'quantity',i.quantity)
                     order by i.product_id,i.quantity) into v_saved
      from public.order_items i where i.order_id=v_id;
    if v_requested is distinct from v_saved or not exists(
      select 1 from public.orders where id=v_id and account_id=p_account
    ) then raise exception 'key reused'; end if;
    return v_id;
  end if;
  insert into public.order_items(order_id,product_id,quantity)
    select v_id,x.product_id,x.quantity
    from jsonb_to_recordset(p_items) as x(product_id uuid,quantity int);
  return v_id;
end $$;
