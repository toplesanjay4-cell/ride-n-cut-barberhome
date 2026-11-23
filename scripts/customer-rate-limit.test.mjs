import assert from "node:assert/strict";
import test from "node:test";
import {
  getCustomerRateLimitPolicy,
  parseCustomerRateLimitResult,
} from "../lib/customer-rate-limit.mjs";

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
