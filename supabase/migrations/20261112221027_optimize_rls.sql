drop policy staff_self on public.staff;
create policy staff_self on public.staff for select to authenticated
  using (user_id=(select auth.uid()) or (select private.is_admin()));

drop policy customers_staff on public.customers;
drop policy customers_linked_account on public.customers;
create policy customers_read on public.customers for select to authenticated
  using ((select private.is_staff()) or exists (
    select 1 from public.accounts a join public.account_access aa on aa.account_id=a.id
    where a.customer_id=customers.id and aa.user_id=(select auth.uid())
  ));
