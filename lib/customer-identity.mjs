/**
 * Normalize a customer phone value to the digits used by booking RPCs.
 *
 * @param {unknown} value
 * @returns {string}
 */
export function normalizeCustomerPhone(value) {
  return typeof value === "string" ? value.replace(/[^0-9]/g, "") : "";
}

/**
 * Validate the customer identity required by history and follow-up actions.
 * The caller trims the booking code before validation, matching the API contract.
 *
 * @param {unknown} phone
 * @param {unknown} code
 * @returns {boolean}
 */
export function isValidCustomerIdentity(phone, code) {
  return typeof phone === "string"
    && phone.length >= 8
    && phone.length <= 16
    && typeof code === "string"
    && /^\d{5}$/.test(code);
}

/**
 * Accept only UUID strings supported by the customer booking endpoint.
 *
 * @param {unknown} value
 * @returns {boolean}
 */
export function isValidBookingId(value) {
  return typeof value === "string"
    && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}
