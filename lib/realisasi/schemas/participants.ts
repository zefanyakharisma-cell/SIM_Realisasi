/**
 * Participant payload schemas + ID list parsing (WP-SUBMIT, CONTRACTS §3.2 / §6.8). Client + server safe.
 */
import { z } from 'zod';
import type { StaffRowPayload, StudentRowPayload } from '@/lib/realisasi/types';

/** NRP formats (Schema §4.1): PETRA `D31240187`, inbound `X01260012`; tolerant of other letter+digits ids. */
export const NRP_RE = /^[A-Z][0-9]{6,12}$/;
/** Employee id `PG204517`. */
export const EMPLOYEE_ID_RE = /^[A-Z]{1,4}[0-9]{3,10}$/;

const nullableText = (max: number) => z.string().trim().max(max, `Maksimal ${max} karakter.`).nullable().optional();

export const studentRowSchema: z.ZodType<StudentRowPayload> = z.object({
  section: z.enum(['internal', 'inbound']),
  nrp: z.string().trim().toUpperCase().min(1, 'NRP wajib diisi.').max(20, 'NRP tidak valid.'),
  home_institution: nullableText(300),
  home_student_number: nullableText(60),
  home_country_code: z.string().regex(/^[A-Z]{2}$/, 'Kode negara tidak valid.').nullable().optional(),
});

export const staffRowSchema: z.ZodType<StaffRowPayload> = z.object({
  employee_id: z.string().trim().toUpperCase().min(1, 'ID pegawai wajib diisi.').max(20, 'ID pegawai tidak valid.'),
});

export const participantsSchema = z
  .object({
    students: z.array(studentRowSchema).max(1000, 'Maksimal 1000 mahasiswa.'),
    staff: z.array(staffRowSchema).max(500, 'Maksimal 500 pegawai.'),
  })
  .superRefine((v, ctx) => {
    const seen = new Set<string>();
    v.students.forEach((s, i) => {
      if (seen.has(s.nrp)) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['students', i, 'nrp'], message: `NRP ${s.nrp} tercantum lebih dari sekali.` });
      }
      seen.add(s.nrp);
    });
    const seenStaff = new Set<string>();
    v.staff.forEach((s, i) => {
      if (seenStaff.has(s.employee_id)) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ['staff', i, 'employee_id'],
          message: `ID pegawai ${s.employee_id} tercantum lebih dari sekali.`,
        });
      }
      seenStaff.add(s.employee_id);
    });
  });

/** Split on new lines / commas / semicolons / whitespace, trim, upper-case, unique preserving order. */
export function parseIdList(text: string): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  for (const raw of text.split(/[\s,;]+/)) {
    const id = raw.trim().toUpperCase();
    if (!id || seen.has(id)) continue;
    seen.add(id);
    out.push(id);
  }
  return out;
}

/** Like `parseIdList` but keeps repeats so the UI can report them (R-22). */
export function splitIdTokens(text: string): string[] {
  return text
    .split(/[\s,;]+/)
    .map((s) => s.trim().toUpperCase())
    .filter(Boolean);
}

/** Max ids per lookup request (security review H-1; the wizard checks in batches of this size). */
export const MAX_LOOKUP_IDS = 200;

/** Request bodies of the lookup routes (CONTRACTS §8.1). */
export const studentLookupRequestSchema = z.object({
  nrps: z.array(z.string().trim().toUpperCase().min(1).max(20)).min(1, 'Daftar NRP kosong.').max(MAX_LOOKUP_IDS, `Maksimal ${MAX_LOOKUP_IDS} NRP per permintaan.`),
  section: z.enum(['internal', 'inbound']),
});

export const employeeLookupRequestSchema = z.object({
  ids: z.array(z.string().trim().toUpperCase().min(1).max(20)).min(1, 'Daftar ID pegawai kosong.').max(MAX_LOOKUP_IDS, `Maksimal ${MAX_LOOKUP_IDS} ID per permintaan.`),
});
