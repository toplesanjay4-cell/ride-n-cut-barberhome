/** @type {Readonly<Record<string, {ipLimit:number, phoneLimit:number, windowSeconds:number}>>} */
const RATE_LIMIT_POLICIES = Object.freeze({
  lookup: Object.freeze({ ipLimit: 30, phoneLimit: 5, windowSeconds: 900 }),
  approve_quote: Object.freeze({ ipLimit: 40, phoneLimit: 10, windowSeconds: 900 }),
  select_payment: Object.freeze({ ipLimit: 40, phoneLimit: 10, windowSeconds: 900 }),
  cancel_booking: Object.freeze({ ipLimit: 40, phoneLimit: 10, windowSeconds: 900 }),
  upload_proof: Object.freeze({ ipLimit: 20, phoneLimit: 4, windowSeconds: 3600 }),
});

const UNAVAILABLE_RATE_LIMIT = Object.freeze({
  ok: false,
  unavailable: true,
  retryAfter: 0,
});

/**
 * Return the server-owned limits for a known customer action.
 *
 * @param {string} action
 * @returns {{ipLimit:number, phoneLimit:number, windowSeconds:number}|null}
 */
export function getCustomerRateLimitPolicy(action) {
  return Object.hasOwn(RATE_LIMIT_POLICIES, action) ? RATE_LIMIT_POLICIES[action] : null;
}

/**
 * Validate the single-row response returned by the rate-limit RPC.
 * Any unexpected shape is treated as an unavailable limiter, never as permission.
 *
 * @param {unknown} data
 * @returns {{allowed:boolean, retryAfter:number}|null}
 */
export function parseCustomerRateLimitResult(data) {
  if (!data || typeof data !== "object") return null;

  const rows = Array.isArray(data) ? data : [data];
  if (rows.length !== 1 || !rows[0] || typeof rows[0] !== "object") return null;

  /** @type {Record<string, unknown>} */
  const row = rows[0];
  const allowed = row.allowed;
  const retryAfter = row.retry_after_seconds;

  if (typeof allowed !== "boolean" || typeof retryAfter !== "number" || !Number.isSafeInteger(retryAfter)) return null;
  if (allowed && retryAfter !== 0) return null;
  if (!allowed && (retryAfter < 1 || retryAfter > 86400)) return null;

  return { allowed, retryAfter };
}

/**
 * Call the rate-limit RPC and fail closed for returned errors, malformed
 * responses, synchronous exceptions, and rejected network requests.
 *
 * @param {{rpc:(name:string, parameters:Record<string, unknown>)=>Promise<{data:unknown,error:unknown|null}>}} admin
 * @param {Record<string, unknown>} parameters
 * @returns {Promise<{ok:boolean,unavailable:boolean,retryAfter:number}>}
 */
export async function consumeCustomerRateLimit(admin, parameters) {
  try {
    if (!admin || typeof admin.rpc !== "function") return { ...UNAVAILABLE_RATE_LIMIT };

    const { data, error } = await admin.rpc("rnc_consume_customer_rate_limit", parameters);
    if (error) return { ...UNAVAILABLE_RATE_LIMIT };

    const decision = parseCustomerRateLimitResult(data);
    if (!decision) return { ...UNAVAILABLE_RATE_LIMIT };

    return {
      ok: decision.allowed,
      unavailable: false,
      retryAfter: decision.retryAfter,
    };
  } catch {
    // Do not leak PostgREST/network exception details to the public endpoint.
    return { ...UNAVAILABLE_RATE_LIMIT };
  }
}
