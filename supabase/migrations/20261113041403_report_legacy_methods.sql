create or replace function public.basic_report(p_from timestamptz,p_to timestamptz)
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
      select coalesce(method,'unspecified') method,sum(amount_cop) amount from public.payments
      where received_at>=p_from and received_at<p_to group by coalesce(method,'unspecified')) m),'{}'::jsonb),
    'responsibles',coalesce((select jsonb_agg(jsonb_build_object('user_id',user_id,
      'name',name,'payments',payments,'amount_cop',amount)) from (
      select s.user_id,s.display_name name,count(p2.id) payments,sum(p2.amount_cop) amount
      from public.payments p2 join public.staff s on s.user_id=p2.received_by
      where p2.received_at>=p_from and p2.received_at<p_to
      group by s.user_id,s.display_name order by amount desc) r),'[]'::jsonb),
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
