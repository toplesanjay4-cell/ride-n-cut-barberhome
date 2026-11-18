import assert from "node:assert/strict";
import test from "node:test";
import {
  addDateKeyDays,
  addDateKeyMonths,
  formatJakartaDateKey,
  formatJakartaDateTime,
  getDateKeyWeekday,
  getJakartaDateKey,
  getJakartaMonthStart,
  getJakartaTimeKey,
  getJakartaYearStart,
  jakartaDateTimeToISOString,
} from "../lib/jakarta-time.mjs";

test("Jakarta date and time cross UTC midnight correctly", () => {
  assert.equal(getJakartaDateKey("2026-11-17T16:59:00.000Z"), "2026-11-17");
  assert.equal(getJakartaDateKey("2026-11-17T17:00:00.000Z"), "2026-11-18");
  assert.equal(getJakartaTimeKey("2026-11-17T17:00:00.000Z"), "00:00");
});

test("customer-selected wall time is always converted from Asia/Jakarta", () => {
  assert.equal(jakartaDateTimeToISOString("2026-11-18", "09:30"), "2026-11-18T02:30:00.000Z");
  assert.equal(jakartaDateTimeToISOString("2026-11-18", "23:59"), "2026-11-18T16:59:00.000Z");
});

test("invalid date and time input is rejected", () => {
  assert.equal(jakartaDateTimeToISOString("2026-02-29", "09:30"), null);
  assert.equal(jakartaDateTimeToISOString("2028-02-29", "24:00"), null);
  assert.equal(jakartaDateTimeToISOString("2028-02-29", "09:60"), null);
  assert.equal(jakartaDateTimeToISOString("2028/02/29", "09:30"), null);
});

test("date-key arithmetic is independent of the browser timezone", () => {
  assert.equal(addDateKeyDays("2026-12-31", 1), "2027-01-01");
  assert.equal(addDateKeyDays("2028-02-28", 1), "2028-02-29");
  assert.equal(addDateKeyMonths("2026-01-01", -1), "2025-12-01");
  assert.equal(getDateKeyWeekday("2026-11-18"), 3);
  assert.equal(getJakartaMonthStart("2026-11-18"), "2026-11-01");
  assert.equal(getJakartaYearStart("2026-11-18"), "2026-01-01");
});

test("calendar labels and booking timestamps render in Jakarta time", () => {
  assert.match(formatJakartaDateKey("2026-11-18", { weekday: "long" }).toLowerCase(), /rabu/);
  assert.match(formatJakartaDateTime("2026-11-17T17:00:00.000Z", { hour: "2-digit", minute: "2-digit" }), /00:00/);
});
