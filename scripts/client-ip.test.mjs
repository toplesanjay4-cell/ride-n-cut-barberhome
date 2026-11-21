import test from "node:test";
import assert from "node:assert/strict";
import { getTrustedClientIp } from "../lib/client-ip.mjs";

test("production accepts a valid Vercel IPv4 address", () => {
  const headers = new Headers({ "x-vercel-forwarded-for": "203.0.113.24" });
  assert.equal(getTrustedClientIp(headers, "production"), "203.0.113.24");
});

test("production accepts and normalizes a valid Vercel IPv6 address", () => {
  const headers = new Headers({ "x-vercel-forwarded-for": "2001:DB8::1" });
  assert.equal(getTrustedClientIp(headers, "production"), "2001:db8::1");
});

test("production ignores client-controlled forwarding fallbacks", () => {
  const headers = new Headers({
    "x-forwarded-for": "203.0.113.10",
    "x-real-ip": "203.0.113.11",
  });
  assert.equal(getTrustedClientIp(headers, "production"), "");
});

test("production prefers the platform header over spoofed fallback headers", () => {
  const headers = new Headers({
    "x-vercel-forwarded-for": "203.0.113.24",
    "x-forwarded-for": "198.51.100.50",
    "x-real-ip": "198.51.100.51",
  });
  assert.equal(getTrustedClientIp(headers, "production"), "203.0.113.24");
});

test("production rejects malformed and chained platform values", () => {
  for (const value of ["not-an-ip", "203.0.113.24, 198.51.100.1", "", "203.0.113.999"]) {
    const headers = new Headers({ "x-vercel-forwarded-for": value });
    assert.equal(getTrustedClientIp(headers, "production"), "");
  }
});

test("development uses a deterministic loopback identity", () => {
  const headers = new Headers({
    "x-vercel-forwarded-for": "203.0.113.24",
    "x-forwarded-for": "198.51.100.50",
  });
  assert.equal(getTrustedClientIp(headers, "development"), "127.0.0.1");
});
