'use server';
// Pengaturan server actions (io_admin). The DB RPCs re-check the role and validate everything;
// we validate input shape with zod first and gate on `settings.manage` for a fast, clear 403.
import { revalidatePath } from 'next/cache';
import type { z } from 'zod';
import { withUser } from '@/lib/db';
import { can, requireUser } from '@/lib/session';
import { ERROR_MESSAGES, runAction } from '@/lib/realisasi/errors';
import type { ActionResult, DailyJobsResult, SettingsValues, SnapshotKind } from '@/lib/realisasi/types';
import {
  academicYearSchema,
  activityTypeSchema,
  demoTodaySchema,
  freezeSchema,
  generalSettingsSchema,
  holidaySchema,
  refreezeSchema,
  semesterSchema,
  type AcademicYearInput,
  type ActivityTypeInput,
  type GeneralSettingsInput,
  type HolidayInput,
  type SemesterInput,
} from '@/lib/realisasi/schemas/settings';

type Fail = { ok: false; code: string; message: string; detail?: unknown };

function forbidden(): Fail {
  return {
    ok: false,
    code: 'AUTH_FORBIDDEN',
    message: ERROR_MESSAGES.AUTH_FORBIDDEN ?? 'Anda tidak memiliki akses untuk tindakan ini.',
  };
}

function invalid(error: z.ZodError): Fail {
  const first = error.issues[0];
  return {
    ok: false,
    code: 'VALIDATION_INVALID',
    message: first?.message ?? 'Permintaan tidak valid.',
    detail: { fields: error.issues.map((i) => i.path.join('.')) },
  };
}

async function adminUser() {
  const user = await requireUser();
  return can(user, 'settings.manage') ? user : null;
}

function revalidateAll() {
  revalidatePath('/realisasi', 'layout');
  revalidatePath('/kerjasama', 'layout');
}

export async function updateSettings(values: GeneralSettingsInput): Promise<ActionResult<SettingsValues>> {
  const user = await adminUser();
  if (!user) return forbidden();
  const parsed = generalSettingsSchema.safeParse(values);
  if (!parsed.success) return invalid(parsed.error);
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx`select realisasi.update_settings(${tx.json(parsed.data)}::jsonb) as r`;
      return row!.r as SettingsValues;
    }),
  );
  if (res.ok) revalidateAll();
  return res;
}

export async function setDemoToday(demoToday: string | null): Promise<ActionResult<SettingsValues>> {
  const user = await adminUser();
  if (!user) return forbidden();
  const parsed = demoTodaySchema.safeParse({ demo_today: demoToday });
  if (!parsed.success) return invalid(parsed.error);
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx`select realisasi.update_settings(${tx.json({ demo_today: parsed.data.demo_today })}::jsonb) as r`;
      return row!.r as SettingsValues;
    }),
  );
  if (res.ok) revalidateAll();
  return res;
}

export async function upsertAcademicYear(input: AcademicYearInput): Promise<ActionResult<{ id: number }>> {
  const user = await adminUser();
  if (!user) return forbidden();
  const parsed = academicYearSchema.safeParse(input);
  if (!parsed.success) return invalid(parsed.error);
  const v = parsed.data;
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx`
        select realisasi.upsert_academic_year(${v.id}::int, ${v.label}::text, ${v.start_date}::date, ${v.end_date}::date) as r`;
      return { id: Number(row!.r) };
    }),
  );
  if (res.ok) revalidateAll();
  return res;
}

export async function upsertSemester(input: SemesterInput): Promise<ActionResult<{ id: number }>> {
  const user = await adminUser();
  if (!user) return forbidden();
  const parsed = semesterSchema.safeParse(input);
  if (!parsed.success) return invalid(parsed.error);
  const v = parsed.data;
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx`
        select realisasi.upsert_semester(${v.id}::int, ${v.academic_year_id}::int, ${v.term}::realisasi.semester_term,
                                         ${v.start_date}::date, ${v.end_date}::date, ${v.cutoff_date}::date) as r`;
      return { id: Number(row!.r) };
    }),
  );
  if (res.ok) revalidateAll();
  return res;
}

export async function upsertActivityType(id: number | null, input: ActivityTypeInput): Promise<ActionResult<{ id: number }>> {
  const user = await adminUser();
  if (!user) return forbidden();
  const parsed = activityTypeSchema.safeParse(input);
  if (!parsed.success) return invalid(parsed.error);
  if (id !== null && (!Number.isInteger(id) || id <= 0)) {
    return { ok: false, code: 'BAD_REQUEST', message: 'Permintaan tidak valid.' };
  }
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx`select realisasi.upsert_activity_type(${id}::int, ${tx.json(parsed.data)}::jsonb) as r`;
      return { id: Number(row!.r) };
    }),
  );
  if (res.ok) revalidateAll();
  return res;
}

export async function upsertHoliday(input: HolidayInput): Promise<ActionResult<null>> {
  const user = await adminUser();
  if (!user) return forbidden();
  const parsed = holidaySchema.safeParse(input);
  if (!parsed.success) return invalid(parsed.error);
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      await tx`select realisasi.upsert_holiday(${parsed.data.day}::date, ${parsed.data.name}::text)`;
      return null;
    }),
  );
  if (res.ok) revalidateAll();
  return res;
}

export async function deleteHoliday(day: string): Promise<ActionResult<null>> {
  const user = await adminUser();
  if (!user) return forbidden();
  const parsed = holidaySchema.shape.day.safeParse(day);
  if (!parsed.success) return invalid(parsed.error);
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      await tx`select realisasi.delete_holiday(${parsed.data}::date)`;
      return null;
    }),
  );
  if (res.ok) revalidateAll();
  return res;
}

export async function freezeNow(ay: number, kind: SnapshotKind): Promise<ActionResult<{ snapshot_id: string }>> {
  const user = await adminUser();
  if (!user) return forbidden();
  const parsed = freezeSchema.safeParse({ academic_year_id: ay, kind });
  if (!parsed.success) return invalid(parsed.error);
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx`
        select realisasi.freeze_snapshot(${parsed.data.academic_year_id}::int, ${parsed.data.kind}::realisasi.snapshot_kind,
                                         null::timestamptz, null::uuid) as r`;
      return { snapshot_id: String(row!.r) };
    }),
  );
  if (res.ok) revalidateAll();
  return res;
}

export async function refreeze(snapshotId: string, reason: string): Promise<ActionResult<{ snapshot_id: string }>> {
  const user = await adminUser();
  if (!user) return forbidden();
  const parsed = refreezeSchema.safeParse({ snapshot_id: snapshotId, reason });
  if (!parsed.success) return invalid(parsed.error);
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx`
        select realisasi.refreeze_snapshot(${parsed.data.snapshot_id}::uuid, ${parsed.data.reason}::text) as r`;
      return { snapshot_id: String(row!.r) };
    }),
  );
  if (res.ok) revalidateAll();
  return res;
}

export async function runDailyJobs(): Promise<ActionResult<DailyJobsResult>> {
  const user = await adminUser();
  if (!user) return forbidden();
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx`select realisasi.run_daily_jobs() as r`;
      return row!.r as DailyJobsResult;
    }),
  );
  if (res.ok) revalidateAll();
  return res;
}
