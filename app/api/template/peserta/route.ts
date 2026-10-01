import ExcelJS from 'exceljs';
import { getSessionUser } from '@/lib/session';
import { canLookupRegistry, forbidden, rateLimited } from '@/lib/api-guard';
import { checkZip } from '@/lib/excel/zip-guard';
import { templateLimiter } from '@/lib/rate-limit';
import { ERROR_MESSAGES } from '@/lib/realisasi/errors';
import { splitIdTokens } from '@/lib/realisasi/schemas/participants';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

type Kind = 'students' | 'staff';

const HEADER: Record<Kind, string> = { students: 'NRP', staff: 'ID Pegawai' };
const EXAMPLE: Record<Kind, string> = { students: 'D31240187', staff: 'PG204517' };
const XLSX_MIME = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/** A 1,000-row id list is a few KB; anything bigger is not a participant template (M-1). */
const MAX_TEMPLATE_BYTES = 512 * 1024;
/** Ids returned per file (the wizard checks them in batches). */
const MAX_TEMPLATE_IDS = 1000;
const TOO_LARGE_MESSAGE = 'Berkas template terlalu besar. Maksimal 512 KB dan 1.000 baris ID; gunakan template yang disediakan.';

function parseKind(value: string | null): Kind | null {
  return value === 'students' || value === 'staff' ? value : null;
}

function unauthorized(): Response {
  return Response.json({ code: 'AUTH_REQUIRED', message: ERROR_MESSAGES.AUTH_REQUIRED }, { status: 401 });
}

function badRequest(message?: string): Response {
  return Response.json({ code: 'BAD_REQUEST', message: message ?? ERROR_MESSAGES.BAD_REQUEST }, { status: 400 });
}

/** GET ?kind=students|staff → one-column .xlsx template (CONTRACTS §8.1). */
export async function GET(request: Request): Promise<Response> {
  const user = await getSessionUser();
  if (!user) return unauthorized();
  const kind = parseKind(new URL(request.url).searchParams.get('kind'));
  if (!kind) return badRequest();

  const wb = new ExcelJS.Workbook();
  wb.creator = 'SIM Realisasi';
  wb.created = new Date();
  const ws = wb.addWorksheet('Peserta', { views: [{ state: 'frozen', ySplit: 1 }] });
  ws.columns = [{ header: HEADER[kind], key: 'id', width: 22 }];
  ws.getRow(1).font = { bold: true };
  ws.getColumn(1).numFmt = '@'; // keep ids as text (no leading-zero loss)
  ws.addRow({ id: EXAMPLE[kind] });
  ws.getCell('C1').value =
    kind === 'students'
      ? 'Isi satu NRP per baris di kolom A (hapus contoh). Unggah kembali melalui "Unggah template Excel".'
      : 'Isi satu ID pegawai per baris di kolom A (hapus contoh). Unggah kembali melalui "Unggah template Excel".';
  ws.getCell('C1').font = { italic: true, color: { argb: 'FF6B7280' } };

  const buf = Buffer.from(await wb.xlsx.writeBuffer());
  const filename = kind === 'students' ? 'Template-Peserta-NRP.xlsx' : 'Template-Peserta-Pegawai.xlsx';
  return new Response(new Uint8Array(buf), {
    headers: {
      'Content-Type': XLSX_MIME,
      'Content-Disposition': `attachment; filename="${filename}"`,
      'Cache-Control': 'private, no-store',
    },
  });
}

function cellText(value: ExcelJS.CellValue): string {
  if (value === null || value === undefined) return '';
  if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') return String(value);
  if (value instanceof Date) return '';
  if (typeof value === 'object') {
    if ('richText' in value && Array.isArray(value.richText)) return value.richText.map((r) => r.text).join('');
    if ('text' in value && typeof value.text === 'string') return value.text;
    if ('result' in value && value.result !== undefined && value.result !== null) return String(value.result);
  }
  return '';
}

/**
 * POST multipart `file` (+ `kind`) → {"ids": string[]} read from column A of the first sheet
 * (header row "NRP"/"ID Pegawai" skipped). Also accepts .csv / .txt. The ids are only parsed here;
 * the client then runs the normal lookup (WP-SUBMIT addition to §8.1, same route family).
 */
export async function POST(request: Request): Promise<Response> {
  const user = await getSessionUser();
  if (!user) return unauthorized();
  // Same audience as the registry lookups the parsed ids are fed into (security review H-1 / M-1).
  if (!canLookupRegistry(user)) return forbidden();
  const limit = templateLimiter.hit(user.id);
  if (!limit.ok) return rateLimited(limit);

  // Refuse oversized bodies before buffering them (M-1).
  const declared = Number(request.headers.get('content-length') ?? '0');
  if (declared > MAX_TEMPLATE_BYTES + 64 * 1024) {
    return Response.json({ code: 'R13_FILE_TOO_LARGE', message: TOO_LARGE_MESSAGE }, { status: 413 });
  }

  let form: FormData;
  try {
    form = await request.formData();
  } catch {
    return badRequest();
  }
  const kind = parseKind(typeof form.get('kind') === 'string' ? (form.get('kind') as string) : null) ?? 'students';
  const file = form.get('file');
  if (!(file instanceof File)) return badRequest('Berkas tidak ditemukan dalam permintaan.');
  if (file.size > MAX_TEMPLATE_BYTES) {
    return Response.json({ code: 'R13_FILE_TOO_LARGE', message: TOO_LARGE_MESSAGE }, { status: 413 });
  }

  const name = file.name.toLowerCase();
  const data = Buffer.from(await file.arrayBuffer());
  const tokens: string[] = [];
  const push = (raw: string) => {
    for (const t of splitIdTokens(raw)) if (tokens.length <= MAX_TEMPLATE_IDS + 2) tokens.push(t);
  };
  try {
    if (name.endsWith('.csv') || name.endsWith('.txt')) {
      push(data.toString('utf8'));
    } else if (name.endsWith('.xlsx')) {
      // Bound the inflated size before ExcelJS loads the workbook into memory (M-1).
      const zip = checkZip(data);
      if (!zip.ok) {
        return zip.reason === 'too_large' || zip.reason === 'too_many_entries'
          ? Response.json({ code: 'R13_FILE_TOO_LARGE', message: TOO_LARGE_MESSAGE }, { status: 413 })
          : badRequest('Berkas Excel tidak dapat dibaca. Gunakan template yang disediakan.');
      }
      const wb = new ExcelJS.Workbook();
      await wb.xlsx.load(data as unknown as ArrayBuffer);
      const ws = wb.worksheets[0];
      if (ws) {
        if (ws.rowCount > MAX_TEMPLATE_IDS + 1) {
          return Response.json({ code: 'R13_FILE_TOO_LARGE', message: TOO_LARGE_MESSAGE }, { status: 413 });
        }
        ws.eachRow({ includeEmpty: false }, (row) => push(cellText(row.getCell(1).value)));
      }
    } else {
      return Response.json(
        { code: 'R13_FILE_TYPE', message: 'Format berkas tidak diizinkan (XLSX, CSV).' },
        { status: 400 },
      );
    }
  } catch {
    return badRequest('Berkas Excel tidak dapat dibaca. Gunakan template yang disediakan.');
  }

  const header = HEADER[kind].toUpperCase();
  const ids = tokens.filter((t) => t !== header && t !== 'NRP' && t !== 'ID' && t !== 'PEGAWAI');
  return Response.json({ ids: ids.slice(0, MAX_TEMPLATE_IDS) });
}
