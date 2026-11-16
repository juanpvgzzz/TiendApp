-- All mutation functions run as owner because direct table writes are revoked.
create function public.open_account(p_shift uuid,p_customer uuid,p_guest text) returns uuid language plpgsql security definer set search_path = '' as $$ declare v_id uuid; begin
 if not private.is_staff() then raise exception 'not authorized'; end if;
 if (p_customer is null) = (nullif(trim(p_guest),'') is null) then raise exception 'invalid customer'; end if;
 if not exists(select 1 from public.shifts where id=p_shift and closed_at is null) then raise exception 'shift closed'; end if;
 insert into public.accounts(shift_id,customer_id,guest_name,opened_by) values(p_shift,p_customer,nullif(trim(p_guest),''),auth.uid()) returning id into v_id;
 return v_id; end $$;
create function public.search_customers(p_query text,p_limit int default 20) returns table(id uuid,name text,phone text) language plpgsql security definer set search_path = '' as $$ begin
 if not private.is_staff() or length(trim(p_query)) < 2 or p_limit not between 1 and 30 then raise exception 'invalid request'; end if;
 return query select c.id,c.name,c.phone from public.customers c where c.name ilike '%'||replace(replace(trim(p_query),'%','\%'),'_','\_')||'%' escape '\' order by c.name,c.id limit p_limit; end $$;
create function public.create_link_code(p_account uuid) returns text language plpgsql security definer set search_path = '' as $$ declare v_code text; begin
 if not private.is_staff() or not exists(select 1 from public.accounts where id=p_account and status='open') then raise exception 'not authorized'; end if;
 v_code:=upper(encode(gen_random_bytes(9),'hex'));
 insert into private.link_codes(account_id,code_hash,expires_at) values(p_account,digest(v_code,'sha256'),now()+interval '10 minutes');
 insert into private.audit(actor,action,entity_id) values(auth.uid(),'link_code_created',p_account);
 return v_code; end $$;
create function public.link_account(p_code text) returns uuid language plpgsql security definer set search_path = '' as $$ declare v private.link_codes%rowtype; begin
 if auth.uid() is null or p_code !~ '^[0-9A-F]{18}$' then raise exception 'invalid code'; end if;
 select * into v from private.link_codes where code_hash=digest(p_code,'sha256') for update;
 if not found then raise exception 'invalid code'; end if;
 update private.link_codes set attempts=attempts+1 where id=v.id and attempts<5;
 if v.attempts>=5 or v.used_at is not null or v.expires_at<now() or not exists(select 1 from public.accounts where id=v.account_id and status='open') then raise exception 'invalid code'; end if;
 update private.link_codes set used_at=now() where id=v.id;
 insert into public.account_access(account_id,user_id) values(v.account_id,auth.uid()) on conflict do nothing;
 insert into private.audit(actor,action,entity_id) values(auth.uid(),'account_linked',v.account_id);
 return v.account_id; end $$;
create function public.create_order(p_account uuid,p_items jsonb,p_key uuid) returns uuid language plpgsql security definer set search_path = '' as $$ declare v_id uuid; v_count int; begin
 if auth.uid() is null or not private.can_access(p_account) or p_key is null then raise exception 'not authorized'; end if;
 perform 1 from public.accounts where id=p_account and status='open' for update;
 if not found then raise exception 'account unavailable'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 20 then raise exception 'invalid items'; end if;
 if exists(select 1 from jsonb_to_recordset(p_items) as x(product_id uuid,quantity int) where x.product_id is null or x.quantity not between 1 and 100 or not exists(select 1 from public.products where id=x.product_id and active)) then raise exception 'invalid items'; end if;
 insert into public.orders(account_id,requested_by,idempotency_key) values(p_account,auth.uid(),p_key) on conflict(requested_by,idempotency_key) do nothing returning id into v_id;
 if v_id is null then select id into v_id from public.orders where requested_by=auth.uid() and idempotency_key=p_key and account_id=p_account; if v_id is null then raise exception 'key reused'; end if; return v_id; end if;
 insert into public.order_items(order_id,product_id,quantity) select v_id,x.product_id,x.quantity from jsonb_to_recordset(p_items) as x(product_id uuid,quantity int);
 return v_id; end $$;
create function public.take_order(p_order uuid) returns void language plpgsql security definer set search_path = '' as $$ begin
 if not private.is_staff() then raise exception 'not authorized'; end if;
 update public.orders set status='taken',taken_by=auth.uid() where id=p_order and status='pending';
 if not found then raise exception 'order unavailable'; end if; end $$;
create function public.confirm_delivery(p_item uuid,p_quantity int,p_key uuid) returns uuid language plpgsql security definer set search_path = '' as $$ declare v_item public.order_items%rowtype; v_account uuid; v_price bigint; v_id uuid; begin
 if not private.is_staff() or p_key is null or p_quantity not between 1 and 100 then raise exception 'not authorized'; end if;
 select * into v_item from public.order_items where id=p_item for update;
 if not found then raise exception 'item unavailable'; end if;
 select account_id into v_account from public.orders where id=v_item.order_id and status in ('pending','taken');
 perform 1 from public.accounts where id=v_account and status='open' for update;
 if not found then raise exception 'account unavailable'; end if;
 select id into v_id from public.deliveries where delivered_by=auth.uid() and idempotency_key=p_key;
 if found then return v_id; end if;
 if v_item.delivered_quantity+p_quantity>v_item.quantity then raise exception 'excess quantity'; end if;
 select price_cop into v_price from public.products where id=v_item.product_id;
 update public.order_items set delivered_quantity=delivered_quantity+p_quantity where id=p_item;
 insert into public.deliveries(account_id,order_item_id,product_id,quantity,unit_price_cop,delivered_by,idempotency_key) values(v_account,p_item,v_item.product_id,p_quantity,v_price,auth.uid(),p_key) returning id into v_id;
 if not exists(select 1 from public.order_items where order_id=v_item.order_id and delivered_quantity<quantity) then update public.orders set status='done' where id=v_item.order_id; end if;
 return v_id; end $$;
create function public.record_direct_delivery(p_account uuid,p_product uuid,p_quantity int,p_key uuid) returns uuid language plpgsql security definer set search_path = '' as $$ declare v_price bigint; v_id uuid; begin
 if not private.is_staff() or p_key is null or p_quantity not between 1 and 100 then raise exception 'not authorized'; end if;
 perform 1 from public.accounts where id=p_account and status='open' for update; if not found then raise exception 'account unavailable'; end if;
 select id into v_id from public.deliveries where delivered_by=auth.uid() and idempotency_key=p_key; if found then return v_id; end if;
 select price_cop into v_price from public.products where id=p_product and active; if not found then raise exception 'product unavailable'; end if;
 insert into public.deliveries(account_id,product_id,quantity,unit_price_cop,delivered_by,idempotency_key) values(p_account,p_product,p_quantity,v_price,auth.uid(),p_key) returning id into v_id;
 return v_id; end $$;
create function public.request_payment(p_account uuid) returns uuid language plpgsql security definer set search_path = '' as $$ declare v_id uuid; begin
 if auth.uid() is null or not private.can_access(p_account) then raise exception 'not authorized'; end if;
 update public.accounts set status='paying' where id=p_account and status='open';
 if not found and not exists(select 1 from public.accounts where id=p_account and status='paying') then raise exception 'account unavailable'; end if;
 insert into public.payment_requests(account_id,requested_by) values(p_account,auth.uid()) on conflict do nothing returning id into v_id;
 if v_id is null then select id into v_id from public.payment_requests where account_id=p_account and cancelled_at is null; end if;
 return v_id; end $$;
create function public.take_payment_request(p_request uuid) returns void language plpgsql security definer set search_path = '' as $$ begin
 if not private.is_staff() then raise exception 'not authorized'; end if;
 update public.payment_requests set taken_by=auth.uid() where id=p_request and taken_by is null and cancelled_at is null;
 if not found then raise exception 'request unavailable'; end if; end $$;
create function public.cancel_payment_request(p_request uuid) returns void language plpgsql security definer set search_path = '' as $$ declare v_account uuid; begin
 if not private.is_staff() then raise exception 'not authorized'; end if;
 select account_id into v_account from public.payment_requests where id=p_request and cancelled_at is null;
 perform 1 from public.accounts where id=v_account and status='paying' for update;
 if not found then raise exception 'request unavailable'; end if;
 update public.payment_requests set cancelled_at=now() where id=p_request;
 update public.accounts set status='open' where id=v_account; end $$;
create function public.confirm_payment(p_account uuid) returns bigint language plpgsql security definer set search_path = '' as $$ declare v_total bigint; begin
 if not private.is_staff() then raise exception 'not authorized'; end if;
 perform 1 from public.accounts where id=p_account and status='paying' for update; if not found then raise exception 'account unavailable'; end if;
 if exists(select 1 from public.orders where account_id=p_account and status in ('pending','taken')) then raise exception 'pending orders'; end if;
 select coalesce(sum(quantity*unit_price_cop),0) into v_total from public.deliveries where account_id=p_account;
 insert into public.payments(account_id,amount_cop,received_by) values(p_account,v_total,auth.uid());
 update public.accounts set status='closed',closed_at=now() where id=p_account;
 insert into private.audit(actor,action,entity_id,details) values(auth.uid(),'payment_confirmed',p_account,jsonb_build_object('amount_cop',v_total));
 return v_total; end $$;
create function public.account_summary(p_account uuid) returns jsonb language plpgsql security definer set search_path = '' as $$ declare v_result jsonb; begin
 if auth.uid() is null or not private.can_access(p_account) then raise exception 'not authorized'; end if;
 select jsonb_build_object('account_id',a.id,'status',a.status,'total_cop',coalesce((select sum(d.quantity*d.unit_price_cop) from public.deliveries d where d.account_id=a.id),0),'paid_cop',coalesce((select p.amount_cop from public.payments p where p.account_id=a.id),0)) into v_result from public.accounts a where a.id=p_account;
 return v_result; end $$;
revoke all on all functions in schema public from public,anon,authenticated;
grant execute on function public.open_account(uuid,uuid,text),public.search_customers(text,int),public.create_link_code(uuid),public.link_account(text),public.create_order(uuid,jsonb,uuid),public.take_order(uuid),public.confirm_delivery(uuid,int,uuid),public.record_direct_delivery(uuid,uuid,int,uuid),public.request_payment(uuid),public.take_payment_request(uuid),public.cancel_payment_request(uuid),public.confirm_payment(uuid),public.account_summary(uuid) to authenticated;
