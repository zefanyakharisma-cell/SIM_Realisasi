/**
 * Duplicate candidate reads (WP-VERIFY, CONTRACTS §6.8). SERVER ONLY.
 * Rows come from `realisasi.v_duplicate_candidates` (RLS: IO only).
 */
import type { Tx } from '@/lib/db';
import type { DupStatus, DuplicateCandidateRow } from '@/lib/realisasi/types';

export const DUP_STATUSES = ['open', 'linked', 'dismissed'] as const satisfies readonly DupStatus[];

export function parseDupStatus(v: string | string[] | null | undefined): DupStatus {
  const s = Array.isArray(v) ? v[0] : v;
  return s && (DUP_STATUSES as readonly string[]).includes(s) ? (s as DupStatus) : 'open';
}

/** Candidates with the given status (default `open`), highest score first. */
export async function listDuplicateCandidates(tx: Tx, f: { status?: DupStatus }): Promise<DuplicateCandidateRow[]> {
  const status = f.status ?? 'open';
  const rows = await tx<DuplicateCandidateRow[]>`
    select d.* from realisasi.v_duplicate_candidates d
     where d.status::text = ${status}::text
     order by d.score desc, coalesce(d.resolved_at, now()) desc, d.id desc`;
  return Array.from(rows);
}

/** Open-candidate count per status for the tab badges. */
export async function countDuplicateCandidates(tx: Tx): Promise<Record<DupStatus, number>> {
  const rows = await tx<Array<{ status: DupStatus; n: number }>>`
    select status::text as status, count(*)::int as n from realisasi.v_duplicate_candidates group by status`;
  const out: Record<DupStatus, number> = { open: 0, linked: 0, dismissed: 0 };
  for (const r of rows) out[r.status] = r.n;
  return out;
}
