import { withUser } from '@/lib/db';
import { getSessionUser } from '@/lib/session';
import { canLookupRegistry, forbidden, rateLimited, requireJson } from '@/lib/api-guard';
import { lookupIdLimiter, lookupLimiter } from '@/lib/rate-limit';
import { ERROR_MESSAGES, errorResponse } from '@/lib/realisasi/errors';
import { lookupStudents, publicStudentResult } from '@/lib/realisasi/queries/lookups';
import { studentLookupRequestSchema } from '@/lib/realisasi/schemas/participants';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

/**
 * POST {"nrps": string[], "section": "internal"|"inbound"} → {"results": PublicStudentLookupResult[]}
 * (CONTRACTS §8.1). Hardened against registry scraping (security review H-1): only roles that
 * edit participants, ≤ 200 ids per request, a per-user budget counted in ids, minimal fields.
 */
export async function POST(request: Request): Promise<Response> {
  const user = await getSessionUser();
  if (!user) return Response.json({ code: 'AUTH_REQUIRED', message: ERROR_MESSAGES.AUTH_REQUIRED }, { status: 401 });
  if (!canLookupRegistry(user)) return forbidden();
  const notJson = requireJson(request);
  if (notJson) return notJson;

  const limit = lookupLimiter.hit(user.id);
  if (!limit.ok) return rateLimited(limit);

  const body: unknown = await request.json().catch(() => null);
  const parsed = studentLookupRequestSchema.safeParse(body);
  if (!parsed.success) {
    return Response.json({ code: 'BAD_REQUEST', message: parsed.error.issues[0]?.message ?? ERROR_MESSAGES.BAD_REQUEST }, { status: 400 });
  }
  const ids = lookupIdLimiter.hit(user.id, Date.now(), new Set(parsed.data.nrps).size);
  if (!ids.ok) {
    return rateLimited(ids, `Batas pengecekan NRP tercapai (${ids.remaining} tersisa). Coba lagi dalam ${Math.ceil(ids.retryAfter / 60)} menit.`);
  }

  try {
    const { nrps, section } = parsed.data;
    const results = await withUser(user.id, (tx) => lookupStudents(tx, nrps, section));
    return Response.json(
      { results: results.map((r) => publicStudentResult(r, section)) },
      { headers: { 'Cache-Control': 'private, no-store' } },
    );
  } catch (e) {
    return errorResponse(e);
  }
}
