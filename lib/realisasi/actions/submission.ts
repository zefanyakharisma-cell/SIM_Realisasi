'use server';
/**
 * Submission server actions (WP-SUBMIT, CONTRACTS §6.7 / §6.8).
 * Every action: requireUser → zod-validate inputs → one `withUser` transaction → RPC.
 * The DB enforces permissions/state; errors come back as `ActionResult` with Indonesian messages.
 */
import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { withUser } from '@/lib/db';
import { requireUser } from '@/lib/session';
import { runAction } from '@/lib/realisasi/errors';
import {
  activityDetailPartialSchema,
  activityDetailSchema,
  editNoteSchema,
  evidenceLinkSchema,
} from '@/lib/realisasi/schemas/activity';
import { participantsSchema } from '@/lib/realisasi/schemas/participants';
import type {
  ActionResult,
  ActivityDetailPayload,
  RegisteredFile,
  SaveParticipantsResult,
  StaffRowPayload,
  StudentRowPayload,
  SubmitResult,
} from '@/lib/realisasi/types';

const uuidSchema = z.string().uuid();

function badRequest(message: string, detail?: unknown): ActionResult<never> {
  return { ok: false, code: 'BAD_REQUEST', message, detail };
}

function revalidate(): void {
  revalidatePath('/realisasi', 'layout');
}

export async function saveActivityDraft(id: string | null, data: ActivityDetailPayload): Promise<ActionResult<{ id: string }>> {
  const user = await requireUser();
  if (id !== null && !uuidSchema.safeParse(id).success) return badRequest('Permintaan tidak valid.');
  const parsed = activityDetailSchema.safeParse(data);
  if (!parsed.success) {
    return {
      ok: false,
      code: 'VALIDATION_INVALID',
      message: parsed.error.issues[0]?.message ?? 'Nilai tidak valid.',
      detail: { fields: parsed.error.issues.map((i) => i.path.join('.')) },
    };
  }
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx<{ r: string }[]>`
        select realisasi.save_activity_draft(${id}::uuid, ${tx.json(parsed.data as never)}::jsonb)::text as r`;
      return { id: row!.r };
    }),
  );
  // No revalidatePath here (frontend review M-7): every /realisasi page is dynamic, and a
  // revalidation inside a server action makes Next re-render the whole wizard route in the
  // response of every 1.5 s autosave. Callers refresh explicitly where they need fresh data.
  return res;
}

export async function deleteDraft(id: string): Promise<ActionResult<null>> {
  const user = await requireUser();
  if (!uuidSchema.safeParse(id).success) return badRequest('Permintaan tidak valid.');
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      await tx`select realisasi.delete_draft(${id}::uuid)`;
      return null;
    }),
  );
  if (res.ok) revalidate();
  return res;
}

export async function ensureParticipantDraft(activityId: string): Promise<ActionResult<{ version_id: string; version: number }>> {
  const user = await requireUser();
  if (!uuidSchema.safeParse(activityId).success) return badRequest('Permintaan tidak valid.');
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx<{ r: { version_id: string; version: number; created: boolean } }[]>`
        select realisasi.ensure_participant_draft(${activityId}::uuid) as r`;
      return { version_id: row!.r.version_id, version: row!.r.version };
    }),
  );
  if (res.ok) revalidate();
  return res;
}

export async function saveParticipants(
  activityId: string,
  students: StudentRowPayload[],
  staff: StaffRowPayload[],
): Promise<ActionResult<SaveParticipantsResult>> {
  const user = await requireUser();
  if (!uuidSchema.safeParse(activityId).success) return badRequest('Permintaan tidak valid.');
  const parsed = participantsSchema.safeParse({ students, staff });
  if (!parsed.success) return badRequest(parsed.error.issues[0]?.message ?? 'Data peserta tidak valid.');
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx<{ r: SaveParticipantsResult }[]>`
        select realisasi.save_participants(${activityId}::uuid,
                                           ${tx.json(parsed.data.students as never)}::jsonb,
                                           ${tx.json(parsed.data.staff as never)}::jsonb) as r`;
      return row!.r;
    }),
  );
  // No revalidatePath (M-7, see saveActivityDraft).
  return res;
}

export async function submitActivity(id: string): Promise<ActionResult<SubmitResult>> {
  const user = await requireUser();
  if (!uuidSchema.safeParse(id).success) return badRequest('Permintaan tidak valid.');
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx<{ r: SubmitResult }[]>`select realisasi.submit_activity(${id}::uuid) as r`;
      return row!.r;
    }),
  );
  if (res.ok) revalidate();
  return res;
}

export async function editVerifiedActivity(
  id: string,
  data: Partial<ActivityDetailPayload>,
  note: string,
): Promise<ActionResult<{ diff: Record<string, unknown>; in_frozen_period: boolean }>> {
  const user = await requireUser();
  if (!uuidSchema.safeParse(id).success) return badRequest('Permintaan tidak valid.');
  const parsedNote = editNoteSchema.safeParse(note);
  if (!parsedNote.success) return { ok: false, code: 'VALIDATION_REQUIRED', message: parsedNote.error.issues[0]!.message, detail: { fields: ['note'] } };
  const parsed = activityDetailPartialSchema.safeParse(data);
  if (!parsed.success) return badRequest(parsed.error.issues[0]?.message ?? 'Nilai tidak valid.');
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx<{ r: { diff: Record<string, unknown>; in_frozen_period: boolean } }[]>`
        select realisasi.edit_verified_activity(${id}::uuid, ${tx.json(parsed.data as never)}::jsonb, ${parsedNote.data}::text) as r`;
      return row!.r;
    }),
  );
  if (res.ok) revalidate();
  return res;
}

export async function commitParticipantEdit(
  activityId: string,
  note: string,
): Promise<ActionResult<{ version: number; diff: unknown; in_frozen_period: boolean }>> {
  const user = await requireUser();
  if (!uuidSchema.safeParse(activityId).success) return badRequest('Permintaan tidak valid.');
  const parsedNote = editNoteSchema.safeParse(note);
  if (!parsedNote.success) return { ok: false, code: 'VALIDATION_REQUIRED', message: parsedNote.error.issues[0]!.message, detail: { fields: ['note'] } };
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx<{ r: { version: number; diff: unknown; in_frozen_period: boolean } }[]>`
        select realisasi.commit_participant_edit(${activityId}::uuid, ${parsedNote.data}::text) as r`;
      return row!.r;
    }),
  );
  if (res.ok) revalidate();
  return res;
}

export async function addEvidenceLink(activityId: string, url: string, label: string): Promise<ActionResult<RegisteredFile>> {
  const user = await requireUser();
  if (!uuidSchema.safeParse(activityId).success) return badRequest('Permintaan tidak valid.');
  const parsed = evidenceLinkSchema.safeParse({ url, label });
  if (!parsed.success) return { ok: false, code: 'VALIDATION_INVALID', message: parsed.error.issues[0]!.message };
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      const [row] = await tx<{ r: RegisteredFile }[]>`
        select realisasi.add_evidence_link(${activityId}::uuid, ${parsed.data.url}::text, ${parsed.data.label}::text) as r`;
      return row!.r;
    }),
  );
  if (res.ok) revalidate();
  return res;
}

export async function removeActivityFile(fileId: number): Promise<ActionResult<null>> {
  const user = await requireUser();
  if (!Number.isSafeInteger(fileId) || fileId <= 0) return badRequest('Permintaan tidak valid.');
  const res = await runAction(() =>
    withUser(user.id, async (tx) => {
      await tx`select realisasi.remove_activity_file(${fileId}::bigint)`;
      return null;
    }),
  );
  if (res.ok) revalidate();
  return res;
}
