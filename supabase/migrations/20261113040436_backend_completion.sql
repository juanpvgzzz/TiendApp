create or replace function private.is_staff() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.staff where user_id=auth.uid() and active)
$$;

create unique index customers_phone_unique on public.customers
  ((regexp_replace(phone, '[^0-9]', '', 'g')))
  where phone is not null and regexp_replace(phone, '[^0-9]', '', 'g') <> '';

create or replace function public.register_customer(p_name text, p_phone text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_phone text;
begin
  if not private.is_staff() or p_name is null or length(trim(p_name)) not between 1 and 120 then
    raise exception 'invalid request';
  end if;
  v_phone := nullif(trim(p_phone), '');
  if v_phone is not null and (length(v_phone) > 30 or length(regexp_replace(v_phone,'[^0-9]','','g')) < 7) then
    raise exception 'invalid phone';
  end if;
  insert into public.customers(name,phone) values(trim(p_name),v_phone)
    on conflict do nothing returning id into v_id;
  if v_id is null then raise exception 'phone already registered'; end if;
  insert into private.audit(actor,action,entity_id) values(auth.uid(),'customer_registered',v_id);
  return v_id;
end $$;

create or replace function public.open_account(p_shift uuid,p_customer uuid,p_guest text,p_key uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_guest text;
begin
  if not private.is_staff() or p_key is null then raise exception 'not authorized'; end if;
  v_guest := nullif(trim(p_guest),'');
  select id into v_id from public.accounts where opened_by=auth.uid() and opening_key=p_key;
  if found then
    if not exists(select 1 from public.accounts where id=v_id and shift_id=p_shift
      and customer_id is not distinct from p_customer and guest_name is not distinct from v_guest) then
      raise exception 'key reused';
    end if;
    return v_id;
  end if;
  if (p_customer is null) = (v_guest is null) or length(v_guest)>120 then raise exception 'invalid customer'; end if;
  perform 1 from public.shifts where id=p_shift and closed_at is null for update;
  if not found then raise exception 'shift closed'; end if;
  insert into public.accounts(shift_id,customer_id,guest_name,opened_by,opening_key)
    values(p_shift,p_customer,v_guest,auth.uid(),p_key) on conflict do nothing returning id into v_id;
  if v_id is null then
    select id into v_id from public.accounts where opened_by=auth.uid() and opening_key=p_key
      and shift_id=p_shift and customer_id is not distinct from p_customer
      and guest_name is not distinct from v_guest;
    if v_id is null then raise exception 'account unavailable or key reused'; end if;
  else
    insert into private.audit(actor,action,entity_id) values(auth.uid(),'account_opened',v_id);
  end if;
  return v_id;
end $$;

create function public.close_shift(p_shift uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_admin() then raise exception 'not authorized'; end if;
  perform 1 from public.shifts where id=p_shift and closed_at is null for update;
  if not found then raise exception 'shift unavailable'; end if;
  if exists(select 1 from public.accounts where shift_id=p_shift and status<>'closed') then
    raise exception 'active accounts';
  end if;
  update public.shifts set closed_at=now() where id=p_shift;
  insert into private.audit(actor,action,entity_id) values(auth.uid(),'shift_closed',p_shift);
end $$;

create function public.set_employee(p_user uuid,p_name text,p_active boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_admin() or p_user is null or p_name is null
     or length(trim(p_name)) not between 2 and 80 or p_active is null then
    raise exception 'not authorized';
  end if;
  if not exists(select 1 from auth.users where id=p_user and email_confirmed_at is not null) then
    raise exception 'verified Auth user required';
  end if;
  insert into public.staff(user_id,role,display_name,active)
    values(p_user,'employee',trim(p_name),p_active)
    on conflict(user_id) do update set display_name=excluded.display_name,active=excluded.active
      where staff.role='employee';
  if not found then raise exception 'admin role cannot be changed'; end if;
  insert into private.audit(actor,action,entity_id,details)
    values(auth.uid(),'employee_changed',p_user,jsonb_build_object('active',p_active));
end $$;

alter table private.link_codes add column revoked_at timestamptz;
create index link_codes_account_active on private.link_codes(account_id) where used_at is null and revoked_at is null;

create or replace function public.create_link_code(p_account uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare v_code text;
begin
  if not private.is_staff() then raise exception 'not authorized'; end if;
  perform 1 from public.accounts where id=p_account and status='open' for update;
  if not found then raise exception 'account unavailable'; end if;
  update private.link_codes set revoked_at=now()
    where account_id=p_account and used_at is null and revoked_at is null;
  v_code := upper(encode(gen_random_bytes(9),'hex'));
  insert into private.link_codes(account_id,code_hash,expires_at)
    values(p_account,sha256(convert_to(v_code,'UTF8')),now()+interval '10 minutes');
  insert into private.audit(actor,action,entity_id) values(auth.uid(),'link_code_created',p_account);
  return v_code;
end $$;

create function public.revoke_link_codes(p_account uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_staff() then raise exception 'not authorized'; end if;
  perform 1 from public.accounts where id=p_account and status<>'closed' for update;
  if not found then raise exception 'account unavailable'; end if;
  update private.link_codes set revoked_at=now()
    where account_id=p_account and used_at is null and revoked_at is null;
  insert into private.audit(actor,action,entity_id) values(auth.uid(),'link_codes_revoked',p_account);
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
  select * into v from private.link_codes where code_hash=sha256(convert_to(p_code,'UTF8')) for update;
  if not found or v.used_at is not null or v.revoked_at is not null or v.expires_at<now() then return null; end if;
  perform 1 from public.accounts where id=v.account_id and status='open' for update;
  if not found then return null; end if;
  update private.link_codes set used_at=now() where id=v.id;
  insert into public.account_access(account_id,user_id) values(v.account_id,auth.uid()) on conflict do nothing;
  insert into private.audit(actor,action,entity_id) values(auth.uid(),'account_linked',v.account_id);
  return v.account_id;
end $$;

create or replace function public.take_order(p_order uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_account uuid;
begin
  if not private.is_staff() then raise exception 'not authorized'; end if;
  select account_id into v_account from public.orders where id=p_order;
  perform 1 from public.accounts where id=v_account and status='open' for update;
  if not found then raise exception 'account unavailable'; end if;
  update public.orders set status='taken',taken_by=auth.uid() where id=p_order and status='pending';
  if not found then raise exception 'order unavailable'; end if;
end $$;

create or replace function public.take_payment_request(p_request uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_account uuid;
begin
  if not private.is_staff() then raise exception 'not authorized'; end if;
  select account_id into v_account from public.payment_requests where id=p_request;
  perform 1 from public.accounts where id=v_account and status='paying' for update;
  if not found then raise exception 'request unavailable'; end if;
  update public.payment_requests set taken_by=auth.uid()
    where id=p_request and taken_by is null and cancelled_at is null;
  if not found then raise exception 'request unavailable'; end if;
end $$;

create or replace function public.confirm_payment(p_account uuid,p_method text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare v_total bigint;
begin
  if not private.is_staff() or p_method not in ('cash','transfer') then raise exception 'not authorized'; end if;
  perform 1 from public.accounts where id=p_account and status='paying' for update;
  if not found then raise exception 'account unavailable'; end if;
  if exists(select 1 from public.orders where account_id=p_account and status in ('pending','taken')) then
    raise exception 'pending orders';
  end if;
  select coalesce(sum((d.quantity+coalesce((select sum(c.quantity_delta)
    from public.delivery_corrections c where c.delivery_id=d.id),0))*d.unit_price_cop),0)
    into v_total from public.deliveries d where d.account_id=p_account;
  insert into public.payments(account_id,amount_cop,received_by,method)
    values(p_account,v_total,auth.uid(),p_method);
  update public.accounts set status='closed',closed_at=now() where id=p_account;
  insert into private.audit(actor,action,entity_id,details)
    values(auth.uid(),'payment_confirmed',p_account,jsonb_build_object('amount_cop',v_total,'method',p_method));
  return v_total;
end $$;

create function public.account_history(p_customer uuid default null,p_from timestamptz default null,
  p_to timestamptz default null,p_shift uuid default null)
returns table(account_id uuid,customer_id uuid,guest_name text,shift_id uuid,opened_at timestamptz,
  closed_at timestamptz,status public.account_status,total_cop bigint,paid_cop bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.is_admin() then raise exception 'not authorized'; end if;
  return query select a.id,a.customer_id,a.guest_name,a.shift_id,a.opened_at,a.closed_at,a.status,
    coalesce((select sum((d.quantity+coalesce((select sum(c.quantity_delta)
      from public.delivery_corrections c where c.delivery_id=d.id),0))*d.unit_price_cop)
      from public.deliveries d where d.account_id=a.id),0)::bigint,
    coalesce(p.amount_cop,0)
    from public.accounts a left join public.payments p on p.account_id=a.id
    where (p_customer is null or a.customer_id=p_customer)
      and (p_shift is null or a.shift_id=p_shift)
      and (p_from is null or a.opened_at>=p_from)
      and (p_to is null or a.opened_at<p_to)
    order by a.opened_at desc,a.id limit 500;
end $$;

create function public.basic_report(p_from timestamptz,p_to timestamptz)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_result jsonb;
begin
  if not private.is_admin() or p_from is null or p_to is null or p_from>=p_to then
    raise exception 'invalid request';
  end if;
  select jsonb_build_object(
    'total_cop',coalesce(sum(p.amount_cop),0),
    'payments',count(p.id),
    'methods',coalesce((select jsonb_object_agg(method,amount) from (
      select method,sum(amount_cop) amount from public.payments
      where received_at>=p_from and received_at<p_to group by method) m),'{}'::jsonb),
    'products',coalesce((select jsonb_agg(jsonb_build_object('product_id',product_id,'name',name,
      'quantity',quantity,'amount_cop',amount) order by quantity desc) from (
      select d.product_id,pr.name,sum(d.quantity+coalesce((select sum(c.quantity_delta)
        from public.delivery_corrections c where c.delivery_id=d.id),0)) quantity,
        sum((d.quantity+coalesce((select sum(c.quantity_delta)
        from public.delivery_corrections c where c.delivery_id=d.id),0))*d.unit_price_cop) amount
      from public.deliveries d join public.products pr on pr.id=d.product_id
      join public.payments paid on paid.account_id=d.account_id
      where paid.received_at>=p_from and paid.received_at<p_to
      group by d.product_id,pr.name order by quantity desc limit 20) x),'[]'::jsonb)
  ) into v_result from public.payments p where p.received_at>=p_from and p.received_at<p_to;
  return v_result;
end $$;

create function public.audit_history(p_limit int default 100)
returns table(id uuid,actor uuid,action text,entity_id uuid,details jsonb,created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.is_admin() or p_limit not between 1 and 500 then raise exception 'not authorized'; end if;
  return query select a.id,a.actor,a.action,a.entity_id,a.details,a.created_at
    from private.audit a order by a.created_at desc,a.id limit p_limit;
end $$;

create table public.account_events (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.accounts(id),
  kind text not null check (kind in ('consumption_corrected')),
  created_at timestamptz not null default now()
);
create index account_events_account on public.account_events(account_id,created_at);
alter table public.account_events enable row level security;
revoke all on public.account_events from public,anon,authenticated;
grant select on public.account_events to authenticated;
create policy account_events_read on public.account_events for select to authenticated
  using (private.can_access(account_id));
alter publication supabase_realtime add table public.account_events;

create or replace function public.correct_delivery(p_delivery uuid,p_delta int,p_reason text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v public.deliveries%rowtype; v_id uuid; v_corrected int;
begin
  if not private.is_admin() or p_delta is null or p_delta=0 or p_reason is null
    or length(trim(p_reason)) not between 5 and 500 then raise exception 'not authorized'; end if;
  select * into v from public.deliveries where id=p_delivery for update;
  if not found then raise exception 'delivery unavailable'; end if;
  perform 1 from public.accounts where id=v.account_id and status<>'closed' for update;
  if not found then raise exception 'account closed'; end if;
  select v.quantity+coalesce(sum(quantity_delta),0) into v_corrected
    from public.delivery_corrections where delivery_id=p_delivery;
  if v_corrected+p_delta<0 or (v.order_item_id is not null and
    v_corrected+p_delta>(select quantity from public.order_items where id=v.order_item_id)) then
    raise exception 'invalid correction';
  end if;
  insert into public.delivery_corrections(delivery_id,quantity_delta,reason,corrected_by)
    values(p_delivery,p_delta,trim(p_reason),auth.uid()) returning id into v_id;
  insert into public.account_events(account_id,kind) values(v.account_id,'consumption_corrected');
  insert into private.audit(actor,action,entity_id,details)
    values(auth.uid(),'delivery_corrected',p_delivery,jsonb_build_object('delta',p_delta,'reason',trim(p_reason)));
  return v_id;
end $$;

revoke all on function public.close_shift(uuid),public.set_employee(uuid,text,boolean),
  public.revoke_link_codes(uuid),public.account_history(uuid,timestamptz,timestamptz,uuid),
  public.basic_report(timestamptz,timestamptz),public.audit_history(int)
  from public,anon,authenticated;
grant execute on function public.close_shift(uuid),public.set_employee(uuid,text,boolean),
  public.revoke_link_codes(uuid),public.account_history(uuid,timestamptz,timestamptz,uuid),
  public.basic_report(timestamptz,timestamptz),public.audit_history(int) to authenticated;
