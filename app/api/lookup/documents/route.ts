import { z } from 'zod';
import { withUser } from '@/lib/db';
import { getSessionUser } from '@/lib/session';
import { lookupLimiter } from '@/lib/rate-limit';
import { ERROR_MESSAGES, errorResponse } from '@/lib/realisasi/errors';
import { getValidDocuments } from '@/lib/realisasi/queries/lookups';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const DATE = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
const querySchema = z
  .object({
    start: DATE,
    end: DATE,
    unit_id: z.coerce.number().int().positive().nullable(),
  })
  .refine((q) => q.end >= q.start, { message: 'Tanggal selesai tidak boleh sebelum tanggal mulai.' });

/** GET ?start=&end=&unit_id= → {"documents": DocumentOption[]} (R-04; CONTRACTS §8.1). */
export async function GET(request: Request): Promise<Response> {
  const user = await getSessionUser();
  if (!user) return Response.json({ code: 'AUTH_REQUIRED', message: ERROR_MESSAGES.AUTH_REQUIRED }, { status: 401 });

  const limit = lookupLimiter.hit(user.id);
  if (!limit.ok) {
    return Response.json(
      { code: 'RATE_LIMITED', message: ERROR_MESSAGES.RATE_LIMITED },
      { status: 429, headers: { 'Retry-After': String(limit.retryAfter) } },
    );
  }

  const sp = new URL(request.url).searchParams;
  const parsed = querySchema.safeParse({
    start: sp.get('start') ?? '',
    end: sp.get('end') ?? '',
    unit_id: sp.get('unit_id') || null,
  });
  if (!parsed.success) {
    return Response.json({ code: 'BAD_REQUEST', message: parsed.error.issues[0]?.message ?? ERROR_MESSAGES.BAD_REQUEST }, { status: 400 });
  }

  try {
    const documents = await withUser(user.id, (tx) =>
      getValidDocuments(tx, parsed.data.start, parsed.data.end, parsed.data.unit_id),
    );
    return Response.json({ documents }, { headers: { 'Cache-Control': 'private, no-store' } });
  } catch (e) {
    return errorResponse(e);
  }
}
