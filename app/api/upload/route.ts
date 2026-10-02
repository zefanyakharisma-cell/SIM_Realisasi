import { z } from 'zod';
import { withUser } from '@/lib/db';
import { getSessionUser } from '@/lib/session';
import { MAX_FILE_BYTES, extensionForMime, newActivityFilePath, newMobilityBundlePath, putObject, sniffMime, validateUpload } from '@/lib/storage';
import { rateLimited } from '@/lib/api-guard';
import { uploadLimiter } from '@/lib/rate-limit';
import { ERROR_MESSAGES, errorResponse } from '@/lib/realisasi/errors';
import type { RegisteredFile } from '@/lib/realisasi/types';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const fieldsSchema = z.object({
  activity_id: z.string().uuid(),
  target: z.enum(['ia', 'ir', 'mobility_bundle', 'evidence']),
});

function json(status: number, code: string, message?: string, detail?: unknown): Response {
  return Response.json({ code, message: message ?? ERROR_MESSAGES[code] ?? ERROR_MESSAGES.INTERNAL, detail }, { status });
}

/** Strip any directory part and control characters from a client-supplied file name. */
function cleanFilename(name: string): string {
  const base = name.split(/[\\/]/).pop() ?? 'berkas';
  const cleaned = base.replace(/[\u0000-\u001f\u007f"]/g, '').trim();
  return (cleaned || 'berkas').slice(0, 200);
}

/**
 * POST multipart (activity_id, target = ia|ir|mobility_bundle|evidence, file) — CONTRACTS §8.1.
 * storage_put + register_activity_file in one tx → RegisteredFile. The mobility bundle (one PDF with
 * transkrip, poster and dokumentasi; Revisi V.1) goes to the personal-data bucket.
 */
export async function POST(request: Request): Promise<Response> {
  const user = await getSessionUser();
  if (!user) return json(401, 'AUTH_REQUIRED');
  // L-5: per-user upload budget.
  const limit = uploadLimiter.hit(user.id);
  if (!limit.ok) return rateLimited(limit, 'Terlalu banyak unggahan. Coba lagi beberapa menit lagi.');
  // I-4: reject an oversized body before buffering it (10 MB file + multipart overhead).
  if (Number(request.headers.get('content-length') ?? '0') > MAX_FILE_BYTES + 512 * 1024) {
    return json(413, 'R13_FILE_TOO_LARGE');
  }

  let form: FormData;
  try {
    form = await request.formData();
  } catch {
    return json(400, 'BAD_REQUEST');
  }
  const file = form.get('file');
  const parsed = fieldsSchema.safeParse({
    activity_id: form.get('activity_id'),
    target: form.get('target'),
  });
  if (!parsed.success || !(file instanceof File)) {
    return json(400, 'BAD_REQUEST', parsed.success ? 'Berkas tidak ditemukan dalam permintaan.' : parsed.error.issues[0]?.message);
  }
  const fields = parsed.data;
  const policy = fields.target === 'evidence' ? 'pdf_or_image' : 'pdf';
  const filename = cleanFilename(file.name);

  // Size check before buffering the whole body.
  const pre = validateUpload({ name: filename, type: file.type, size: file.size }, policy);
  if (!pre.ok) return json(400, pre.code, pre.message);
  const data = Buffer.from(await file.arrayBuffer());
  const check = validateUpload({ name: filename, type: file.type, size: data.length }, policy, data.subarray(0, 8));
  if (!check.ok) return json(400, check.code, check.message);
  // L-3: store the sniffed type (validateUpload guarantees it equals the declared one).
  const mime = sniffMime(data.subarray(0, 8)) ?? 'application/octet-stream';

  try {
    const registered = await withUser(user.id, async (tx) => {
      const path =
        fields.target === 'mobility_bundle'
          ? newMobilityBundlePath(fields.activity_id)
          : newActivityFilePath(fields.activity_id, fields.target, `x.${extensionForMime(mime)}`);
      await putObject(tx, path, data, mime);
      const [row] = await tx<{ r: RegisteredFile }[]>`
        select realisasi.register_activity_file(${fields.activity_id}::uuid, ${fields.target}::realisasi.file_kind,
                                                ${path}::text, ${filename}::text, ${data.length}::int, ${mime}::text) as r`;
      return row!.r;
    });
    return Response.json(registered);
  } catch (e) {
    return errorResponse(e);
  }
}
