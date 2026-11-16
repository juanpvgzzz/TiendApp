create policy account_access_revocation_receive
on realtime.messages for select to authenticated
using (
  extension = 'broadcast'
  and (select realtime.topic()) = 'account-access:' || (select auth.uid())::text
);

create function private.notify_account_access_revoked()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into private.audit(actor, action, entity_id, details)
  values (auth.uid(), 'account_access_revoked', old.account_id, jsonb_build_object('user_id', old.user_id));
  perform realtime.send(
    jsonb_build_object('account_id', old.account_id),
    'revoked',
    'account-access:' || old.user_id::text,
    true
  );
  return old;
end;
$$;

revoke all on function private.notify_account_access_revoked() from public, anon, authenticated;

create trigger account_access_revoked
  after delete on public.account_access
  for each row execute function private.notify_account_access_revoked();
