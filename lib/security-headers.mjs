/**
 * Build conservative browser security headers for the public app and admin UI.
 * HSTS is emitted only in production; CSP is intentionally omitted until all
 * third-party map/payment assets and required origins have been inventoried.
 *
 * @param {string} nodeEnv
 * @returns {{key:string,value:string}[]}
 */
export function getGlobalSecurityHeaders(nodeEnv = process.env.NODE_ENV) {
  const headers = [
    { key: "X-Content-Type-Options", value: "nosniff" },
    { key: "X-Frame-Options", value: "DENY" },
    { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
    { key: "Permissions-Policy", value: "geolocation=(self), camera=(), microphone=()" },
  ];

  if (nodeEnv === "production") {
    headers.push({
      key: "Strict-Transport-Security",
      value: "max-age=31536000",
    });
  }

  return headers;
}
