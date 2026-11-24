-- Run as postgres in a NON-PRODUCTION Supabase project after all migrations.
-- This test exercises the real RPC but intentionally persists no fixtures:
-- the nested PL/pgSQL exception block is a subtransaction, and the final
-- sentinel exception rolls back every rate-limit row created or updated here.
--
-- This checks sequential thresholds and fixed-window expiry. It does not
-- replace concurrent-request, HTTP 429, proxy, or end-to-end integration tests.

do $rnc_rate_limit_test$
declare
  v_ip_key text;
  v_phone_key text;
  v_allowed boolean;
  v_retry integer;
  v_attempts integer;
  v_updated integer;
  v_index integer;
begin
  begin
    -- IP threshold: keep one IP key and vary phone keys so only the IP
    -- counter reaches its limit on the third request.
    v_ip_key := repeat(md5(random()::text || clock_timestamp()::text || pg_backend_pid()::text), 2);

    for v_index in 1..3 loop
      v_phone_key := repeat(md5(random()::text || clock_timestamp()::text || v_index::text), 2);

      select allowed, retry_after_seconds
        into v_allowed, v_retry
      from public.rnc_consume_customer_rate_limit(
        v_ip_key, v_phone_key, 2, 100, 60
      );

      if v_index < 3 then
        if v_allowed is not true or v_retry is distinct from 0 then
          raise exception 'FAIL: IP threshold blocked an allowed request before its limit';
        end if;
      elsif v_allowed is not false or v_retry is null or v_retry not between 1 and 60 then
        raise exception 'FAIL: IP threshold did not block the third request with a bounded retry interval';
      end if;
    end loop;

    -- Phone threshold: keep one phone key and vary IP keys so only the
    -- phone counter reaches its limit on the third request.
    v_phone_key := repeat(md5(random()::text || clock_timestamp()::text || 'phone'), 2);

    for v_index in 1..3 loop
      v_ip_key := repeat(md5(random()::text || clock_timestamp()::text || v_index::text || 'ip'), 2);

      select allowed, retry_after_seconds
        into v_allowed, v_retry
      from public.rnc_consume_customer_rate_limit(
        v_ip_key, v_phone_key, 100, 2, 60
      );

      if v_index < 3 then
        if v_allowed is not true or v_retry is distinct from 0 then
          raise exception 'FAIL: phone threshold blocked an allowed request before its limit';
        end if;
      elsif v_allowed is not false or v_retry is null or v_retry not between 1 and 60 then
        raise exception 'FAIL: phone threshold did not block the third request with a bounded retry interval';
      end if;
    end loop;

    -- Fixed-window expiry: age both counters beyond their window, then
    -- verify the next request resets both attempt counts to one.
    v_ip_key := repeat(md5(random()::text || clock_timestamp()::text || 'reset-ip'), 2);
    v_phone_key := repeat(md5(random()::text || clock_timestamp()::text || 'reset-phone'), 2);

    select allowed, retry_after_seconds
      into v_allowed, v_retry
    from public.rnc_consume_customer_rate_limit(
      v_ip_key, v_phone_key, 1, 1, 60
    );

    if v_allowed is not true or v_retry is distinct from 0 then
      raise exception 'FAIL: first request in a fresh window was not allowed';
    end if;

    update public.rnc_customer_rate_limits
    set window_started_at = clock_timestamp() - interval '61 seconds'
    where key_hash in (v_ip_key, v_phone_key);

    get diagnostics v_updated = row_count;
    if v_updated <> 2 then
      raise exception 'FAIL: expected both test counters to exist before window reset';
    end if;

    select allowed, retry_after_seconds
      into v_allowed, v_retry
    from public.rnc_consume_customer_rate_limit(
      v_ip_key, v_phone_key, 1, 1, 60
    );

    if v_allowed is not true or v_retry is distinct from 0 then
      raise exception 'FAIL: expired fixed window did not allow a fresh request';
    end if;

    select attempts into v_attempts
    from public.rnc_customer_rate_limits
    where key_hash = v_ip_key;

    if v_attempts is distinct from 1 then
      raise exception 'FAIL: IP attempt count was not reset to one after window expiry';
    end if;

    select attempts into v_attempts
    from public.rnc_customer_rate_limits
    where key_hash = v_phone_key;

    if v_attempts is distinct from 1 then
      raise exception 'FAIL: phone attempt count was not reset to one after window expiry';
    end if;

    -- Force the successful test path to roll back all fixture writes.
    raise exception using
      errcode = 'RNC01',
      message = 'RNC_RATE_LIMIT_TEST_ROLLBACK';
  exception
    when sqlstate 'RNC01' then
      if sqlerrm <> 'RNC_RATE_LIMIT_TEST_ROLLBACK' then
        raise;
      end if;
      raise notice 'PASS: rate-limit thresholds and window expiry verified; all test writes rolled back.';
  end;
end
$rnc_rate_limit_test$;
