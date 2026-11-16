create or replace function public.link_account(p_code text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v private.link_codes%rowtype; v_attempts int; v_account uuid;
begin
  if auth.uid() is null then return null; end if;
  insert into private.link_attempts(user_id) values(auth.uid()) on conflict do nothing;
  update private.link_attempts
    set attempts=case when window_started_at<now()-interval '15 minutes' then 1 else attempts+1 end,
        window_started_at=case when window_started_at<now()-interval '15 minutes' then now() else window_started_at end
    where user_id=auth.uid() returning attempts into v_attempts;
  if v_attempts>5 or p_code !~ '^[0-9A-F]{18}$' then return null; end if;
  select account_id into v_account from private.link_codes
    where code_hash=sha256(convert_to(p_code,'UTF8'));
  if v_account is null then return null; end if;
  perform 1 from public.accounts where id=v_account and status='open' for update;
  if not found then return null; end if;
  select * into v from private.link_codes
    where code_hash=sha256(convert_to(p_code,'UTF8')) for update;
  if not found or v.used_at is not null or v.revoked_at is not null or v.expires_at<now() then return null; end if;
  update private.link_codes set used_at=now() where id=v.id;
  insert into public.account_access(account_id,user_id) values(v_account,auth.uid()) on conflict do nothing;
  insert into private.audit(actor,action,entity_id) values(auth.uid(),'account_linked',v_account);
  return v_account;
end $$;

alter table public.delivery_corrections add column idempotency_key uuid;
create unique index corrections_idempotency_key on public.delivery_corrections(corrected_by,idempotency_key)
  where idempotency_key is not null;

create function public.correct_delivery(p_delivery uuid,p_delta int,p_reason text,p_key uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v public.deliveries%rowtype; v_existing public.delivery_corrections%rowtype;
  v_account uuid; v_id uuid; v_corrected int;
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
  if v_corrected+p_delta<0 or (v.order_item_id is not null and
    v_corrected+p_delta>(select quantity from public.order_items where id=v.order_item_id)) then
    raise exception 'invalid correction';
  end if;
  insert into public.delivery_corrections(delivery_id,quantity_delta,reason,corrected_by,idempotency_key)
    values(p_delivery,p_delta,trim(p_reason),auth.uid(),p_key) returning id into v_id;
  insert into public.account_events(account_id,kind) values(v_account,'consumption_corrected');
  insert into private.audit(actor,action,entity_id,details)
    values(auth.uid(),'delivery_corrected',p_delivery,jsonb_build_object('delta',p_delta,'reason',trim(p_reason)));
  return v_id;
end $$;

revoke all on function public.correct_delivery(uuid,int,text) from public,anon,authenticated;
revoke all on function public.correct_delivery(uuid,int,text,uuid) from public,anon,authenticated;
grant execute on function public.correct_delivery(uuid,int,text,uuid) to authenticated;
