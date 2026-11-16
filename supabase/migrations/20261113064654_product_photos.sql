alter table public.products add column photo_path text;

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('product-photos','product-photos',true,2097152,array['image/webp'])
on conflict (id) do nothing;

create policy product_photo_upload on storage.objects for insert to authenticated
with check (
  bucket_id='product-photos' and private.is_admin()
  and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.webp$'
  and exists(select 1 from public.products where id=split_part(name,'/',1)::uuid)
);

create policy product_photo_delete on storage.objects for delete to authenticated
using (bucket_id='product-photos' and private.is_admin());

create policy product_photo_admin_read on storage.objects for select to authenticated
using (bucket_id='product-photos' and private.is_admin());

create function public.set_product_photo(p_product uuid,p_path text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_admin() or p_product is null then raise exception 'not authorized'; end if;
  if p_path is not null and (
    p_path !~ ('^'||p_product::text||'/[0-9a-f-]{36}\.webp$')
    or not exists(select 1 from storage.objects where bucket_id='product-photos' and name=p_path)
  ) then raise exception 'invalid photo'; end if;
  update public.products set photo_path=p_path where id=p_product;
  if not found then raise exception 'product unavailable'; end if;
  insert into private.audit(actor,action,entity_id,details)
  values(auth.uid(),'product_photo_updated',p_product,jsonb_build_object('has_photo',p_path is not null));
end $$;

revoke all on function public.set_product_photo(uuid,text) from public,anon,authenticated;
grant execute on function public.set_product_photo(uuid,text) to authenticated;
