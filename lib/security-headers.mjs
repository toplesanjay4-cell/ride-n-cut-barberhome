/**
 * Build conservative browser security headers for the public app and admin UI.
 * HSTS is limited to Vercel Production (NODE_ENV is also "production" on
 * Preview builds). CSP is intentionally omitted until all third-party
 * map/payment asset origins have been inventoried.
 *
 * @param {string|undefined} vercelEnv
 * @returns {{key:string,value:string}[]}
 */
export function getGlobalSecurityHeaders(vercelEnv = process.env.VERCEL_ENV) {
  const headers = [
    { key: "X-Content-Type-Options", value: "nosniff" },
    { key: "X-Frame-Options", value: "DENY" },
    { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
    { key: "Permissions-Policy", value: "geolocation=(self), camera=(), microphone=()" },
  ];

  if (vercelEnv === "production") {
    headers.push({
      key: "Strict-Transport-Security",
      value: "max-age=31536000",
    });
  }

  return headers;
}
