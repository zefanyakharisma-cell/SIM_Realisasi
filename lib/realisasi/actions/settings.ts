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
  agendaSchema,
  demoTodaySchema,
  freezeSchema,
  generalSettingsSchema,
  refreezeSchema,
  semesterSchema,
  type AcademicYearInput,
  type AgendaInput,
  type GeneralSettingsInput,
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

/** Add (id null) or edit one Jenis Kegiatan: program, name, Keterangan, Awards category, 1.19.S1 flag, active. */
export async function saveAgenda(input: AgendaInput): Promise<ActionResult<{ id: number }>> {
  const user = await adminUser();
  if (!user) return forbidden();
  const parsed = agendaSchema.safeParse(input);
  if (!parsed.success) return invalid(parsed.error);
  const { id, ...data } = parsed.data;
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx`select realisasi.save_agenda(${id}::int, ${tx.json(data)}::jsonb) as r`;
      return { id: Number((row!.r as { id: number }).id) };
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
