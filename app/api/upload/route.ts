import { z } from 'zod';
import { withUser } from '@/lib/db';
import { getSessionUser } from '@/lib/session';
import { fileHref, newActivityFilePath, newTranscriptPath, putObject, validateUpload } from '@/lib/storage';
import { ERROR_MESSAGES, errorResponse } from '@/lib/realisasi/errors';
import type { RegisteredFile } from '@/lib/realisasi/types';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const fieldsSchema = z.discriminatedUnion('target', [
  z.object({ activity_id: z.string().uuid(), target: z.enum(['ia', 'ir', 'evidence']) }),
  z.object({
    activity_id: z.string().uuid(),
    target: z.literal('transcript'),
    nrp: z.string().trim().toUpperCase().regex(/^[A-Z0-9]{3,20}$/, 'NRP tidak valid.'),
  }),
]);

function json(status: number, code: string, message?: string, detail?: unknown): Response {
  return Response.json({ code, message: message ?? ERROR_MESSAGES[code] ?? ERROR_MESSAGES.INTERNAL, detail }, { status });
}

/** Strip any directory part and control characters from a client-supplied file name. */
function cleanFilename(name: string): string {
  const base = name.split(/[\\/]/).pop() ?? 'berkas';
  // eslint-disable-next-line no-control-regex
  const cleaned = base.replace(/[\u0000-\u001f\u007f"]/g, '').trim();
  return (cleaned || 'berkas').slice(0, 200);
}

/**
 * POST multipart (activity_id, target = ia|ir|evidence|transcript, file, nrp?) — CONTRACTS §8.1.
 * ia/ir/evidence → storage_put + register_activity_file in one tx → RegisteredFile.
 * transcript → ensure_participant_draft + storage_put → {path, href, version}.
 */
export async function POST(request: Request): Promise<Response> {
  const user = await getSessionUser();
  if (!user) return json(401, 'AUTH_REQUIRED');

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
    nrp: form.get('nrp') ?? undefined,
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

  try {
    if (fields.target === 'transcript') {
      const result = await withUser(user.id, async (tx) => {
        const [row] = await tx<{ r: { version_id: string; version: number } }[]>`
          select realisasi.ensure_participant_draft(${fields.activity_id}::uuid) as r`;
        const version = row!.r.version;
        const path = newTranscriptPath(fields.activity_id, version, fields.nrp);
        await putObject(tx, path, data, 'application/pdf');
        return { path, href: fileHref(path), version };
      });
      return Response.json(result);
    }

    const registered = await withUser(user.id, async (tx) => {
      const path = newActivityFilePath(fields.activity_id, fields.target, filename);
      await putObject(tx, path, data, file.type);
      const [row] = await tx<{ r: RegisteredFile }[]>`
        select realisasi.register_activity_file(${fields.activity_id}::uuid, ${fields.target}::realisasi.file_kind,
                                                ${path}::text, ${filename}::text, ${data.length}::int, ${file.type}::text) as r`;
      return row!.r;
    });
    return Response.json(registered);
  } catch (e) {
    return errorResponse(e);
  }
}
