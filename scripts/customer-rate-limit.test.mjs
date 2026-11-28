import assert from "node:assert/strict";
import test from "node:test";
import {
  consumeCustomerRateLimit,
  getCustomerRateLimitPolicy,
  parseCustomerRateLimitResult,
} from "../lib/customer-rate-limit.mjs";

const parameters = {
  p_ip_key_hash: "ip-hash",
  p_phone_key_hash: "phone-hash",
  p_ip_limit: 30,
  p_phone_limit: 5,
  p_window_seconds: 900,
};

test("customer actions use explicit server-owned rate-limit policies", () => {
  assert.deepEqual(getCustomerRateLimitPolicy("lookup"), {
    ipLimit: 30,
    phoneLimit: 5,
    windowSeconds: 900,
  });
  assert.deepEqual(getCustomerRateLimitPolicy("approve_quote"), {
    ipLimit: 40,
    phoneLimit: 10,
    windowSeconds: 900,
  });
  assert.deepEqual(getCustomerRateLimitPolicy("select_payment"), {
    ipLimit: 40,
    phoneLimit: 10,
    windowSeconds: 900,
  });
  assert.deepEqual(getCustomerRateLimitPolicy("cancel_booking"), {
    ipLimit: 40,
    phoneLimit: 10,
    windowSeconds: 900,
  });
  assert.deepEqual(getCustomerRateLimitPolicy("upload_proof"), {
    ipLimit: 20,
    phoneLimit: 4,
    windowSeconds: 3600,
  });
  assert.equal(getCustomerRateLimitPolicy("unknown"), null);
  assert.equal(getCustomerRateLimitPolicy("toString"), null);
});

test("parses one valid row returned by the PostgREST table RPC", () => {
  assert.deepEqual(
    parseCustomerRateLimitResult([{ allowed: true, retry_after_seconds: 0 }]),
    { allowed: true, retryAfter: 0 },
  );
  assert.deepEqual(
    parseCustomerRateLimitResult({ allowed: false, retry_after_seconds: 45 }),
    { allowed: false, retryAfter: 45 },
  );
});

test("fails closed for missing, duplicate, or malformed RPC rows", () => {
  const invalidResults = [
    null,
    undefined,
    {},
    [],
    [{ allowed: true, retry_after_seconds: 0 }, { allowed: true, retry_after_seconds: 0 }],
    [{ allowed: "true", retry_after_seconds: 0 }],
    [{ allowed: false, retry_after_seconds: "30" }],
    [{ allowed: false }],
    [{ allowed: false, retry_after_seconds: 0 }],
    [{ allowed: true, retry_after_seconds: 1 }],
    [{ allowed: false, retry_after_seconds: -1 }],
    [{ allowed: false, retry_after_seconds: 86401 }],
    [{ allowed: false, retry_after_seconds: 1.5 }],
    [{ allowed: false, retry_after_seconds: Number.POSITIVE_INFINITY }],
  ];

  for (const result of invalidResults) {
    assert.equal(parseCustomerRateLimitResult(result), null);
  }
});

test("allows a valid RPC decision and forwards only the expected arguments", async () => {
  let receivedName;
  let receivedParameters;
  const result = await consumeCustomerRateLimit({
    async rpc(name, args) {
      receivedName = name;
      receivedParameters = args;
      return { data: [{ allowed: true, retry_after_seconds: 0 }], error: null };
    },
  }, parameters);

  assert.equal(receivedName, "rnc_consume_customer_rate_limit");
  assert.deepEqual(receivedParameters, parameters);
  assert.deepEqual(result, { ok: true, unavailable: false, retryAfter: 0 });
});

test("returns a rate-limit denial with the database retry interval", async () => {
  const result = await consumeCustomerRateLimit({
    async rpc() {
      return { data: [{ allowed: false, retry_after_seconds: 45 }], error: null };
    },
  }, parameters);

  assert.deepEqual(result, { ok: false, unavailable: false, retryAfter: 45 });
});

test("fails closed when the RPC returns a database error", async () => {
  const result = await consumeCustomerRateLimit({
    async rpc() {
      return { data: null, error: new Error("private database detail") };
    },
  }, parameters);

  assert.deepEqual(result, { ok: false, unavailable: true, retryAfter: 0 });
});

test("fails closed when the RPC rejects because of a network failure", async () => {
  const result = await consumeCustomerRateLimit({
    async rpc() {
      throw new Error("private network detail");
    },
  }, parameters);

  assert.deepEqual(result, { ok: false, unavailable: true, retryAfter: 0 });
});

test("fails closed when the RPC throws synchronously or is unavailable", async () => {
  const throwingResult = await consumeCustomerRateLimit({
    rpc() {
      throw new Error("private client detail");
    },
  }, parameters);
  const missingRpcResult = await consumeCustomerRateLimit({}, parameters);

  assert.deepEqual(throwingResult, { ok: false, unavailable: true, retryAfter: 0 });
  assert.deepEqual(missingRpcResult, { ok: false, unavailable: true, retryAfter: 0 });
});

test("fails closed when the RPC resolves with a malformed response", async () => {
  const result = await consumeCustomerRateLimit({
    async rpc() {
      return { data: [{ allowed: true, retry_after_seconds: 30 }], error: null };
    },
  }, parameters);

  assert.deepEqual(result, { ok: false, unavailable: true, retryAfter: 0 });
});
