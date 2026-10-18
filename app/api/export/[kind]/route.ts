// GET /api/export/[kind] — CONTRACTS §8.2.
// Flow: session (401) → unknown kind (404) → role gate (403, AT-11) → build inside withUser (RLS)
//       → log_export (R-63; every export, personal flag) → stream .xlsx.
import { withUser } from '@/lib/db';
import { getSessionUser } from '@/lib/session';
import { ERROR_MESSAGES, errorResponse } from '@/lib/realisasi/errors';
import { exportFilename } from '@/lib/realisasi/format';
import { EXPORTS, ExportParamError, isExportKind } from '@/lib/excel/registry';
import { toBuffer } from '@/lib/excel/workbook';
import { exportLimiter } from '@/lib/rate-limit';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

function json(status: number, code: string, message?: string): Response {
  return Response.json(
    { code, message: message ?? ERROR_MESSAGES[code] ?? code },
    { status, headers: { 'Cache-Control': 'private, no-store' } },
  );
}

export async function GET(request: Request, props: { params: Promise<{ kind: string }> }): Promise<Response> {
  const user = await getSessionUser();
  if (!user) return json(401, 'AUTH_REQUIRED');

  const { kind } = await props.params;
  if (!isExportKind(kind)) return json(404, 'NOT_FOUND');

  const def = EXPORTS[kind];
  if (!def.allowed(user)) return json(403, 'AUTH_FORBIDDEN');
  // L-5: whole-workbook builds are expensive; per-user budget.
  const limit = exportLimiter.hit(user.id);
  if (!limit.ok) {
    return Response.json(
      { code: 'RATE_LIMITED', message: 'Terlalu banyak unduhan Excel. Coba lagi beberapa menit lagi.' },
      { status: 429, headers: { 'Retry-After': String(limit.retryAfter), 'Cache-Control': 'private, no-store' } },
    );
  }

  const url = new URL(request.url);
  const params = url.searchParams;
  try {
    const { buffer, filename } = await withUser(user.id, async (tx) => {
      const result = await def.build({ tx, user, params, origin: url.origin });
      // Same transaction: if logging fails, nothing is served (personal-data audit must not be skipped).
      await tx`select realisasi.log_export(${kind}::text, ${tx.json(result.filters as Parameters<typeof tx.json>[0])}::jsonb,
                                           ${result.rowCount}::int, ${result.containsPersonal}::boolean)`;
      const buf = await toBuffer(result.workbook);
      return { buffer: buf, filename: exportFilename(kind, result.periodLabel) };
    });
    return new Response(new Uint8Array(buffer), {
      status: 200,
      headers: {
        'Content-Type': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'Content-Disposition': `attachment; filename="${filename.replace(/["\r\n]/g, '')}"`,
        'Content-Length': String(buffer.length),
        'Cache-Control': 'private, no-store',
        'X-Content-Type-Options': 'nosniff',
      },
    });
  } catch (e) {
    if (e instanceof ExportParamError) return json(400, 'BAD_REQUEST', e.message);
    return errorResponse(e);
  }
}
