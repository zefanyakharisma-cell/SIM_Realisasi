/**
 * Activity Detail payload schemas (WP-SUBMIT, CONTRACTS §3.2 / §6.8). Client + server safe.
 *
 * - `activityDetailSchema` mirrors what `save_activity_draft` validates (draft level).
 * - `activityDetailSubmitSchema` adds the R-07 submit requirements (venue always; city + country
 *   unless online) so the wizard can warn before the DB checklist does.
 * Messages are Indonesian; the DB stays authoritative.
 */
import { z } from 'zod';
import type { ActivityDetailPayload, ExternalPersonPayload } from '@/lib/realisasi/types';

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function isValidDate(s: string): boolean {
  if (!DATE_RE.test(s)) return false;
  const d = new Date(`${s}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
}

const dateString = (label: string) =>
  z
    .string({ required_error: `${label} wajib diisi.`, invalid_type_error: `${label} wajib diisi.` })
    .min(1, `${label} wajib diisi.`)
    .refine(isValidDate, `${label} tidak valid.`);

const optionalText = (max: number) =>
  z
    .string()
    .trim()
    .max(max, `Maksimal ${max} karakter.`)
    .nullable();

const countryCode = z
  .string()
  .regex(/^[A-Z]{2}$/, 'Kode negara tidak valid.');

export const MODES = ['offline', 'online', 'hybrid'] as const;
export const FUNDING_SOURCES = ['pcu', 'partner', 'government', 'participant', 'mixed', 'none'] as const;
export const PERSON_ROLES = ['speaker', 'visiting_lecturer', 'researcher', 'staff_visitor', 'other'] as const;

export const externalPersonSchema: z.ZodType<ExternalPersonPayload> = z.object({
  full_name: z.string().trim().min(1, 'Nama wajib diisi.').max(200, 'Maksimal 200 karakter.'),
  institution: z.string().trim().min(1, 'Institusi wajib diisi.').max(200, 'Maksimal 200 karakter.'),
  country_code: countryCode,
  role: z.enum(PERSON_ROLES, { errorMap: () => ({ message: 'Pilih peran.' }) }),
  notes: optionalText(500),
});

const idArray = (label: string) =>
  z
    .array(z.number().int().positive(), { invalid_type_error: `${label} tidak valid.` })
    .max(50, `${label} terlalu banyak.`);

const baseObject = z.object({
  name: z
    .string({ required_error: 'Nama kegiatan wajib diisi.' })
    .trim()
    .min(1, 'Nama kegiatan wajib diisi.')
    .max(300, 'Maksimal 300 karakter.'),
  type_id: z
    .number({ required_error: 'Pilih jenis kegiatan.', invalid_type_error: 'Pilih jenis kegiatan.' })
    .int()
    .positive('Pilih jenis kegiatan.'),
  start_date: dateString('Tanggal mulai'),
  end_date: dateString('Tanggal selesai'),
  mode: z.enum(MODES, { errorMap: () => ({ message: 'Pilih moda kegiatan.' }) }),
  venue: optionalText(300),
  city: optionalText(120),
  country_code: countryCode.nullable(),
  sks_recognized: z
    .number({ invalid_type_error: 'SKS tidak valid.' })
    .min(0, 'SKS tidak boleh negatif.')
    .max(99.9, 'SKS terlalu besar.')
    .nullable(),
  funding_source: z.enum(FUNDING_SOURCES).nullable(),
  description: z
    .string({ required_error: 'Deskripsi wajib diisi.' })
    .trim()
    .min(1, 'Deskripsi wajib diisi.')
    .max(5000, 'Maksimal 5000 karakter.'),
  submitter_unit_id: z
    .number({ required_error: 'Pilih unit pengaju.', invalid_type_error: 'Pilih unit pengaju.' })
    .int()
    .positive('Pilih unit pengaju.'),
  co_unit_ids: idArray('Unit lain'),
  document_ids: idArray('Kerja sama'),
  sdg_ids: z.array(z.number().int().min(1).max(17)).max(17),
  external_persons: z.array(externalPersonSchema).max(100, 'Terlalu banyak orang.'),
});

function refineDates(v: { start_date: string; end_date: string }, ctx: z.RefinementCtx) {
  if (isValidDate(v.start_date) && isValidDate(v.end_date) && v.end_date < v.start_date) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['end_date'],
      message: 'Tanggal selesai tidak boleh sebelum tanggal mulai.',
    });
  }
}

export const activityDetailSchema: z.ZodType<ActivityDetailPayload> = baseObject.superRefine((v, ctx) => {
  refineDates(v, ctx);
  if (v.co_unit_ids.includes(v.submitter_unit_id)) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['co_unit_ids'], message: 'Unit lain tidak boleh sama dengan unit pengaju.' });
  }
});

/** Draft schema + R-07 submit-time requirements (used for the wizard's "Lanjut" and hints). */
export const activityDetailSubmitSchema: z.ZodType<ActivityDetailPayload> = baseObject.superRefine((v, ctx) => {
  refineDates(v, ctx);
  if (!v.venue) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['venue'],
      message: v.mode === 'online' ? 'Nama platform wajib diisi.' : 'Tempat wajib diisi.',
    });
  }
  if (v.mode !== 'online') {
    if (!v.city) ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['city'], message: 'Kota wajib diisi.' });
    if (!v.country_code) ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['country_code'], message: 'Pilih negara.' });
  }
  if (v.document_ids.length === 0) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['document_ids'], message: 'Pilih minimal satu kerja sama.' });
  }
});

/** Partial payload for IO post-verification edits (`edit_verified_activity`). */
export const activityDetailPartialSchema = baseObject.partial().superRefine((v, ctx) => {
  if (v.start_date && v.end_date) refineDates({ start_date: v.start_date, end_date: v.end_date }, ctx);
});

export const evidenceLinkSchema = z.object({
  url: z
    .string()
    .trim()
    .url('Tautan tidak valid.')
    .refine((u) => /^https?:\/\//i.test(u), 'Tautan harus diawali http:// atau https://.'),
  label: z.string().trim().min(1, 'Label tautan wajib diisi.').max(200, 'Maksimal 200 karakter.'),
});

export const editNoteSchema = z.string().trim().min(1, 'Catatan perubahan wajib diisi.').max(2000, 'Maksimal 2000 karakter.');

/** Flattens zod issues into `{ field: message }` (first message per top-level path). */
export function fieldErrors(error: z.ZodError): Record<string, string> {
  const out: Record<string, string> = {};
  for (const issue of error.issues) {
    const key = issue.path.map(String).join('.') || '_';
    if (!(key in out)) out[key] = issue.message;
  }
  return out;
}
