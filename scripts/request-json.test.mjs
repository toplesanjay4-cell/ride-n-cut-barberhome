import assert from "node:assert/strict";
import test from "node:test";
import { readJsonObjectRequest, readRequestBytesWithinLimit } from "../lib/request-json.mjs";

function makeRequest(body, contentType = "application/json", extraHeaders = {}) {
  return new Request("https://ride-n-cut.test/api/booking-notification", {
    method: "POST",
    headers: {
      ...(contentType === null ? {} : { "content-type": contentType }),
      ...extraHeaders,
    },
    ...(body === null ? {} : { body }),
  });
}

test("accepts a JSON object with a charset parameter", async () => {
  const request = makeRequest('{"booking_code":"12345"}', "application/json; charset=utf-8");
  const result = await readJsonObjectRequest(request, 128);

  assert.deepEqual(result, { ok: true, data: { booking_code: "12345" } });
});

test("rejects non-JSON and JSONP content types", async () => {
  for (const contentType of ["text/plain", "application/jsonp", "text/application/json", null]) {
    const result = await readJsonObjectRequest(makeRequest("{}", contentType), 128);
    assert.equal(result.ok, false);
    assert.equal(result.status, 415);
  }
});

test("rejects a declared body larger than the configured limit", async () => {
  const request = makeRequest("{}", "application/json", { "content-length": "129" });
  const result = await readJsonObjectRequest(request, 128);

  assert.equal(result.ok, false);
  assert.equal(result.status, 413);
});

test("rejects malformed Content-Length values", async () => {
  for (const value of ["-1", "12x", "1.5"]) {
    const result = await readJsonObjectRequest(
      makeRequest("{}", "application/json", { "content-length": value }),
      128,
    );
    assert.equal(result.ok, false);
    assert.equal(result.status, 400);
  }
});

test("enforces the byte limit while streaming when Content-Length is absent", async () => {
  const request = makeRequest("x".repeat(129));
  const result = await readJsonObjectRequest(request, 128);

  assert.equal(result.ok, false);
  assert.equal(result.status, 413);
});

test("rejects empty bodies, malformed JSON, arrays, and primitive JSON", async () => {
  const cases = [
    makeRequest(null),
    makeRequest("{"),
    makeRequest("[]"),
    makeRequest("null"),
    makeRequest('"booking"'),
  ];

  for (const request of cases) {
    const result = await readJsonObjectRequest(request, 128);
    assert.equal(result.ok, false);
    assert.equal(result.status, 400);
  }
});

test("rejects invalid UTF-8 instead of silently replacing bytes", async () => {
  const request = new Request("https://ride-n-cut.test/api/booking-notification", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: new Uint8Array([0xff, 0xfe]),
  });
  const result = await readJsonObjectRequest(request, 128);

  assert.equal(result.ok, false);
  assert.equal(result.status, 400);
  assert.match(result.error, /UTF-8/);
});

test("streamed byte reader accepts a body within the limit", async () => {
  const result = await readRequestBytesWithinLimit(makeRequest("small", "multipart/form-data; boundary=test"), 8, "Upload");
  assert.equal(result.ok, true);
  if (result.ok) assert.equal(new TextDecoder().decode(result.bytes), "small");
});

test("streamed byte reader rejects oversized bodies without Content-Length", async () => {
  const result = await readRequestBytesWithinLimit(makeRequest("x".repeat(129), "multipart/form-data; boundary=test"), 128, "Upload");
  assert.equal(result.ok, false);
  assert.equal(result.status, 413);
});

test("streamed byte reader rejects declared oversized and malformed lengths", async () => {
  const oversized = await readRequestBytesWithinLimit(
    makeRequest("{}", "multipart/form-data; boundary=test", { "content-length": "129" }),
    128,
    "Upload",
  );
  assert.equal(oversized.ok, false);
  assert.equal(oversized.status, 413);

  const malformed = await readRequestBytesWithinLimit(
    makeRequest("{}", "multipart/form-data; boundary=test", { "content-length": "12x" }),
    128,
    "Upload",
  );
  assert.equal(malformed.ok, false);
  assert.equal(malformed.status, 400);
});
