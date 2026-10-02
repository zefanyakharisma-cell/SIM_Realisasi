import { z } from 'zod';

/** Validation for verification / conflict server-action arguments (Indonesian messages). */

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

/** Revisi V.1: one revision note (no per-row notes). */
export const mobilityRevisionSchema = requestRevisionSchema;

/** Mobility picks the activity that keeps the student (Revisi V.1 rule 2.1). */
export const resolveConflictSchema = z.object({ conflictId: bigintIdSchema, keptActivityId: uuidSchema, note: optionalNote });

export const activityCodeSchema = z
  .string()
  .trim()
  .toUpperCase()
  .regex(/^RL-\d{4}-\d{3,}$/, 'Format kode: RL-2026-0001');
