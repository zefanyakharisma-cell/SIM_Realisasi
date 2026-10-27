// Zod schemas for Pengaturan forms (client + server). Messages in Bahasa Indonesia.
// The DB re-validates everything (update_settings / upsert_* RPCs); these give early feedback.
import { z } from 'zod';

const dateString = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Format tanggal harus YYYY-MM-DD.');
/** Same caps as update_settings: months / days that keep the date arithmetic (and the nightly jobs) in range. */
export const SETTING_MAX = { months: 120, days: 3650 } as const;
// An emptied field must not coerce to 0 (z.coerce.number('') === 0): it would silently move every draft's deadline.
const nonNegInt = (label: string, max: number) =>
  z.preprocess(
    (v) => (typeof v === 'string' && v.trim() === '' ? undefined : v),
    z.coerce
      .number({ invalid_type_error: `${label} wajib diisi.` })
      .int(`${label} harus bilangan bulat.`)
      .min(0, `${label} tidak boleh negatif.`)
      .max(max, `${label} maksimal ${max}.`),
  );
export const generalSettingsSchema = z.object({
  grace_period_months: nonNegInt('Masa tenggang', SETTING_MAX.months),
  reporting_deadline_days: nonNegInt('Batas pelaporan', SETTING_MAX.days),
  revision_reminder_days: nonNegInt('Pengingat revisi', SETTING_MAX.days),
  deadline_reminder_before_days: nonNegInt('Pengingat sebelum tenggat', SETTING_MAX.days),
});
export type GeneralSettingsInput = z.infer<typeof generalSettingsSchema>;

/** Revisi V.1: no SLA, duplicate-similarity or Known-Activities settings any more. */
export const GENERAL_SETTING_FIELDS: Array<{ key: keyof GeneralSettingsInput; label: string; suffix: string; step?: string }> = [
  { key: 'grace_period_months', label: 'Masa tenggang kerja sama baru', suffix: 'bulan' },
  { key: 'reporting_deadline_days', label: 'Batas pelaporan setelah kegiatan selesai', suffix: 'hari' },
  { key: 'revision_reminder_days', label: 'Pengingat revisi ke unit setelah', suffix: 'hari' },
  { key: 'deadline_reminder_before_days', label: 'Pengingat tenggat draf sebelum', suffix: 'hari' },
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

export const MOBILITY_CATEGORIES = ['jd_dd', 'student_exchange', 'short_summer', 'other_mobility'] as const;

/** Jenis Kegiatan rule for one SIMKS agenda (`set_agenda_rule`). */
export const agendaRuleSchema = z.object({
  agenda_id: z.number().int().positive(),
  mobility_category: z.enum(MOBILITY_CATEGORIES).nullable(),
  counts_for_s1: z.boolean(),
});
export type AgendaRuleInput = z.infer<typeof agendaRuleSchema>;

export const refreezeSchema = z.object({
  snapshot_id: z.string().uuid(),
  reason: z.string().trim().min(5, 'Alasan pembekuan ulang wajib diisi (min. 5 karakter).').max(1000),
});

export const freezeSchema = z.object({
  academic_year_id: z.number().int().positive(),
  kind: z.enum(['ganjil_ytd', 'genap_full_year']),
});
