import { isIP } from "node:net";

/**
 * Return only an address supplied by the hosting platform.
 *
 * In production, do not fall back to x-forwarded-for or x-real-ip: clients
 * can send those headers themselves unless a trusted proxy overwrites them.
 * An absent or malformed platform header intentionally fails closed.
 */
export function getTrustedClientIp(headers, nodeEnv = process.env.NODE_ENV) {
  if (nodeEnv !== "production") return "127.0.0.1";

  const candidate = headers.get("x-vercel-forwarded-for")?.trim() || "";
  if (!candidate || candidate.includes(",") || isIP(candidate) === 0) return "";

  // IPv6 hexadecimal digits are case-insensitive; normalize them before HMAC.
  return candidate.toLowerCase();
}
