'use server';
/**
 * Duplicate / event-group server actions (WP-VERIFY, CONTRACTS §3.5 / §6.8).
 */
import { revalidatePath } from 'next/cache';
import type { z } from 'zod';
import { withUser } from '@/lib/db';
import { requireUser } from '@/lib/session';
import { runAction } from '@/lib/realisasi/errors';
import { findActivityByCode as findByCode } from '@/lib/realisasi/queries/activities';
import {
  activityCodeSchema,
  linkActivitiesSchema,
  linkDuplicatesSchema,
  unlinkSchema,
  uuidSchema,
} from '@/lib/realisasi/schemas/verification';
import type { ActionResult, ActivityStatus } from '@/lib/realisasi/types';

export interface LinkResult {
  event_group_id: string;
  activity_ids: string[];
}

function invalid(error: z.ZodError, codes: Record<string, string> = {}): ActionResult<never> {
  const issue = error.issues[0];
  const field = String(issue?.path[0] ?? '');
  return { ok: false, code: codes[field] ?? 'BAD_REQUEST', message: issue?.message ?? 'Permintaan tidak valid.' };
}

function revalidate(): void {
  revalidatePath('/realisasi', 'layout');
}

export async function linkDuplicates(candidateId: number, note?: string | null): Promise<ActionResult<LinkResult>> {
  const user = await requireUser();
  const parsed = linkDuplicatesSchema.safeParse({ candidateId, note });
  if (!parsed.success) return invalid(parsed.error);
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx<{ r: LinkResult }[]>`
        select realisasi.link_duplicates(${parsed.data.candidateId}::bigint, ${parsed.data.note}::text) as r`;
      return row!.r;
    }),
  );
  if (res.ok) revalidate();
  return res;
}

export async function linkActivities(a: string, b: string, note: string): Promise<ActionResult<LinkResult>> {
  const user = await requireUser();
  const parsed = linkActivitiesSchema.safeParse({ a, b, note });
  if (!parsed.success) return invalid(parsed.error, { note: 'VALIDATION_REQUIRED' });
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx<{ r: LinkResult }[]>`
        select realisasi.link_activities(${parsed.data.a}::uuid, ${parsed.data.b}::uuid, ${parsed.data.note}::text) as r`;
      return row!.r;
    }),
  );
  if (res.ok) revalidate();
  return res;
}

export async function dismissDuplicate(candidateId: number, note?: string | null): Promise<ActionResult<null>> {
  const user = await requireUser();
  const parsed = linkDuplicatesSchema.safeParse({ candidateId, note });
  if (!parsed.success) return invalid(parsed.error);
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      await tx`select realisasi.dismiss_duplicate(${parsed.data.candidateId}::bigint, ${parsed.data.note}::text)`;
      return null;
    }),
  );
  if (res.ok) revalidate();
  return res;
}

export async function unlinkActivity(id: string, note: string): Promise<ActionResult<LinkResult>> {
  const user = await requireUser();
  const parsed = unlinkSchema.safeParse({ id, note });
  if (!parsed.success) return invalid(parsed.error, { note: 'VALIDATION_REQUIRED' });
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx<{ r: LinkResult }[]>`
        select realisasi.unlink_activity(${parsed.data.id}::uuid, ${parsed.data.note}::text) as r`;
      return row!.r;
    }),
  );
  if (res.ok) revalidate();
  return res;
}

export interface ActivityLookup {
  id: string;
  code: string;
  name: string;
  status: ActivityStatus;
  submitter_unit_name: string;
  event_group_id: string;
}

/** Resolves an activity code for the manual "Tautkan dengan kegiatan lain" dialog (IO only). */
export async function lookupActivityByCode(code: string, exceptId?: string): Promise<ActionResult<ActivityLookup>> {
  const user = await requireUser();
  const parsed = activityCodeSchema.safeParse(code);
  if (!parsed.success) return { ok: false, code: 'VALIDATION_INVALID', message: parsed.error.issues[0]?.message ?? 'Kode tidak valid.' };
  if (exceptId !== undefined && !uuidSchema.safeParse(exceptId).success) {
    return { ok: false, code: 'BAD_REQUEST', message: 'Permintaan tidak valid.' };
  }
  const res = await runAction(() => withUser(user.id, (tx) => findByCode(tx, parsed.data)));
  if (!res.ok) return res;
  if (!res.data) return { ok: false, code: 'NOT_FOUND', message: 'Kegiatan dengan kode tersebut tidak ditemukan.' };
  if (exceptId && res.data.id === exceptId) {
    return { ok: false, code: 'VALIDATION_INVALID', message: 'Pilih kegiatan lain, bukan kegiatan ini sendiri.' };
  }
  return { ok: true, data: res.data };
}
