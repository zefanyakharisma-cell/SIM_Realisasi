// Zod schemas for Pengaturan forms (client + server). Messages in Bahasa Indonesia.
// The DB re-validates everything (update_settings / upsert_* RPCs); these give early feedback.
import { z } from 'zod';
import { RENSTRA_KEYS } from '@/lib/realisasi/schemas/report';

const dateString = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Format tanggal harus YYYY-MM-DD.');
const nonNegInt = (label: string) =>
  z.coerce.number({ invalid_type_error: `${label} harus berupa angka.` }).int(`${label} harus bilangan bulat.`).min(0, `${label} tidak boleh negatif.`);
export const generalSettingsSchema = z.object({
  grace_period_months: nonNegInt('Masa tenggang'),
  reporting_deadline_days: nonNegInt('Batas pelaporan'),
  revision_reminder_days: nonNegInt('Pengingat revisi'),
  deadline_reminder_before_days: nonNegInt('Pengingat sebelum tenggat'),
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

export const AGENDA_PROGRAMS = ['student_mobility', 'faculty_mobility', 'other'] as const;

/** One Jenis Kegiatan (`save_agenda`); id null adds a new one. Student Mobility needs its Awards category. */
export const agendaSchema = z
  .object({
    id: z.number().int().positive().nullable(),
    name: z.string().trim().min(1, 'Nama jenis kegiatan wajib diisi.').max(200),
    program: z.enum(AGENDA_PROGRAMS),
    description: z.string().trim().max(2000).nullable(),
    mobility_category: z.enum(MOBILITY_CATEGORIES).nullable(),
    counts_for_s1: z.boolean(),
    sort_order: z.number().int().min(0),
    is_active: z.boolean(),
  })
  .refine((v) => v.program !== 'student_mobility' || v.mobility_category !== null, {
    message: 'Pilih kategori International Awards untuk Student Mobility.',
    path: ['mobility_category'],
  });
export type AgendaInput = z.infer<typeof agendaSchema>;

/** Target RENSTRA for one academic year and indicator (`set_renstra_targets`); unit_id 0 = Universitas, null target = none. */
export const renstraTargetsSchema = z
  .object({
    academic_year_id: z.number().int().positive(),
    renstra_key: z.enum(RENSTRA_KEYS),
    rows: z.array(
      z.object({
        unit_id: z.number().int().min(0),
        target: z.number({ invalid_type_error: 'Target harus berupa angka.' }).min(0, 'Target tidak boleh negatif.').nullable(),
      }),
    ),
  })
  .refine((v) => v.renstra_key !== '1.19.S4' || v.rows.every((r) => r.unit_id === 0 && (r.target === null || r.target <= 100)), {
    message: 'Target 1.19.S4 berupa satu persentase universitas (0–100).',
    path: ['rows'],
  });
export type RenstraTargetsInput = z.infer<typeof renstraTargetsSchema>;

export const refreezeSchema = z.object({
  snapshot_id: z.string().uuid(),
  reason: z.string().trim().min(5, 'Alasan pembekuan ulang wajib diisi (min. 5 karakter).').max(1000),
});

export const freezeSchema = z.object({
  academic_year_id: z.number().int().positive(),
  kind: z.enum(['ganjil_ytd', 'genap_full_year']),
});
