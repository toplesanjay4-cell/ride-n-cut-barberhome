-- Only the manually bootstrapped owner may hold the owner role.
-- Owners can manage staff accounts, but cannot mint, modify, or delete owner roles.
drop policy if exists "rnc owner manages roles" on public.user_roles;

drop policy if exists "rnc owner creates staff roles" on public.user_roles;
create policy "rnc owner creates staff roles" on public.user_roles
  for insert to authenticated
  with check (
    role = 'staff'
    and public.rnc_has_role(array['owner'])
  );

drop policy if exists "rnc owner updates staff roles" on public.user_roles;
create policy "rnc owner updates staff roles" on public.user_roles
  for update to authenticated
  using (
    role = 'staff'
    and public.rnc_has_role(array['owner'])
  )
  with check (
    role = 'staff'
    and public.rnc_has_role(array['owner'])
  );

drop policy if exists "rnc owner deletes staff roles" on public.user_roles;
create policy "rnc owner deletes staff roles" on public.user_roles
  for delete to authenticated
  using (
    role = 'staff'
    and public.rnc_has_role(array['owner'])
  );

comment on policy "rnc owner creates staff roles" on public.user_roles is
  'Owner may provision staff only; owner role must be bootstrapped manually by a trusted operator.';
