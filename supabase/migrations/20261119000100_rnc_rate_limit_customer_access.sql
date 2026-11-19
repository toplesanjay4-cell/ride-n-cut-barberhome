-- Keep phone/code-based customer RPCs behind a rate-limited server boundary.
-- This migration is additive; it does not change booking or payment records.

create table if not exists public.rnc_customer_rate_limits (
  key_hash text primary key check (key_hash ~ '^[a-f0-9]{64}$'),
  window_started_at timestamptz not null,
  attempts integer not null check (attempts > 0),
  updated_at timestamptz not null default now()
);

create index if not exists rnc_customer_rate_limits_window_idx
  on public.rnc_customer_rate_limits(window_started_at);

alter table public.rnc_customer_rate_limits enable row level security;
revoke all privileges on table public.rnc_customer_rate_limits from public, anon, authenticated;
grant all privileges on table public.rnc_customer_rate_limits to service_role;

create or replace function public.rnc_consume_customer_rate_limit(
  p_ip_key_hash text,
  p_phone_key_hash text,
  p_ip_limit integer default 30,
  p_phone_limit integer default 10,
  p_window_seconds integer default 900
)
returns table (allowed boolean, retry_after_seconds integer)
language plpgsql
security definer
set search_path = public
as $rnc$
declare
  v_now timestamptz := clock_timestamp();
  v_ip_attempts integer;
  v_phone_attempts integer;
  v_ip_window timestamptz;
  v_phone_window timestamptz;
  v_retry integer;
begin
  if p_ip_key_hash !~ '^[a-f0-9]{64}$'
     or p_phone_key_hash !~ '^[a-f0-9]{64}$'
     or p_ip_limit not between 1 and 1000
     or p_phone_limit not between 1 and 1000
     or p_window_seconds not between 1 and 86400 then
    raise exception 'Invalid rate-limit request.';
  end if;

  -- Opportunistic bounded cleanup prevents unbounded growth without a cron dependency.
  delete from public.rnc_customer_rate_limits
  where key_hash in (
    select key_hash
    from public.rnc_customer_rate_limits
    where window_started_at < v_now - interval '24 hours'
    order by window_started_at
    limit 100
  );

  insert into public.rnc_customer_rate_limits(key_hash, window_started_at, attempts, updated_at)
  values (p_ip_key_hash, v_now, 1, v_now)
  on conflict (key_hash) do update
  set window_started_at = case
        when public.rnc_customer_rate_limits.window_started_at + make_interval(secs => p_window_seconds) <= v_now then v_now
        else public.rnc_customer_rate_limits.window_started_at end,
      attempts = case
        when public.rnc_customer_rate_limits.window_started_at + make_interval(secs => p_window_seconds) <= v_now then 1
        else public.rnc_customer_rate_limits.attempts + 1 end,
      updated_at = v_now
  returning attempts, window_started_at into v_ip_attempts, v_ip_window;

  insert into public.rnc_customer_rate_limits(key_hash, window_started_at, attempts, updated_at)
  values (p_phone_key_hash, v_now, 1, v_now)
  on conflict (key_hash) do update
  set window_started_at = case
        when public.rnc_customer_rate_limits.window_started_at + make_interval(secs => p_window_seconds) <= v_now then v_now
        else public.rnc_customer_rate_limits.window_started_at end,
      attempts = case
        when public.rnc_customer_rate_limits.window_started_at + make_interval(secs => p_window_seconds) <= v_now then 1
        else public.rnc_customer_rate_limits.attempts + 1 end,
      updated_at = v_now
  returning attempts, window_started_at into v_phone_attempts, v_phone_window;

  v_retry := greatest(1, ceil(extract(epoch from greatest(
    v_ip_window + make_interval(secs => p_window_seconds),
    v_phone_window + make_interval(secs => p_window_seconds)
  ) - v_now))::integer);

  return query select (v_ip_attempts <= p_ip_limit and v_phone_attempts <= p_phone_limit),
    case when v_ip_attempts <= p_ip_limit and v_phone_attempts <= p_phone_limit then 0 else v_retry end;
end;
$rnc$;

revoke all on function public.rnc_consume_customer_rate_limit(text,text,integer,integer,integer) from public, anon, authenticated;
grant execute on function public.rnc_consume_customer_rate_limit(text,text,integer,integer,integer) to service_role;

-- Revoke every overload by name so the history RPC's legacy signature is not guessed.
do $rnc$
declare
  v_function record;
begin
  for v_function in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and p.proname = any(array[
        'customer_booking_history',
        'customer_booking_quote',
        'customer_booking_payment',
        'customer_booking_cancellation_status',
        'customer_approve_booking_quote',
        'customer_select_booking_payment',
        'customer_attach_payment_proof',
        'customer_request_booking_cancellation',
        'rnc_can_upload_payment_proof'
      ])
  loop
    execute format('revoke all on function %s from public, anon, authenticated', v_function.signature);
    execute format('grant execute on function %s to service_role', v_function.signature);
  end loop;
end;
$rnc$;

-- Customers now upload proof through the rate-limited server route using service_role.
drop policy if exists "rnc customer uploads own payment proof" on storage.objects;

comment on table public.rnc_customer_rate_limits is
  'HMAC-only, server-managed counters for customer phone/code actions; raw phone numbers and IP addresses are never stored.';