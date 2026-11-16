-- Bootstrap: run manually in SQL editor after creating the Auth user. Never expose this as RPC.
-- insert into public.staff(user_id,role) values ('AUTH_USER_UUID','admin');
create table public.delivery_corrections (id uuid primary key default gen_random_uuid(), delivery_id uuid not null references public.deliveries(id), quantity_delta int not null check (quantity_delta <> 0), reason text not null check (length(trim(reason)) between 5 and 500), corrected_by uuid not null references public.staff(user_id), created_at timestamptz not null default now());
create index corrections_delivery on public.delivery_corrections(delivery_id);
alter table public.delivery_corrections enable row level security;
revoke all on public.delivery_corrections from anon,authenticated;
grant select on public.delivery_corrections to authenticated;
create policy corrections_staff on public.delivery_corrections for select to authenticated using (private.is_staff());
create or replace function public.correct_delivery(p_delivery uuid,p_delta int,p_reason text) returns uuid language plpgsql security definer set search_path = '' as $$ declare v public.deliveries%rowtype; v_id uuid; v_corrected int; begin
 if not private.is_admin() or p_delta=0 or length(trim(p_reason)) not between 5 and 500 then raise exception 'not authorized'; end if;
 select * into v from public.deliveries where id=p_delivery for update; if not found then raise exception 'delivery unavailable'; end if;
 perform 1 from public.accounts where id=v.account_id and status<>'closed' for update; if not found then raise exception 'account closed'; end if;
 select v.quantity+coalesce(sum(quantity_delta),0) into v_corrected from public.delivery_corrections where delivery_id=p_delivery;
 if v_corrected+p_delta<0 then raise exception 'invalid correction'; end if;
 insert into public.delivery_corrections(delivery_id,quantity_delta,reason,corrected_by) values(p_delivery,p_delta,trim(p_reason),auth.uid()) returning id into v_id;
 insert into private.audit(actor,action,entity_id,details) values(auth.uid(),'delivery_corrected',p_delivery,jsonb_build_object('delta',p_delta,'reason',trim(p_reason)));
 return v_id; end $$;
create or replace function public.account_summary(p_account uuid) returns jsonb language plpgsql security definer set search_path = '' as $$ declare v_result jsonb; begin
 if auth.uid() is null or not private.can_access(p_account) then raise exception 'not authorized'; end if;
 select jsonb_build_object('account_id',a.id,'status',a.status,'total_cop',coalesce((select sum((d.quantity+coalesce((select sum(c.quantity_delta) from public.delivery_corrections c where c.delivery_id=d.id),0))*d.unit_price_cop) from public.deliveries d where d.account_id=a.id),0),'paid_cop',coalesce((select p.amount_cop from public.payments p where p.account_id=a.id),0)) into v_result from public.accounts a where a.id=p_account;
 return v_result; end $$;
create or replace function public.confirm_payment(p_account uuid) returns bigint language plpgsql security definer set search_path = '' as $$ declare v_total bigint; begin
 if not private.is_staff() then raise exception 'not authorized'; end if;
 perform 1 from public.accounts where id=p_account and status='paying' for update; if not found then raise exception 'account unavailable'; end if;
 if exists(select 1 from public.orders where account_id=p_account and status in ('pending','taken')) then raise exception 'pending orders'; end if;
 select coalesce(sum((d.quantity+coalesce((select sum(c.quantity_delta) from public.delivery_corrections c where c.delivery_id=d.id),0))*d.unit_price_cop),0) into v_total from public.deliveries d where account_id=p_account;
 insert into public.payments(account_id,amount_cop,received_by) values(p_account,v_total,auth.uid());
 update public.accounts set status='closed',closed_at=now() where id=p_account;
 insert into private.audit(actor,action,entity_id,details) values(auth.uid(),'payment_confirmed',p_account,jsonb_build_object('amount_cop',v_total));
 return v_total; end $$;
revoke all on function public.correct_delivery(uuid,int,text) from public,anon,authenticated;
grant execute on function public.correct_delivery(uuid,int,text) to authenticated;
-- Only admins can change catalog or staff through the SQL dashboard/service backend;
-- no browser grant exists for these writes.
