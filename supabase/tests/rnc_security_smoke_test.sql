-- Run this script in the Supabase SQL Editor against a NON-PRODUCTION
-- staging project after applying every migration. Run as the postgres role.
-- It is read-only: failures raise an exception and do not mutate application data.

do $rnc_test$
declare
  v_enabled boolean;
  v_policy_count integer;
begin
  -- Core role table must be protected by RLS.
  select c.relrowsecurity into v_enabled
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'user_roles';
  if coalesce(v_enabled, false) is not true then
    raise exception 'FAIL: public.user_roles must have RLS enabled';
  end if;

  -- The old all-actions owner policy must not survive the hardening migration.
  select count(*) into v_policy_count
  from pg_policies
  where schemaname = 'public'
    and tablename = 'user_roles'
    and policyname = 'rnc owner manages roles';
  if v_policy_count <> 0 then
    raise exception 'FAIL: broad owner role-management policy still exists';
  end if;

  -- Verify the policy expressions, not just their names: each write path
  -- must require an owner actor and must restrict affected rows to role=staff.
  select count(*) into v_policy_count
  from pg_policies
  where schemaname = 'public'
    and tablename = 'user_roles'
    and (
      (policyname = 'rnc owner creates staff roles'
       and cmd = 'INSERT'
       and coalesce(with_check, '') ilike '%staff%'
       and coalesce(with_check, '') ilike '%rnc_has_role%owner%')
      or
      (policyname = 'rnc owner updates staff roles'
       and cmd = 'UPDATE'
       and coalesce(qual, '') ilike '%staff%'
       and coalesce(qual, '') ilike '%rnc_has_role%owner%'
       and coalesce(with_check, '') ilike '%staff%'
       and coalesce(with_check, '') ilike '%rnc_has_role%owner%')
      or
      (policyname = 'rnc owner deletes staff roles'
       and cmd = 'DELETE'
       and coalesce(qual, '') ilike '%staff%'
       and coalesce(qual, '') ilike '%rnc_has_role%owner%')
    );
  if v_policy_count <> 3 then
    raise exception 'FAIL: staff role policies are missing or do not enforce staff-only owner access';
  end if;

  -- Direct client writes to payments are forbidden; mutations go through RPCs.
  if has_table_privilege('anon', 'public.booking_payments', 'INSERT')
     or has_table_privilege('anon', 'public.booking_payments', 'UPDATE')
     or has_table_privilege('anon', 'public.booking_payments', 'DELETE')
     or has_table_privilege('authenticated', 'public.booking_payments', 'INSERT')
     or has_table_privilege('authenticated', 'public.booking_payments', 'UPDATE')
     or has_table_privilege('authenticated', 'public.booking_payments', 'DELETE') then
    raise exception 'FAIL: direct client write privilege remains on booking_payments';
  end if;

  -- Public settings are column-scoped, not table-wide.
  if has_table_privilege('anon', 'public.site_settings', 'SELECT') then
    raise exception 'FAIL: anon still has table-wide SELECT on site_settings';
  end if;
  if not has_column_privilege('anon', 'public.site_settings', 'brand_name', 'SELECT')
     or not has_column_privilege('anon', 'public.site_settings', 'booking_buffer_minutes', 'SELECT') then
    raise exception 'FAIL: required public site_settings columns are not readable';
  end if;
  if has_column_privilege('anon', 'public.site_settings', 'origin_latitude', 'SELECT')
     or has_column_privilege('anon', 'public.site_settings', 'origin_longitude', 'SELECT')
     or has_column_privilege('anon', 'public.site_settings', 'automatic_expense_rules', 'SELECT') then
    raise exception 'FAIL: private site_settings columns are exposed to anon';
  end if;

  -- Service-only price control: staff cannot create or edit customer quotes.
  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'booking_price_quotes'
      and policyname in ('rnc staff creates quotes', 'rnc staff updates quotes')
  ) then
    raise exception 'FAIL: a staff quote write policy remains';
  end if;
  select count(*) into v_policy_count
  from pg_policies
  where schemaname = 'public'
    and tablename = 'booking_price_quotes'
    and policyname = 'rnc owner creates quotes'
    and cmd = 'INSERT'
    and coalesce(with_check, '') ilike '%rnc_has_role%owner%';
  if v_policy_count <> 1 then
    raise exception 'FAIL: owner-only quote INSERT policy is missing or invalid';
  end if;
  select count(*) into v_policy_count
  from pg_policies
  where schemaname = 'public'
    and tablename = 'booking_price_quotes'
    and policyname = 'rnc owner updates quotes'
    and cmd = 'UPDATE'
    and coalesce(qual, '') ilike '%rnc_has_role%owner%'
    and coalesce(with_check, '') ilike '%rnc_has_role%owner%';
  if v_policy_count <> 1 then
    raise exception 'FAIL: owner-only quote UPDATE policy is missing or invalid';
  end if;

  -- Private proof storage must remain private and staff-readable only.
  if exists (
    select 1 from storage.buckets
    where id = 'rnc-payment-proofs' and public is true
  ) or not exists (
    select 1 from storage.buckets
    where id = 'rnc-payment-proofs' and public is false
  ) then
    raise exception 'FAIL: payment proof bucket is missing or public';
  end if;

  if to_regprocedure('public.rnc_admin_set_booking_status(uuid,text)') is null
     or to_regprocedure('public.rnc_admin_verify_booking_payment(uuid)') is null
     or to_regprocedure('public.rnc_admin_update_booking(uuid,text,text,text,uuid,timestamp with time zone,text,text)') is null
     or to_regprocedure('public.rnc_admin_mark_payment_refunded(uuid)') is null
     or to_regprocedure('public.rnc_can_upload_payment_proof(text)') is null
     or to_regprocedure('public.rnc_guard_booking_schedule_update()') is null then
    raise exception 'FAIL: one or more validated admin RPCs are missing';
  end if;

  -- Paid bookings must be refunded only as part of a requested cancellation.
  if position('v_payment_status = ''paid''' in pg_get_functiondef('public.rnc_admin_review_booking_cancellation(uuid,text)'::regprocedure)) = 0
     or position('v_payment_status = ''paid''' in pg_get_functiondef('public.rnc_admin_set_booking_status(uuid,text)'::regprocedure)) = 0
     or position('v_cancellation_status <> ''requested''' in pg_get_functiondef('public.rnc_admin_mark_payment_refunded(uuid)'::regprocedure)) = 0
     or position('for update' in lower(pg_get_functiondef('public.rnc_admin_mark_payment_refunded(uuid)'::regprocedure))) = 0
     or position('Always lock booking first' in pg_get_functiondef('public.rnc_admin_verify_booking_payment(uuid)'::regprocedure)) = 0
     or position('v_cancellation_status = ''requested''' in pg_get_functiondef('public.customer_approve_booking_quote(text,text,uuid,text)'::regprocedure)) = 0
     or position('v_cancellation_status = ''requested''' in pg_get_functiondef('public.customer_select_booking_payment(text,text,uuid,text)'::regprocedure)) = 0
     or position('v_cancellation_status = ''requested''' in pg_get_functiondef('public.customer_attach_payment_proof(text,text,uuid,text)'::regprocedure)) = 0
     or position('v_cancellation_status = ''requested''' in pg_get_functiondef('public.rnc_admin_verify_booking_payment(uuid)'::regprocedure)) = 0 then
    raise exception 'FAIL: paid cancellation/refund guards are missing';
  end if;

  -- Cancellation review must freeze uploads, rescheduling, and generic status changes.
  if position('cancellation_status' in lower(pg_get_functiondef('public.rnc_can_upload_payment_proof(text)'::regprocedure))) = 0
     or position('requested' in lower(pg_get_functiondef('public.rnc_can_upload_payment_proof(text)'::regprocedure))) = 0
     or position('order by bp_latest.created_at desc' in lower(pg_get_functiondef('public.rnc_can_upload_payment_proof(text)'::regprocedure))) = 0
     or position('v_cancellation_status' in lower(pg_get_functiondef('public.rnc_admin_set_booking_status(uuid,text)'::regprocedure))) = 0
     or position('old.cancellation_status' in lower(pg_get_functiondef('public.rnc_guard_booking_schedule_update()'::regprocedure))) = 0
     or position('v_payment_status = ''refunded''' in lower(pg_get_functiondef('public.rnc_admin_review_booking_cancellation(uuid,text)'::regprocedure))) = 0
     or position('order by bp_latest.created_at desc' in lower(pg_get_functiondef('public.rnc_admin_mark_payment_refunded(uuid)'::regprocedure))) = 0 then
    raise exception 'FAIL: cancellation transition, proof upload, reschedule, or refund guards are incomplete';
  end if;

  raise notice 'PASS: Ride N Cut security smoke checks passed. This does not replace role-based integration tests.';
end
$rnc_test$;
