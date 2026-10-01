import { withUser } from '@/lib/db';
import { getSessionUser } from '@/lib/session';
import { lookupLimiter } from '@/lib/rate-limit';
import { ERROR_MESSAGES, errorResponse } from '@/lib/realisasi/errors';
import { lookupStudents } from '@/lib/realisasi/queries/lookups';
import { studentLookupRequestSchema } from '@/lib/realisasi/schemas/participants';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

/** POST {"nrps": string[], "section": "internal"|"inbound"} → {"results": StudentLookupResult[]} (CONTRACTS §8.1). */
export async function POST(request: Request): Promise<Response> {
  const user = await getSessionUser();
  if (!user) return Response.json({ code: 'AUTH_REQUIRED', message: ERROR_MESSAGES.AUTH_REQUIRED }, { status: 401 });

  const limit = lookupLimiter.hit(user.id);
  if (!limit.ok) {
    return Response.json(
      { code: 'RATE_LIMITED', message: ERROR_MESSAGES.RATE_LIMITED },
      { status: 429, headers: { 'Retry-After': String(limit.retryAfter) } },
    );
  }

  const body: unknown = await request.json().catch(() => null);
  const parsed = studentLookupRequestSchema.safeParse(body);
  if (!parsed.success) {
    return Response.json({ code: 'BAD_REQUEST', message: parsed.error.issues[0]?.message ?? ERROR_MESSAGES.BAD_REQUEST }, { status: 400 });
  }

  try {
    const results = await withUser(user.id, (tx) => lookupStudents(tx, parsed.data.nrps, parsed.data.section));
    return Response.json({ results }, { headers: { 'Cache-Control': 'private, no-store' } });
  } catch (e) {
    return errorResponse(e);
  }
}
