import assert from "node:assert/strict";
import test from "node:test";
import { getGlobalSecurityHeaders } from "../lib/security-headers.mjs";

function headerMap(nodeEnv) {
  return new Map(getGlobalSecurityHeaders(nodeEnv).map(({ key, value }) => [key.toLowerCase(), value]));
}

test("global security headers prevent MIME sniffing and framing", () => {
  const headers = headerMap("development");

  assert.equal(headers.get("x-content-type-options"), "nosniff");
  assert.equal(headers.get("x-frame-options"), "DENY");
  assert.equal(headers.get("referrer-policy"), "strict-origin-when-cross-origin");
});

test("permissions policy keeps customer geolocation available only to this origin", () => {
  const headers = headerMap("production");

  assert.equal(headers.get("permissions-policy"), "geolocation=(self), camera=(), microphone=()");
});

test("HSTS is emitted in production and omitted from development", () => {
  assert.equal(headerMap("production").get("strict-transport-security"), "max-age=31536000");
  assert.equal(headerMap("development").has("strict-transport-security"), false);
  assert.equal(headerMap("test").has("strict-transport-security"), false);
});

test("each call returns an independent header list", () => {
  const first = getGlobalSecurityHeaders("production");
  first.pop();

  assert.equal(
    getGlobalSecurityHeaders("production").some(({ key }) => key === "Strict-Transport-Security"),
    true,
  );
});
