/**
 * Cookie guard (CONTRACTS §6.3) + cross-origin write guard for `/api/*` (security review L-1).
 * No DB access here: only checks that `demo_uid` exists; the profile itself is validated by
 * requireUser() in layouts/routes.
 */
import { NextResponse, type NextRequest } from 'next/server';
import { isCrossOriginWrite } from '@/lib/origin-check';

const SESSION_COOKIE = 'demo_uid'; // keep in sync with lib/session.ts (not imported: edge runtime)

export function middleware(req: NextRequest) {
  const isApi = req.nextUrl.pathname.startsWith('/api/');
  // Route handlers do not get Next's server-action Origin check: refuse writes that a page on
  // another site — or a sibling *.petra.ac.id subdomain (SameSite=Lax does not stop those) — made.
  if (isApi && isCrossOriginWrite(req.method, req.headers, req.headers.get('host') ?? req.nextUrl.host)) {
    return NextResponse.json({ code: 'AUTH_FORBIDDEN', message: 'Permintaan lintas situs ditolak.' }, { status: 403 });
  }
  if (req.cookies.get(SESSION_COOKIE)?.value) return NextResponse.next();
  if (isApi) {
    return NextResponse.json({ code: 'AUTH_REQUIRED', message: 'Sesi tidak valid. Silakan masuk kembali.' }, { status: 401 });
  }
  const url = req.nextUrl.clone();
  url.pathname = '/login';
  url.search = '';
  return NextResponse.redirect(url);
}

export const config = {
  // I-3: skip only the exact /login page (and Next internals / favicon / public brand assets such as the
  // logo, which the login page shows before any session exists), not every path that merely starts with "login".
  matcher: ['/((?!_next/|favicon\\.ico$|brand/|login$).*)'],
};
