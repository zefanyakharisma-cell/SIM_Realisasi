import { z } from 'zod';
import type { DateString, KnownActivityPayload, KnownSource, KnownStatus } from '@/lib/realisasi/types';
import { KNOWN_STATUS_LABEL } from '@/lib/realisasi/status';
import { firstParam } from '@/lib/realisasi/schemas/filters';

/** Known Activities register filters (CONTRACTS §6.8). URL keys = field names; booleans '1'. */
export interface KnownFilters {
  q?: string;
  status?: KnownStatus;
  unit_id?: number;
  intl?: boolean;
  from?: DateString;
  to?: DateString;
}

export const KNOWN_STATUSES = ['unmatched', 'matched', 'dismissed'] as const satisfies readonly KnownStatus[];
export const KNOWN_SOURCES = [
  'surat_tugas',
  'news',
  'faculty_report',
  'loa_visa_letter',
  'email',
  'other',
] as const satisfies readonly KnownSource[];

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
function isValidDate(s: string): boolean {
  if (!DATE_RE.test(s)) return false;
  const d = new Date(`${s}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
}

type RawParams = URLSearchParams | Record<string, string | string[] | undefined>;

export function parseKnownFilters(sp: RawParams): KnownFilters {
  const out: KnownFilters = {};
  const q = firstParam(sp, 'q')?.trim();
  if (q) out.q = q.slice(0, 200);
  const status = firstParam(sp, 'status');
  if (status && (KNOWN_STATUSES as readonly string[]).includes(status)) out.status = status as KnownStatus;
  const unit = Number(firstParam(sp, 'unit_id'));
  if (Number.isInteger(unit) && unit > 0) out.unit_id = unit;
  const intl = firstParam(sp, 'intl');
  if (intl === '1' || intl === 'true') out.intl = true;
  else if (intl === '0' || intl === 'false') out.intl = false;
  const from = firstParam(sp, 'from');
  if (from && isValidDate(from)) out.from = from;
  const to = firstParam(sp, 'to');
  if (to && isValidDate(to)) out.to = to;
  return out;
}

export function knownFiltersToSearchParams(f: KnownFilters): URLSearchParams {
  const sp = new URLSearchParams();
  if (f.q) sp.set('q', f.q);
  if (f.status) sp.set('status', f.status);
  if (f.unit_id !== undefined) sp.set('unit_id', String(f.unit_id));
  if (f.intl !== undefined) sp.set('intl', f.intl ? '1' : '0');
  if (f.from) sp.set('from', f.from);
  if (f.to) sp.set('to', f.to);
  return sp;
}

export function describeKnownFilters(
  f: KnownFilters,
  opts: { unitName?: (id: number) => string } = {},
): Array<[label: string, value: string]> {
  const rows: Array<[string, string]> = [];
  if (f.q) rows.push(['Pencarian', f.q]);
  if (f.status) rows.push(['Status', KNOWN_STATUS_LABEL[f.status] ?? f.status]);
  if (f.unit_id !== undefined) rows.push(['Unit', opts.unitName?.(f.unit_id) ?? `#${f.unit_id}`]);
  if (f.intl !== undefined) rows.push(['Internasional', f.intl ? 'Ya' : 'Tidak']);
  if (f.from) rows.push(['Tanggal dari', f.from]);
  if (f.to) rows.push(['Tanggal sampai', f.to]);
  return rows;
}

const optionalText = (max: number) =>
  z
    .string()
    .trim()
    .max(max, `Maksimal ${max} karakter`)
    .nullable()
    .optional()
    .transform((v) => (v ? v : null));

/** `KnownActivityPayload` (CONTRACTS §3.6). Required: title, activity_date, is_international, source. */
export const knownActivitySchema = z.object({
  title: z.string({ required_error: 'Judul wajib diisi' }).trim().min(3, 'Judul minimal 3 karakter').max(300, 'Maksimal 300 karakter'),
  activity_date: z
    .string({ required_error: 'Tanggal wajib diisi' })
    .refine(isValidDate, 'Tanggal tidak valid'),
  unit_id: z.coerce.number().int().positive().nullable().optional().transform((v) => v ?? null),
  partner_name: optionalText(200),
  country_code: z
    .string()
    .trim()
    .nullable()
    .optional()
    .transform((v) => (v ? v.toUpperCase() : null))
    .refine((v) => v === null || /^[A-Z]{2}$/.test(v), 'Kode negara tidak valid'),
  is_international: z.boolean({ required_error: 'Pilih apakah kegiatan internasional' }),
  source: z.enum(KNOWN_SOURCES, { errorMap: () => ({ message: 'Pilih sumber informasi' }) }),
  source_reference: optionalText(300),
  notes: optionalText(2000),
}) as unknown as z.ZodType<KnownActivityPayload>;

/** Form-level type (inputs before transform). */
export interface KnownActivityFormValues {
  title: string;
  activity_date: string;
  unit_id: string;
  partner_name: string;
  country_code: string;
  is_international: boolean;
  source: KnownSource | '';
  source_reference: string;
  notes: string;
}

export const dismissKnownSchema = z.object({
  id: z.number().int().positive(),
  note: z.string().trim().min(1, 'Catatan wajib diisi').max(2000),
});
