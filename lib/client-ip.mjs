import { isIP } from "node:net";

/**
 * Return only the client address set by Vercel's edge.
 *
 * Vercel documents that it overwrites X-Forwarded-For to prevent IP spoofing.
 * Do not trust x-real-ip or x-vercel-forwarded-for as fallbacks. If another
 * proxy sits in front of Vercel, this may identify that proxy rather than the
 * end user; fail closed on absent or malformed values instead of guessing.
 */
export function getTrustedClientIp(headers, nodeEnv = process.env.NODE_ENV) {
  if (nodeEnv !== "production") return "127.0.0.1";

  const candidate = headers.get("x-forwarded-for")?.trim() || "";
  if (!candidate || candidate.includes(",") || isIP(candidate) === 0) return "";

  // IPv6 hexadecimal digits are case-insensitive; normalize them before HMAC.
  return candidate.toLowerCase();
}
