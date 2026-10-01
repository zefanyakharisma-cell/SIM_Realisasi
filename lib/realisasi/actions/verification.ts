'use server';
/**
 * Verification server actions (WP-VERIFY, CONTRACTS §3.4 / §6.8).
 * requireUser → zod-validate → one `withUser` transaction → RPC. The DB enforces team membership
 * and track state; failures come back as `ActionResult` with the Indonesian SQL message.
 */
import { revalidatePath } from 'next/cache';
import type { z } from 'zod';
import { withUser } from '@/lib/db';
import { requireUser } from '@/lib/session';
import { runAction } from '@/lib/realisasi/errors';
import {
  approveSchema,
  mobilityRevisionSchema,
  rejectSchema,
  requestRevisionSchema,
} from '@/lib/realisasi/schemas/verification';
import type { ActionResult, ActivityStatusResult, RejectReason, RowNotePayload } from '@/lib/realisasi/types';

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

export async function partnershipApprove(id: string, note?: string | null): Promise<ActionResult<ActivityStatusResult>> {
  const user = await requireUser();
  const parsed = approveSchema.safeParse({ id, note });
  if (!parsed.success) return invalid(parsed.error);
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx<{ r: ActivityStatusResult }[]>`
        select realisasi.partnership_approve(${parsed.data.id}::uuid, ${parsed.data.note}::text) as r`;
      return row!.r;
    }),
  );
  if (res.ok) revalidate();
  return res;
}

export async function partnershipRequestRevision(id: string, note: string): Promise<ActionResult<ActivityStatusResult>> {
  const user = await requireUser();
  const parsed = requestRevisionSchema.safeParse({ id, note });
  if (!parsed.success) return invalid(parsed.error, { note: 'R27_NOTE_REQUIRED' });
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx<{ r: ActivityStatusResult }[]>`
        select realisasi.partnership_request_revision(${parsed.data.id}::uuid, ${parsed.data.note}::text) as r`;
      return row!.r;
    }),
  );
  if (res.ok) revalidate();
  return res;
}

export async function partnershipReject(id: string, reason: RejectReason, note: string): Promise<ActionResult<ActivityStatusResult>> {
  const user = await requireUser();
  const parsed = rejectSchema.safeParse({ id, reason, note });
  if (!parsed.success) return invalid(parsed.error, { reason: 'R26_REASON_REQUIRED', note: 'R26_NOTE_REQUIRED' });
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx<{ r: ActivityStatusResult }[]>`
        select realisasi.partnership_reject(${parsed.data.id}::uuid, ${parsed.data.reason}::text, ${parsed.data.note}::text) as r`;
      return row!.r;
    }),
  );
  if (res.ok) revalidate();
  return res;
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

export async function mobilityRequestRevision(
  id: string,
  note: string,
  rowNotes: RowNotePayload[],
): Promise<ActionResult<ActivityStatusResult>> {
  const user = await requireUser();
  const parsed = mobilityRevisionSchema.safeParse({ id, note, rowNotes: rowNotes ?? [] });
  if (!parsed.success) return invalid(parsed.error, { note: 'R27_NOTE_REQUIRED', rowNotes: 'VALIDATION_INVALID' });
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx<{ r: ActivityStatusResult }[]>`
        select realisasi.mobility_request_revision(
          ${parsed.data.id}::uuid, ${parsed.data.note}::text, ${tx.json(parsed.data.rowNotes)}::jsonb) as r`;
      return row!.r;
    }),
  );
  if (res.ok) revalidate();
  return res;
}
