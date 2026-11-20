import assert from "node:assert/strict";
import test from "node:test";
import { isAllowedPaymentProof } from "../lib/payment-proof.mjs";

const encoder = new TextEncoder();

test("accepts supported proof formats when MIME and file signature match", () => {
  const cases = [
    ["image/jpeg", Uint8Array.from([0xff, 0xd8, 0xff, 0xe0, 0x00])],
    ["image/png", Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])],
    ["image/webp", encoder.encode("RIFF\x04\x00\x00\x00WEBPVP8 ")],
    ["application/pdf", encoder.encode("%PDF-1.7\n")],
  ];

  for (const [contentType, bytes] of cases) {
    assert.equal(isAllowedPaymentProof(contentType, bytes), true, contentType);
  }
});

test("rejects MIME spoofing when the file signature belongs to another format", () => {
  const png = Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  assert.equal(isAllowedPaymentProof("image/jpeg", png), false);
  assert.equal(isAllowedPaymentProof("application/pdf", png), false);
});

test("rejects unsupported, empty, truncated, and non-byte inputs", () => {
  assert.equal(isAllowedPaymentProof("image/svg+xml", encoder.encode("<svg/>")), false);
  assert.equal(isAllowedPaymentProof("image/png", new Uint8Array()), false);
  assert.equal(isAllowedPaymentProof("image/jpeg", Uint8Array.from([0xff, 0xd8])), false);
  assert.equal(isAllowedPaymentProof("image/webp", encoder.encode("RIFFxxxxWEB")), false);
  assert.equal(isAllowedPaymentProof("application/pdf", encoder.encode("%PDF")), false);
  assert.equal(isAllowedPaymentProof("image/png", /** @type {any} */ ("not bytes")), false);
  assert.equal(isAllowedPaymentProof("constructor", Uint8Array.from([0xff, 0xd8, 0xff])), false);
});
