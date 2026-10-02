'use server';
/**
 * Verification server actions (WP-VERIFY, CONTRACTS §3.4 / §6.8; Revisi V.1: Mobility is the only track).
 * requireUser → zod-validate → one `withUser` transaction → RPC. The DB enforces team membership
 * and track state; failures come back as `ActionResult` with the Indonesian SQL message.
 */
import { revalidatePath } from 'next/cache';
import type { z } from 'zod';
import { withUser } from '@/lib/db';
import { requireUser } from '@/lib/session';
import { runAction } from '@/lib/realisasi/errors';
import { approveSchema, mobilityRevisionSchema, resolveConflictSchema } from '@/lib/realisasi/schemas/verification';
import type { ActionResult, ActivityStatusResult } from '@/lib/realisasi/types';

/** Maps a zod failure to the contract error code of the first issue's field. */
function invalid(error: z.ZodError, codes: Record<string, string> = {}): ActionResult<never> {
  const issue = error.issues[0];
  const field = String(issue?.path[0] ?? '');
  return {
    ok: false,
    code: codes[field] ?? 'BAD_REQUEST',
    message: issue?.message ?? 'Permintaan tidak valid.',
    detail: { fields: error.issues.map((i) => i.path.join('.')) },
  };
}

function revalidate(): void {
  revalidatePath('/realisasi', 'layout');
}

export async function mobilityApprove(id: string, note?: string | null): Promise<ActionResult<ActivityStatusResult>> {
  const user = await requireUser();
  const parsed = approveSchema.safeParse({ id, note });
  if (!parsed.success) return invalid(parsed.error);
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx<{ r: ActivityStatusResult }[]>`
        select realisasi.mobility_approve(${parsed.data.id}::uuid, ${parsed.data.note}::text) as r`;
      return row!.r;
    }),
  );
  if (res.ok) revalidate();
  return res;
}

/** Revisi V.1: one revision note for the whole submission (no per-row notes). */
export async function mobilityRequestRevision(id: string, note: string): Promise<ActionResult<ActivityStatusResult>> {
  const user = await requireUser();
  const parsed = mobilityRevisionSchema.safeParse({ id, note });
  if (!parsed.success) return invalid(parsed.error, { note: 'R27_NOTE_REQUIRED' });
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx<{ r: ActivityStatusResult }[]>`
        select realisasi.mobility_request_revision(${parsed.data.id}::uuid, ${parsed.data.note}::text) as r`;
      return row!.r;
    }),
  );
  if (res.ok) revalidate();
  return res;
}

/** Rule 2.1: Mobility keeps the student on one of the two activities (may change an earlier decision). */
export async function resolveConflict(
  conflictId: number,
  keptActivityId: string,
  note?: string | null,
): Promise<ActionResult<{ id: number; kept_activity_id: string; open_remaining: number }>> {
  const user = await requireUser();
  const parsed = resolveConflictSchema.safeParse({ conflictId, keptActivityId, note });
  if (!parsed.success) return invalid(parsed.error);
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx<{ r: { id: number; kept_activity_id: string; open_remaining: number } }[]>`
        select realisasi.resolve_conflict(${parsed.data.conflictId}::bigint, ${parsed.data.keptActivityId}::uuid, ${parsed.data.note}::text) as r`;
      return row!.r;
    }),
  );
  if (res.ok) revalidate();
  return res;
}
