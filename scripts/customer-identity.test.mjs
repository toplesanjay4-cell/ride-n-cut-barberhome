import assert from "node:assert/strict";
import test from "node:test";
import {
  isValidBookingId,
  isValidCustomerIdentity,
  normalizeCustomerPhone,
} from "../lib/customer-identity.mjs";

test("normalizes customer phone values to ASCII digits", () => {
  assert.equal(normalizeCustomerPhone("+62 812-3456-7890"), "6281234567890");
  assert.equal(normalizeCustomerPhone("0812 (345) 678"), "0812345678");
  assert.equal(normalizeCustomerPhone("not a phone"), "");
  assert.equal(normalizeCustomerPhone(null), "");
  assert.equal(normalizeCustomerPhone(62812345678), "");
});

test("accepts only an 8–16 digit phone and an exact five-digit booking code", () => {
  assert.equal(isValidCustomerIdentity("08123456", "12345"), true);
  assert.equal(isValidCustomerIdentity("6281234567890123", "00001"), true);

  for (const [phone, code] of [
    ["1234567", "12345"],
    ["12345678901234567", "12345"],
    ["", "12345"],
    ["0812345678", "1234"],
    ["0812345678", "123456"],
    ["0812345678", "12 345"],
    ["0812345678", "１２３４５"],
    [null, "12345"],
    ["0812345678", null],
  ]) {
    assert.equal(isValidCustomerIdentity(phone, code), false);
  }
});

test("accepts supported UUID booking identifiers and rejects malformed values", () => {
  assert.equal(isValidBookingId("550e8400-e29b-41d4-a716-446655440000"), true);
  assert.equal(isValidBookingId("550E8400-E29B-41D4-A716-446655440000"), true);

  for (const value of [
    "",
    "not-a-uuid",
    "550e8400-e29b-01d4-a716-446655440000",
    "550e8400-e29b-41d4-7116-446655440000",
    "550e8400-e29b-41d4-a716-44665544000",
    null,
    123,
  ]) {
    assert.equal(isValidBookingId(value), false);
  }
});
