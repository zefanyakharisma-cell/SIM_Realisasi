import { withUser } from '@/lib/db';
import { getSessionUser } from '@/lib/session';
import { BUCKETS, getObject } from '@/lib/storage';
import { ERROR_MESSAGES, errorResponse } from '@/lib/realisasi/errors';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const ALLOWED_BUCKETS: ReadonlySet<string> = new Set(Object.values(BUCKETS));

function safeDecode(s: string): string {
  try {
    return decodeURIComponent(s);
  } catch {
    return s;
  }
}

/** RFC 6266 header value with an ASCII fallback and a UTF-8 `filename*`. */
function contentDisposition(filename: string): string {
  const ascii = filename.replace(/[^\x20-\x7e]/g, '_').replace(/["\\]/g, '_');
  return `inline; filename="${ascii}"; filename*=UTF-8''${encodeURIComponent(filename)}`;
}

/** GET /api/files/<bucket>/<...key> → bytes (CONTRACTS §8.1). Access is decided by `storage_get`. */
export async function GET(_request: Request, props: { params: Promise<{ path: string[] }> }): Promise<Response> {
  const user = await getSessionUser();
  if (!user) return Response.json({ code: 'AUTH_REQUIRED', message: ERROR_MESSAGES.AUTH_REQUIRED }, { status: 401 });

  const { path: segments } = await props.params;
  const decoded = segments.map(safeDecode);
  if (decoded.length < 3 || !ALLOWED_BUCKETS.has(decoded[0]!) || decoded.some((s) => s === '' || s === '.' || s === '..')) {
    return Response.json({ code: 'FILE_NOT_FOUND', message: ERROR_MESSAGES.FILE_NOT_FOUND }, { status: 404 });
  }
  const path = decoded.join('/');

  try {
    const { object, filename } = await withUser(user.id, async (tx) => {
      const obj = await getObject(tx, path);
      const [row] = await tx<{ filename: string | null }[]>`
        select filename from realisasi.activity_files where storage_path = ${path} order by version desc limit 1`;
      return { object: obj, filename: row?.filename ?? decoded[decoded.length - 1]! };
    });
    return new Response(new Uint8Array(object.data), {
      status: 200,
      headers: {
        'Content-Type': object.mime,
        'Content-Length': String(object.data.length),
        'Content-Disposition': contentDisposition(filename),
        'Cache-Control': 'private, no-store',
        'X-Content-Type-Options': 'nosniff',
      },
    });
  } catch (e) {
    return errorResponse(e);
  }
}
