create or replace function public.create_link_code(p_account uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare v_code text;
begin
  if not private.is_staff() then raise exception 'not authorized'; end if;
  perform 1 from public.accounts where id=p_account and status<>'closed' for update;
  if not found then raise exception 'account unavailable'; end if;
  update private.link_codes set revoked_at=now()
    where account_id=p_account and used_at is null and revoked_at is null;
  v_code := upper(encode(extensions.gen_random_bytes(9),'hex'));
  insert into private.link_codes(account_id,code_hash,expires_at)
    values(p_account,sha256(convert_to(v_code,'UTF8')),now()+interval '10 minutes');
  insert into private.audit(actor,action,entity_id) values(auth.uid(),'link_code_created',p_account);
  return v_code;
end $$;

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
  perform 1 from public.accounts where id=v_account and status<>'closed' for update;
  if not found then return null; end if;
  select * into v from private.link_codes
    where code_hash=sha256(convert_to(p_code,'UTF8')) for update;
  if not found or v.used_at is not null or v.revoked_at is not null or v.expires_at<now() then return null; end if;
  update private.link_codes set used_at=now() where id=v.id;
  insert into public.account_access(account_id,user_id) values(v_account,auth.uid()) on conflict do nothing;
  insert into private.audit(actor,action,entity_id) values(auth.uid(),'account_linked',v_account);
  return v_account;
end $$;
