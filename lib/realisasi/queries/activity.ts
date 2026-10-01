/**
 * Activity read helpers (WP-SUBMIT, CONTRACTS §6.8). SERVER ONLY (takes a `withUser` tx).
 * Errors that mean "not visible" are turned into `null` inside a savepoint so the surrounding
 * transaction stays usable for further reads.
 */
import type { Tx } from '@/lib/db';
import { parseDbError } from '@/lib/realisasi/errors';
import type { ActivityDetail, ChecklistItem, ParticipantCounts, ParticipantVersion } from '@/lib/realisasi/types';

const HIDDEN_CODES = new Set(['NOT_FOUND', 'AUTH_FORBIDDEN']);
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isUuid(v: string | null | undefined): v is string {
  return typeof v === 'string' && UUID_RE.test(v);
}

async function nullOnHidden<T>(tx: Tx, fn: (sp: Tx) => Promise<T>): Promise<T | null> {
  try {
    return (await tx.savepoint((sp) => fn(sp as unknown as Tx))) as T;
  } catch (e) {
    const err = parseDbError(e);
    if (HIDDEN_CODES.has(err.code)) return null;
    throw e;
  }
}

/** `activity_detail()`; null on NOT_FOUND (not visible to the caller) or malformed id. */
export async function getActivityDetail(tx: Tx, id: string): Promise<ActivityDetail | null> {
  if (!isUuid(id)) return null;
  return nullOnHidden(tx, async (sp) => {
    const [row] = await sp<{ r: ActivityDetail | null }[]>`select realisasi.activity_detail(${id}::uuid) as r`;
    return row?.r ?? null;
  });
}

/** `participant_version()`; null version = latest (draft included for unit editors / mobility). */
export async function getParticipantVersion(tx: Tx, activityId: string, version?: number): Promise<ParticipantVersion | null> {
  if (!isUuid(activityId)) return null;
  return nullOnHidden(tx, async (sp) => {
    const [row] = await sp<{ r: ParticipantVersion | null }[]>`
      select realisasi.participant_version(${activityId}::uuid, ${version ?? null}::int) as r`;
    return row?.r ?? null;
  });
}

export async function getParticipantCounts(tx: Tx, activityId: string): Promise<ParticipantCounts | null> {
  if (!isUuid(activityId)) return null;
  return nullOnHidden(tx, async (sp) => {
    const [row] = await sp<{ r: ParticipantCounts | null }[]>`select realisasi.participant_counts(${activityId}::uuid) as r`;
    return row?.r ?? null;
  });
}

export async function getSubmissionChecklist(tx: Tx, activityId: string): Promise<ChecklistItem[] | null> {
  if (!isUuid(activityId)) return null;
  return nullOnHidden(tx, async (sp) => {
    const [row] = await sp<{ r: ChecklistItem[] | null }[]>`select realisasi.submission_checklist(${activityId}::uuid) as r`;
    return row?.r ?? null;
  });
}

/**
 * Previous non-draft version (for MobilityActions' diff): the highest version below `version`
 * that is not a draft. Returns null when none is visible.
 */
export async function getPreviousParticipantVersion(
  tx: Tx,
  activityId: string,
  versions: ActivityDetail['participants']['versions'],
  current: number,
): Promise<ParticipantVersion | null> {
  const prev = versions
    .filter((v) => v.version < current && v.status !== 'draft')
    .sort((a, b) => b.version - a.version)[0];
  if (!prev) return null;
  return getParticipantVersion(tx, activityId, prev.version);
}
