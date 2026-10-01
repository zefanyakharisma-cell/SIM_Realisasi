import type { ParticipantStaffRow, ParticipantStudentRow, ParticipantVersion } from '@/lib/realisasi/types';

export type RowChange = 'added' | 'removed' | 'changed' | 'same';

export interface DiffEntry<R> {
  /** Business key: NRP for students, employee ID for staff. */
  key: string;
  change: RowChange;
  before?: R;
  after?: R;
  changedFields: string[];
}

export interface ParticipantDiff {
  students: Array<DiffEntry<ParticipantStudentRow>>;
  staff: Array<DiffEntry<ParticipantStaffRow>>;
}

/** Fields that matter to the reviewer (ids, notes, registry status and hrefs are ignored). */
export const STUDENT_DIFF_FIELDS = [
  'section',
  'full_name',
  'faculty_name',
  'prodi_name',
  'home_institution',
  'home_student_number',
  'home_country_code',
  'transcript_path',
] as const satisfies ReadonlyArray<keyof ParticipantStudentRow>;

export const STAFF_DIFF_FIELDS = ['full_name', 'unit_name'] as const satisfies ReadonlyArray<keyof ParticipantStaffRow>;

function norm(v: unknown): unknown {
  return v === undefined || v === '' ? null : v;
}

function diffRows<R>(
  prev: R[],
  next: R[],
  keyOf: (r: R) => string,
  fields: ReadonlyArray<keyof R>,
): Array<DiffEntry<R>> {
  const prevMap = new Map<string, R>();
  for (const r of prev) prevMap.set(keyOf(r), r);
  const seen = new Set<string>();
  const out: Array<DiffEntry<R>> = [];

  for (const after of next) {
    const key = keyOf(after);
    seen.add(key);
    const before = prevMap.get(key);
    if (!before) {
      out.push({ key, change: 'added', after, changedFields: [] });
      continue;
    }
    const changedFields = fields.filter((f) => norm(before[f]) !== norm(after[f])).map(String);
    out.push({ key, change: changedFields.length ? 'changed' : 'same', before, after, changedFields });
  }
  // Removed rows are appended in their previous order.
  for (const before of prev) {
    const key = keyOf(before);
    if (!seen.has(key)) out.push({ key, change: 'removed', before, changedFields: [] });
  }
  return out;
}

/**
 * Row-level diff between two participant set versions (R-21). With `prev = null`
 * every row of `next` is reported as `same` (first version: nothing to compare).
 */
export function diffParticipantVersions(prev: ParticipantVersion | null, next: ParticipantVersion): ParticipantDiff {
  if (!prev) {
    return {
      students: next.students.map((r) => ({ key: r.nrp, change: 'same' as const, before: r, after: r, changedFields: [] })),
      staff: next.staff.map((r) => ({ key: r.employee_id, change: 'same' as const, before: r, after: r, changedFields: [] })),
    };
  }
  return {
    students: diffRows(prev.students, next.students, (r) => r.nrp, STUDENT_DIFF_FIELDS),
    staff: diffRows(prev.staff, next.staff, (r) => r.employee_id, STAFF_DIFF_FIELDS),
  };
}

export function summarizeDiff(d: ParticipantDiff): { added: number; removed: number; changed: number } {
  const all = [...d.students, ...d.staff];
  return {
    added: all.filter((e) => e.change === 'added').length,
    removed: all.filter((e) => e.change === 'removed').length,
    changed: all.filter((e) => e.change === 'changed').length,
  };
}
