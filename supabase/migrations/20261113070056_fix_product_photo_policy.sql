drop policy product_photo_upload on storage.objects;
create policy product_photo_upload on storage.objects for insert to authenticated
with check (
  bucket_id='product-photos' and private.is_admin()
  and storage.objects.name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.webp$'
  and exists(select 1 from public.products p where p.id=split_part(storage.objects.name,'/',1)::uuid)
);
