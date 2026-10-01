'use server';
/**
 * Known Activities register server actions (WP-VERIFY, CONTRACTS §3.6 / §6.8; Rules R-51..R-54).
 */
import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { withUser } from '@/lib/db';
import { requireUser } from '@/lib/session';
import { runAction } from '@/lib/realisasi/errors';
import { getKnownSuggestions as querySuggestions } from '@/lib/realisasi/queries/known';
import { knownActivitySchema } from '@/lib/realisasi/schemas/known';
import { bigintIdSchema, uuidSchema } from '@/lib/realisasi/schemas/verification';
import type { ActionResult, KnownActivityPayload, KnownSuggestion } from '@/lib/realisasi/types';

function badRequest(message = 'Permintaan tidak valid.'): ActionResult<never> {
  return { ok: false, code: 'BAD_REQUEST', message };
}

function invalidPayload(error: z.ZodError): ActionResult<never> {
  return {
    ok: false,
    code: 'VALIDATION_INVALID',
    message: error.issues[0]?.message ?? 'Nilai tidak valid.',
    detail: { fields: error.issues.map((i) => i.path.join('.')) },
  };
}

function revalidate(): void {
  revalidatePath('/realisasi', 'layout');
}

const partialKnownSchema = (knownActivitySchema as unknown as z.ZodObject<z.ZodRawShape>).partial();
const noteSchema = z.string().trim().min(1, 'Catatan wajib diisi.').max(2000, 'Catatan maksimal 2000 karakter.');

export async function createKnownActivity(data: KnownActivityPayload): Promise<ActionResult<{ id: number }>> {
  const user = await requireUser();
  const parsed = knownActivitySchema.safeParse(data);
  if (!parsed.success) return invalidPayload(parsed.error);
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx<{ r: number }[]>`
        select realisasi.create_known_activity(${tx.json(parsed.data as never)}::jsonb) as r`;
      return { id: row!.r };
    }),
  );
  if (res.ok) revalidate();
  return res;
}

export async function updateKnownActivity(id: number, data: Partial<KnownActivityPayload>): Promise<ActionResult<null>> {
  const user = await requireUser();
  const pid = bigintIdSchema.safeParse(id);
  if (!pid.success) return badRequest();
  const parsed = partialKnownSchema.safeParse(data);
  if (!parsed.success) return invalidPayload(parsed.error);
  // Only send keys the caller provided (partial update semantics of the RPC).
  const payload = Object.fromEntries(
    Object.entries(parsed.data).filter(([k]) => Object.prototype.hasOwnProperty.call(data, k)),
  );
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      await tx`select realisasi.update_known_activity(${pid.data}::bigint, ${tx.json(payload as never)}::jsonb)`;
      return null;
    }),
  );
  if (res.ok) revalidate();
  return res;
}

export async function matchKnownActivity(id: number, activityId: string): Promise<ActionResult<null>> {
  const user = await requireUser();
  const pid = bigintIdSchema.safeParse(id);
  const aid = uuidSchema.safeParse(activityId);
  if (!pid.success || !aid.success) return badRequest();
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      await tx`select realisasi.match_known_activity(${pid.data}::bigint, ${aid.data}::uuid)`;
      return null;
    }),
  );
  if (res.ok) revalidate();
  return res;
}

export async function unmatchKnownActivity(id: number): Promise<ActionResult<null>> {
  const user = await requireUser();
  const pid = bigintIdSchema.safeParse(id);
  if (!pid.success) return badRequest();
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      await tx`select realisasi.unmatch_known_activity(${pid.data}::bigint)`;
      return null;
    }),
  );
  if (res.ok) revalidate();
  return res;
}

export async function dismissKnownActivity(id: number, note: string): Promise<ActionResult<null>> {
  const user = await requireUser();
  const pid = bigintIdSchema.safeParse(id);
  if (!pid.success) return badRequest();
  const pnote = noteSchema.safeParse(note);
  if (!pnote.success) return { ok: false, code: 'VALIDATION_REQUIRED', message: pnote.error.issues[0]?.message ?? 'Catatan wajib diisi.' };
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      await tx`select realisasi.dismiss_known_activity(${pid.data}::bigint, ${pnote.data}::text)`;
      return null;
    }),
  );
  if (res.ok) revalidate();
  return res;
}

export async function nudgeKnownActivity(id: number): Promise<ActionResult<{ nudged_at: string }>> {
  const user = await requireUser();
  const pid = bigintIdSchema.safeParse(id);
  if (!pid.success) return badRequest();
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx<{ r: string }[]>`select realisasi.nudge_known_activity(${pid.data}::bigint) as r`;
      return { nudged_at: row!.r };
    }),
  );
  if (res.ok) revalidate();
  return res;
}

export async function getKnownSuggestions(id: number): Promise<ActionResult<KnownSuggestion[]>> {
  const user = await requireUser();
  const pid = bigintIdSchema.safeParse(id);
  if (!pid.success) return badRequest();
  return runAction(() => withUser(user.id, (tx) => querySuggestions(tx, pid.data)));
}
