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

  -- Raw booking rows must be private to active owner/staff accounts.
  select c.relrowsecurity into v_enabled
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'bookings';
  if coalesce(v_enabled, false) is not true then
    raise exception 'FAIL: public.bookings must have RLS enabled';
  end if;

  if has_table_privilege('anon', 'public.bookings', 'SELECT')
     or has_table_privilege('anon', 'public.bookings', 'INSERT')
     or has_table_privilege('anon', 'public.bookings', 'UPDATE')
     or has_table_privilege('anon', 'public.bookings', 'DELETE')
     or has_table_privilege('authenticated', 'public.bookings', 'INSERT')
     or has_table_privilege('authenticated', 'public.bookings', 'UPDATE')
     or has_table_privilege('authenticated', 'public.bookings', 'DELETE')
     or not has_table_privilege('authenticated', 'public.bookings', 'SELECT') then
    raise exception 'FAIL: direct booking table privileges are broader or narrower than the admin read-only model';
  end if;

  select count(*) into v_policy_count
  from pg_policies
  where schemaname = 'public'
    and tablename = 'bookings'
    and cmd = 'SELECT'
    and coalesce(qual, '') ilike '%rnc_has_role%owner%staff%'
    and (
      (policyname = 'rnc active admins read bookings' and permissive = 'PERMISSIVE')
      or
      (policyname = 'rnc active admins restrict booking reads' and permissive = 'RESTRICTIVE')
    );
  if v_policy_count <> 2 then
    raise exception 'FAIL: active owner/staff booking read policies are missing or invalid';
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
     or to_regprocedure('public.rnc_guard_booking_schedule_update()') is null
     or to_regprocedure('public.rnc_guard_booking_state_update()') is null
     or to_regprocedure('public.customer_booking_slots(uuid,date)') is null then
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

  -- Protected booking state must not be writable directly through PostgREST.
  if not exists (
    select 1
    from pg_trigger t
    where t.tgrelid = 'public.bookings'::regclass
      and t.tgname = 'rnc_guard_booking_state_update'
      and not t.tgisinternal
      and t.tgenabled in ('O','A')
  ) then
    raise exception 'FAIL: booking state guard trigger is missing or disabled';
  end if;

  select p.prosecdef into v_enabled
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'rnc_guard_booking_state_update';
  if coalesce(v_enabled, true) is not false
     or position('current_user' in lower(pg_get_functiondef('public.rnc_guard_booking_state_update()'::regprocedure))) = 0
     or position('payment_status' in lower(pg_get_functiondef('public.rnc_guard_booking_state_update()'::regprocedure))) = 0
     or position('cancellation_status' in lower(pg_get_functiondef('public.rnc_guard_booking_state_update()'::regprocedure))) = 0 then
    raise exception 'FAIL: booking state guard does not protect sensitive columns as an invoker trigger';
  end if;

  -- The public availability RPC must expose only occupied intervals, not customer data.
  select p.prosecdef into v_enabled
  from pg_proc p
  where p.oid = 'public.customer_booking_slots(uuid,date)'::regprocedure;
  if coalesce(v_enabled, false) is not true
     or position('start_at' in lower(pg_get_functiondef('public.customer_booking_slots(uuid,date)'::regprocedure))) = 0
     or position('service_duration_minutes' in lower(pg_get_functiondef('public.customer_booking_slots(uuid,date)'::regprocedure))) = 0
     or position('customer_name' in lower(pg_get_functiondef('public.customer_booking_slots(uuid,date)'::regprocedure))) > 0
     or position('phone' in lower(pg_get_functiondef('public.customer_booking_slots(uuid,date)'::regprocedure))) > 0
     or position('address' in lower(pg_get_functiondef('public.customer_booking_slots(uuid,date)'::regprocedure))) > 0 then
    raise exception 'FAIL: public booking availability RPC is not a minimal, private-data-safe function';
  end if;

  -- The state-write trigger relies on SECURITY DEFINER RPCs owned by postgres.
  select count(*) into v_policy_count
  from unnest(array[
    'public.rnc_admin_set_booking_status(uuid,text)'::regprocedure,
    'public.rnc_admin_verify_booking_payment(uuid)'::regprocedure,
    'public.rnc_admin_update_booking(uuid,text,text,text,uuid,timestamp with time zone,text,text)'::regprocedure,
    'public.rnc_admin_mark_payment_refunded(uuid)'::regprocedure,
    'public.rnc_admin_review_booking_cancellation(uuid,text)'::regprocedure,
    'public.customer_request_booking_cancellation(text,text,uuid)'::regprocedure,
    'public.customer_approve_booking_quote(text,text,uuid,text)'::regprocedure,
    'public.customer_select_booking_payment(text,text,uuid,text)'::regprocedure,
    'public.customer_attach_payment_proof(text,text,uuid,text)'::regprocedure,
    'public.customer_booking_slots(uuid,date)'::regprocedure
  ]) as required_functions(function_oid)
  join pg_proc p on p.oid = required_functions.function_oid::oid
  join pg_roles r on r.oid = p.proowner
  where p.prosecdef is true and r.rolname = 'postgres';
  if v_policy_count <> 10 then
    raise exception 'FAIL: validated booking/payment RPCs must be SECURITY DEFINER functions owned by postgres';
  end if;

  -- Customer-facing SECURITY DEFINER RPCs must be callable by anon,
  -- while admin mutation RPCs must never be executable by anon.
  select count(*) into v_policy_count
  from unnest(array[
    'public.customer_create_booking(text,text,text,uuid,timestamp with time zone,text,text,integer,uuid,text,double precision,double precision)'::regprocedure,
    'public.customer_booking_quote(text,text,uuid)'::regprocedure,
    'public.customer_approve_booking_quote(text,text,uuid,text)'::regprocedure,
    'public.customer_select_booking_payment(text,text,uuid,text)'::regprocedure,
    'public.customer_attach_payment_proof(text,text,uuid,text)'::regprocedure,
    'public.customer_booking_payment(text,text,uuid)'::regprocedure,
    'public.customer_request_booking_cancellation(text,text,uuid)'::regprocedure,
    'public.customer_booking_cancellation_status(text,text,uuid)'::regprocedure,
    'public.customer_booking_slots(uuid,date)'::regprocedure
  ]) as customer_functions(function_oid)
  where has_function_privilege('anon', customer_functions.function_oid, 'EXECUTE')
    and has_function_privilege('authenticated', customer_functions.function_oid, 'EXECUTE');
  if v_policy_count <> 9 then
    raise exception 'FAIL: customer RPC execute grants are missing or inconsistent for anon/authenticated';
  end if;

  select count(*) into v_policy_count
  from unnest(array[
    'public.rnc_admin_set_booking_status(uuid,text)'::regprocedure,
    'public.rnc_admin_verify_booking_payment(uuid)'::regprocedure,
    'public.rnc_admin_update_booking(uuid,text,text,text,uuid,timestamp with time zone,text,text)'::regprocedure,
    'public.rnc_admin_mark_payment_refunded(uuid)'::regprocedure,
    'public.rnc_admin_review_booking_cancellation(uuid,text)'::regprocedure
  ]) as admin_functions(function_oid)
  where not has_function_privilege('anon', admin_functions.function_oid, 'EXECUTE')
    and has_function_privilege('authenticated', admin_functions.function_oid, 'EXECUTE');
  if v_policy_count <> 5 then
    raise exception 'FAIL: admin mutation RPCs must be unavailable to anon and executable by authenticated users';
  end if;

  raise notice 'PASS: Ride N Cut security smoke checks passed. This does not replace role-based integration tests.';
end
$rnc_test$;
