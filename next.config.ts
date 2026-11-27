import type { NextConfig } from "next";
import { getGlobalSecurityHeaders } from "./lib/security-headers.mjs";

const nextConfig: NextConfig = {
  async headers() {
    return [
      {
        source: "/:path*",
        headers: getGlobalSecurityHeaders(),
      },
    ];
  },
};

export default nextConfig;
