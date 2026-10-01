// Zod schemas for Pengaturan forms (client + server). Messages in Bahasa Indonesia.
// The DB re-validates everything (update_settings / upsert_* RPCs); these give early feedback.
import { z } from 'zod';

const dateString = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Format tanggal harus YYYY-MM-DD.');
const nonNegInt = (label: string) =>
  z.coerce.number({ invalid_type_error: `${label} harus berupa angka.` }).int(`${label} harus bilangan bulat.`).min(0, `${label} tidak boleh negatif.`);
const similarity = (label: string) =>
  z.coerce
    .number({ invalid_type_error: `${label} harus berupa angka.` })
    .gt(0, `${label} harus lebih dari 0.`)
    .max(1, `${label} maksimal 1.`);

export const generalSettingsSchema = z
  .object({
    grace_period_months: nonNegInt('Masa tenggang'),
    reporting_deadline_days: nonNegInt('Batas pelaporan'),
    sla_yellow_days: nonNegInt('SLA kuning'),
    sla_red_days: nonNegInt('SLA merah'),
    revision_reminder_days: nonNegInt('Pengingat revisi'),
    revision_escalate_days: nonNegInt('Eskalasi revisi'),
    dup_date_window_days: nonNegInt('Jendela tanggal duplikat'),
    dup_name_similarity: similarity('Kemiripan nama duplikat'),
    known_match_window_days: nonNegInt('Jendela tanggal pencocokan'),
    known_name_similarity: similarity('Kemiripan nama pencocokan'),
    nudge_resend_days: nonNegInt('Jeda pengingat ulang'),
    deadline_reminder_before_days: nonNegInt('Pengingat sebelum tenggat'),
  })
  .refine((v) => v.sla_red_days > v.sla_yellow_days, {
    message: 'SLA merah harus lebih besar dari SLA kuning.',
    path: ['sla_red_days'],
  })
  .refine((v) => v.revision_escalate_days > v.revision_reminder_days, {
    message: 'Eskalasi revisi harus lebih besar dari pengingat revisi.',
    path: ['revision_escalate_days'],
  });
export type GeneralSettingsInput = z.infer<typeof generalSettingsSchema>;

export const GENERAL_SETTING_FIELDS: Array<{ key: keyof GeneralSettingsInput; label: string; suffix: string; step?: string }> = [
  { key: 'grace_period_months', label: 'Masa tenggang kerja sama baru', suffix: 'bulan' },
  { key: 'reporting_deadline_days', label: 'Batas pelaporan setelah kegiatan selesai', suffix: 'hari' },
  { key: 'sla_yellow_days', label: 'SLA verifikasi — kuning setelah', suffix: 'hari kerja' },
  { key: 'sla_red_days', label: 'SLA verifikasi — merah setelah', suffix: 'hari kerja' },
  { key: 'revision_reminder_days', label: 'Pengingat revisi ke unit setelah', suffix: 'hari' },
  { key: 'revision_escalate_days', label: 'Eskalasi revisi ke IO setelah', suffix: 'hari' },
  { key: 'deadline_reminder_before_days', label: 'Pengingat tenggat draf sebelum', suffix: 'hari' },
  { key: 'dup_date_window_days', label: 'Deteksi duplikat — jendela tanggal ±', suffix: 'hari' },
  { key: 'dup_name_similarity', label: 'Deteksi duplikat — kemiripan nama minimal', suffix: '0–1', step: '0.05' },
  { key: 'known_match_window_days', label: 'Pencocokan register — jendela tanggal ±', suffix: 'hari' },
  { key: 'known_name_similarity', label: 'Pencocokan register — kemiripan nama minimal', suffix: '0–1', step: '0.05' },
  { key: 'nudge_resend_days', label: 'Pengingat unit dapat dikirim ulang setelah', suffix: 'hari' },
];

export const demoTodaySchema = z.object({ demo_today: dateString.nullable() });

export const academicYearSchema = z
  .object({
    id: z.number().int().positive().nullable(),
    label: z.string().trim().regex(/^\d{4}\/\d{4}$/, 'Label harus berformat 2026/2027.'),
    start_date: dateString,
    end_date: dateString,
  })
  .refine((v) => v.end_date > v.start_date, { message: 'Tanggal akhir harus setelah tanggal mulai.', path: ['end_date'] });
export type AcademicYearInput = z.infer<typeof academicYearSchema>;

export const semesterSchema = z
  .object({
    id: z.number().int().positive().nullable(),
    academic_year_id: z.number().int().positive(),
    term: z.enum(['ganjil', 'genap']),
    start_date: dateString,
    end_date: dateString,
    cutoff_date: dateString,
  })
  .refine((v) => v.end_date > v.start_date, { message: 'Tanggal akhir harus setelah tanggal mulai.', path: ['end_date'] })
  .refine((v) => v.cutoff_date >= v.end_date, { message: 'Cutoff tidak boleh sebelum akhir semester.', path: ['cutoff_date'] });
export type SemesterInput = z.infer<typeof semesterSchema>;

export const activityTypeSchema = z.object({
  name: z.string().trim().min(3, 'Nama jenis minimal 3 karakter.').max(120),
  direction: z.enum(['inbound', 'outbound', 'none']),
  counts_as_mobility: z.boolean(),
  counts_for_s1: z.boolean(),
  requires_mobility_review: z.boolean(),
  is_active: z.boolean(),
  sort_order: z.coerce.number().int().min(0).max(9999),
});
export type ActivityTypeInput = z.infer<typeof activityTypeSchema>;

export const holidaySchema = z.object({
  day: dateString,
  name: z.string().trim().min(2, 'Nama hari libur wajib diisi.').max(120),
});
export type HolidayInput = z.infer<typeof holidaySchema>;

export const refreezeSchema = z.object({
  snapshot_id: z.string().uuid(),
  reason: z.string().trim().min(5, 'Alasan pembekuan ulang wajib diisi (min. 5 karakter).').max(1000),
});

export const freezeSchema = z.object({
  academic_year_id: z.number().int().positive(),
  kind: z.enum(['ganjil_ytd', 'genap_full_year']),
});
