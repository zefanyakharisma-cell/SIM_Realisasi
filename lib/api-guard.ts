/**
 * Shared guards for the `/api/*` route handlers (security review H-1, M-1, L-1, L-5). SERVER ONLY.
 * Route handlers do not get the Origin check that Next applies to server actions, so the
 * cross-origin rule lives in `middleware.ts` (see `isCrossOriginWrite`, also exported for tests).
 */
import type { SessionUser } from '@/lib/session';
import type { RateLimitResult } from '@/lib/rate-limit';
import { ERROR_MESSAGES } from '@/lib/realisasi/errors';

/**
 * Who may query the BAAK / HR registries: only roles that edit participant lists — submitters,
 * IO Mobility and IO Admin (Rules §10: IO Partnership sees counts only, viewers see no names).
 */
export function canLookupRegistry(user: SessionUser): boolean {
  return user.role === 'submitter' || user.role === 'io_admin' || (user.role === 'io_staff' && user.teams.includes('mobility'));
}

export function forbidden(): Response {
  return Response.json({ code: 'AUTH_FORBIDDEN', message: ERROR_MESSAGES.AUTH_FORBIDDEN }, { status: 403 });
}

export function rateLimited(limit: RateLimitResult, message: string = ERROR_MESSAGES.RATE_LIMITED!): Response {
  return Response.json(
    { code: 'RATE_LIMITED', message },
    { status: 429, headers: { 'Retry-After': String(limit.retryAfter) } },
  );
}

/** JSON-only bodies (L-1): a `text/plain` POST would skip the CORS preflight. */
export function requireJson(request: Request): Response | null {
  const type = request.headers.get('content-type') ?? '';
  if (/^application\/json\b/i.test(type)) return null;
  return Response.json({ code: 'BAD_REQUEST', message: 'Permintaan harus berformat JSON.' }, { status: 415 });
}
