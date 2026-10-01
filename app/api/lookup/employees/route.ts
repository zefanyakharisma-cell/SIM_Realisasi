import { withUser } from '@/lib/db';
import { getSessionUser } from '@/lib/session';
import { canLookupRegistry, forbidden, rateLimited, requireJson } from '@/lib/api-guard';
import { lookupIdLimiter, lookupLimiter } from '@/lib/rate-limit';
import { ERROR_MESSAGES, errorResponse } from '@/lib/realisasi/errors';
import { lookupEmployees, publicEmployeeResult } from '@/lib/realisasi/queries/lookups';
import { employeeLookupRequestSchema } from '@/lib/realisasi/schemas/participants';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

/**
 * POST {"ids": string[]} → {"results": PublicEmployeeLookupResult[]} (CONTRACTS §8.1).
 * Same anti-scraping rules as the student lookup (security review H-1).
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
  const parsed = employeeLookupRequestSchema.safeParse(body);
  if (!parsed.success) {
    return Response.json({ code: 'BAD_REQUEST', message: parsed.error.issues[0]?.message ?? ERROR_MESSAGES.BAD_REQUEST }, { status: 400 });
  }
  const ids = lookupIdLimiter.hit(user.id, Date.now(), new Set(parsed.data.ids).size);
  if (!ids.ok) {
    return rateLimited(ids, `Batas pengecekan ID pegawai tercapai (${ids.remaining} tersisa). Coba lagi dalam ${Math.ceil(ids.retryAfter / 60)} menit.`);
  }

  try {
    const results = await withUser(user.id, (tx) => lookupEmployees(tx, parsed.data.ids));
    return Response.json({ results: results.map(publicEmployeeResult) }, { headers: { 'Cache-Control': 'private, no-store' } });
  } catch (e) {
    return errorResponse(e);
  }
}
