create or replace function public.create_link_code(p_account uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare v_code text;
begin
  if not private.is_staff() then raise exception 'not authorized'; end if;
  perform 1 from public.accounts where id=p_account and status='open' for update;
  if not found then raise exception 'account unavailable'; end if;
  update private.link_codes set revoked_at=now()
    where account_id=p_account and used_at is null and revoked_at is null;
  v_code := upper(encode(extensions.gen_random_bytes(9),'hex'));
  insert into private.link_codes(account_id,code_hash,expires_at)
    values(p_account,sha256(convert_to(v_code,'UTF8')),now()+interval '10 minutes');
  insert into private.audit(actor,action,entity_id) values(auth.uid(),'link_code_created',p_account);
  return v_code;
end $$;
