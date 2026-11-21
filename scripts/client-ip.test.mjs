import test from "node:test";
import assert from "node:assert/strict";
import { getTrustedClientIp } from "../lib/client-ip.mjs";

test("production accepts a valid Vercel-overwritten IPv4 address", () => {
  const headers = new Headers({ "x-forwarded-for": "203.0.113.24" });
  assert.equal(getTrustedClientIp(headers, "production"), "203.0.113.24");
});

test("production accepts and normalizes a valid Vercel-overwritten IPv6 address", () => {
  const headers = new Headers({ "x-forwarded-for": "2001:DB8::1" });
  assert.equal(getTrustedClientIp(headers, "production"), "2001:db8::1");
});

test("production ignores x-real-ip and x-vercel-forwarded-for fallbacks", () => {
  const headers = new Headers({
    "x-real-ip": "203.0.113.11",
    "x-vercel-forwarded-for": "203.0.113.12",
  });
  assert.equal(getTrustedClientIp(headers, "production"), "");
});

test("production uses the overwritten x-forwarded-for instead of other headers", () => {
  const headers = new Headers({
    "x-forwarded-for": "203.0.113.24",
    "x-real-ip": "198.51.100.51",
    "x-vercel-forwarded-for": "198.51.100.52",
  });
  assert.equal(getTrustedClientIp(headers, "production"), "203.0.113.24");
});

test("production rejects malformed and chained forwarding values", () => {
  for (const value of ["not-an-ip", "203.0.113.24, 198.51.100.1", "", "203.0.113.999"]) {
    const headers = new Headers({ "x-forwarded-for": value });
    assert.equal(getTrustedClientIp(headers, "production"), "");
  }
});

test("development uses a deterministic loopback identity", () => {
  const headers = new Headers({
    "x-forwarded-for": "203.0.113.24",
    "x-real-ip": "198.51.100.50",
  });
  assert.equal(getTrustedClientIp(headers, "development"), "127.0.0.1");
});
