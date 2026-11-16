import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";

const migrationDir = join(process.cwd(), "supabase", "migrations");
const files = (await readdir(migrationDir))
  .filter((name) => /^2026\d{10}_.+\.sql$/.test(name))
  .sort();

const expected = [
  "20261115000100_rnc_redesign_additive_schema.sql",
  ...Array.from({ length: 20 }, (_, index) => {
    const number = String(index + 1).padStart(4, "0");
    const titles = [
      "rnc_atomic_booking_slots",
      "rnc_service_duration_booking",
      "rnc_booking_horizon_guard",
      "rnc_lock_payment_writes",
      "rnc_validate_payment_verification",
      "rnc_lock_booking_during_payment_verify",
      "rnc_enforce_owner_price_settings",
      "rnc_customer_map_pin",
      "rnc_limit_public_settings_columns",
      "rnc_serialize_customer_payment_actions",
      "rnc_atomic_admin_reschedule",
      "rnc_admin_review_customer_cancellation",
      "rnc_enforce_operating_schedule",
      "rnc_validate_admin_booking_status",
      "rnc_owner_only_quote_edits",
      "rnc_bound_booking_buffer",
      "rnc_public_booking_buffer",
      "rnc_restrict_owner_role_provisioning",
      "rnc_record_external_payment_refunds",
      "rnc_freeze_customer_payment_during_cancellation",
    ];
    return `20261116${number}00_${titles[index]}.sql`;
  }),
];

const errors = [];
if (files.length !== expected.length) {
  errors.push(`Expected ${expected.length} migrations, found ${files.length}.`);
}
for (const name of expected) {
  if (!files.includes(name)) errors.push(`Missing migration: ${name}`);
}
for (const name of files) {
  if (!expected.includes(name)) errors.push(`Unexpected migration requiring review: ${name}`);
}

const docs = await readFile(join(process.cwd(), "docs", "SETUP-REDESIGN.md"), "utf8");
for (const name of expected) {
  if (!docs.includes(name)) errors.push(`Setup guide does not list ${name}`);
}

const smoke = await readFile(join(process.cwd(), "supabase", "tests", "rnc_security_smoke_test.sql"), "utf8");
for (const marker of [
  "rnc owner creates staff roles",
  "rnc owner updates staff roles",
  "rnc owner deletes staff roles",
  "rnc owner creates quotes",
  "rnc owner updates quotes",
  "booking_payments",
  "booking_buffer_minutes",
  "rnc-payment-proofs",
  "rnc_admin_set_booking_status",
  "rnc_admin_verify_booking_payment",
  "rnc_admin_update_booking",
  "rnc_admin_mark_payment_refunded",
]) {
  if (!smoke.includes(marker)) errors.push(`Security smoke test is missing check: ${marker}`);
}

if (errors.length) {
  console.error("Migration integrity check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exitCode = 1;
} else {
  console.log(`Migration integrity check passed: ${files.length} ordered migrations, setup guide, and security smoke test.`);
}
