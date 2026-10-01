import type { NextConfig } from 'next';

const isProd = process.env.NODE_ENV === 'production';

/**
 * Content-Security-Policy (security review M-2).
 * - `script-src 'unsafe-inline'`: the App Router streams its RSC payload through inline
 *   `<script>` tags; without a per-request nonce (middleware + dynamic rendering of every page)
 *   they need 'unsafe-inline'. Acceptable for the mockup; move to a nonce-based policy before
 *   production (see docs/reviews/security-review.md M-2). 'unsafe-eval' only in `next dev`.
 * - `style-src 'unsafe-inline'`: Recharts, Radix (popper positioning) and sonner set inline
 *   `style` attributes; style injection cannot run script.
 * - `frame-src 'self'` + `frame-ancestors 'self'`: the verification queue previews IA/IR PDFs from
 *   `/api/files` in same-origin iframes; no other site may frame the app (clickjacking).
 */
const csp = [
  "default-src 'self'",
  `script-src 'self' 'unsafe-inline'${isProd ? '' : " 'unsafe-eval'"}`,
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob:",
  "font-src 'self' data:",
  `connect-src 'self'${isProd ? '' : ' ws: wss:'}`,
  "frame-src 'self'",
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "frame-ancestors 'self'",
].join('; ');

const common = [
  { key: 'X-Frame-Options', value: 'SAMEORIGIN' },
  { key: 'X-Content-Type-Options', value: 'nosniff' },
  { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
  { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=(), payment=(), usb=()' },
  { key: 'Cross-Origin-Opener-Policy', value: 'same-origin' },
  ...(isProd ? [{ key: 'Strict-Transport-Security', value: 'max-age=63072000; includeSubDomains' }] : []),
];

const nextConfig: NextConfig = {
  reactStrictMode: true,
  // M-2: do not advertise the framework.
  poweredByHeader: false,
  // postgres.js and exceljs must stay as native Node modules (no bundling).
  serverExternalPackages: ['postgres', 'exceljs'],
  experimental: {
    serverActions: {
      bodySizeLimit: '12mb',
    },
    // I-4: middleware runs on /api/upload; let a 10 MB file plus multipart overhead through so the
    // route can answer R13_FILE_TOO_LARGE itself instead of a truncated-body 400.
    middlewareClientMaxBodySize: '11mb',
  },
  async headers() {
    return [
      // Everything except served files gets the full policy.
      { source: '/((?!api/files/).*)', headers: [{ key: 'Content-Security-Policy', value: csp }, ...common] },
      // Served uploads (/api/files): no page CSP — Chrome's PDF viewer does not render under
      // `object-src 'none'` — but still not frameable by other sites and never sniffed.
      { source: '/api/files/:path*', headers: [{ key: 'Content-Security-Policy', value: "frame-ancestors 'self'" }, ...common] },
    ];
  },
};

export default nextConfig;
