import { z } from 'zod';
import type { RejectReason } from '@/lib/realisasi/types';

/** Validation for verification / duplicate server-action arguments (Indonesian messages). */

export const REJECT_REASONS = ['duplicate', 'not_partnership', 'wrong_agreement', 'other'] as const satisfies readonly RejectReason[];

export const uuidSchema = z.string().uuid('ID kegiatan tidak valid');
export const bigintIdSchema = z.coerce.number().int().positive('ID tidak valid');

const optionalNote = z
  .string()
  .trim()
  .max(2000, 'Catatan maksimal 2000 karakter')
  .optional()
  .nullable()
  .transform((v) => (v ? v : null));

const requiredNote = (message: string) =>
  z.string({ required_error: message }).trim().min(1, message).max(2000, 'Catatan maksimal 2000 karakter');

export const approveSchema = z.object({ id: uuidSchema, note: optionalNote });

export const requestRevisionSchema = z.object({
  id: uuidSchema,
  note: requiredNote('Catatan revisi wajib diisi.'),
});

export const rejectSchema = z.object({
  id: uuidSchema,
  reason: z.enum(REJECT_REASONS, { errorMap: () => ({ message: 'Pilih alasan penolakan.' }) }),
  note: requiredNote('Catatan penolakan wajib diisi.'),
});

export const rowNoteSchema = z.object({
  kind: z.enum(['student', 'staff']),
  id: z.string().trim().min(1).max(50),
  note: z.string().trim().min(1).max(1000, 'Catatan baris maksimal 1000 karakter'),
});

export const mobilityRevisionSchema = z.object({
  id: uuidSchema,
  note: requiredNote('Catatan revisi wajib diisi.'),
  rowNotes: z.array(rowNoteSchema).max(500).default([]),
});

export const linkDuplicatesSchema = z.object({ candidateId: bigintIdSchema, note: optionalNote });

export const linkActivitiesSchema = z
  .object({
    a: uuidSchema,
    b: uuidSchema,
    note: requiredNote('Catatan wajib diisi.'),
  })
  .refine((v) => v.a !== v.b, { message: 'Pilih kegiatan lain.', path: ['b'] });

export const unlinkSchema = z.object({ id: uuidSchema, note: requiredNote('Catatan wajib diisi.') });

export const activityCodeSchema = z
  .string()
  .trim()
  .toUpperCase()
  .regex(/^RL-\d{4}-\d{3,}$/, 'Format kode: RL-2026-0001');
