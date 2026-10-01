/**
 * Cookie guard (CONTRACTS §6.3). No DB access here: only checks that `demo_uid` exists;
 * the profile itself is validated by requireUser() in layouts/routes.
 */
import { NextResponse, type NextRequest } from 'next/server';

const SESSION_COOKIE = 'demo_uid'; // keep in sync with lib/session.ts (not imported: edge runtime)

export function middleware(req: NextRequest) {
  if (req.cookies.get(SESSION_COOKIE)?.value) return NextResponse.next();
  if (req.nextUrl.pathname.startsWith('/api/')) {
    return NextResponse.json({ code: 'AUTH_REQUIRED', message: 'Sesi tidak valid. Silakan masuk kembali.' }, { status: 401 });
  }
  const url = req.nextUrl.clone();
  url.pathname = '/login';
  url.search = '';
  return NextResponse.redirect(url);
}

export const config = {
  matcher: ['/((?!_next/|favicon.ico|login).*)'],
};
