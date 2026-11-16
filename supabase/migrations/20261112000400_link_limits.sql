create table private.link_attempts (user_id uuid primary key references auth.users(id), window_started_at timestamptz not null default now(), attempts int not null default 0 check (attempts >= 0));
create or replace function public.link_account(p_code text) returns uuid language plpgsql security definer set search_path = '' as $$ declare v private.link_codes%rowtype; v_attempts int; v_account uuid; begin
 if auth.uid() is null then return null; end if;
 insert into private.link_attempts(user_id) values(auth.uid()) on conflict do nothing;
 select attempts into v_attempts from private.link_attempts where user_id=auth.uid() for update;
 update private.link_attempts set attempts=case when window_started_at<now()-interval '15 minutes' then 1 else attempts+1 end,window_started_at=case when window_started_at<now()-interval '15 minutes' then now() else window_started_at end where user_id=auth.uid() returning attempts into v_attempts;
 if v_attempts>5 or p_code !~ '^[0-9A-F]{18}$' then return null; end if;
 select * into v from private.link_codes where code_hash=digest(p_code,'sha256') for update;
 if not found then return null; end if;
 if v.used_at is not null or v.expires_at<now() or not exists(select 1 from public.accounts where id=v.account_id and status='open') then return null; end if;
 update private.link_codes set used_at=now() where id=v.id;
 insert into public.account_access(account_id,user_id) values(v.account_id,auth.uid()) on conflict do nothing;
 insert into private.audit(actor,action,entity_id) values(auth.uid(),'account_linked',v.account_id);
 v_account:=v.account_id; return v_account; end $$;
create or replace function public.confirm_delivery(p_item uuid,p_quantity int,p_key uuid) returns uuid language plpgsql security definer set search_path = '' as $$ declare v_item public.order_items%rowtype; v_account uuid; v_price bigint; v_id uuid; begin
 if not private.is_staff() or p_key is null or p_quantity not between 1 and 100 then raise exception 'not authorized'; end if;
 select id into v_id from public.deliveries where delivered_by=auth.uid() and idempotency_key=p_key;
 if found then return v_id; end if;
 select * into v_item from public.order_items where id=p_item for update;
 if not found then raise exception 'item unavailable'; end if;
 select account_id into v_account from public.orders where id=v_item.order_id and status in ('pending','taken');
 perform 1 from public.accounts where id=v_account and status='open' for update;
 if not found then raise exception 'account unavailable'; end if;
 if v_item.delivered_quantity+p_quantity>v_item.quantity then raise exception 'excess quantity'; end if;
 select price_cop into v_price from public.products where id=v_item.product_id;
 update public.order_items set delivered_quantity=delivered_quantity+p_quantity where id=p_item;
 insert into public.deliveries(account_id,order_item_id,product_id,quantity,unit_price_cop,delivered_by,idempotency_key) values(v_account,p_item,v_item.product_id,p_quantity,v_price,auth.uid(),p_key) returning id into v_id;
 if not exists(select 1 from public.order_items where order_id=v_item.order_id and delivered_quantity<quantity) then update public.orders set status='done' where id=v_item.order_id; end if;
 return v_id; end $$;
