/**
 * Pure state model of the participant editor (frontend review H-2).
 *
 * Every mutation is an action applied to the *latest* state, so results of slow requests
 * (lookups) merge into whatever the user did in the meantime instead of
 * restoring the array captured when the request started. Unit-tested in `participants-model.test.ts`.
 */
import type { EmployeeLookupStatus, StudentLookupStatus } from '@/lib/realisasi/queries/lookups';
import type { ParticipantVersion, StaffRowPayload, StudentRowPayload, StudentSection } from '@/lib/realisasi/types';

export type RowStatus = StudentLookupStatus | EmployeeLookupStatus;

export interface StudentRow {
  key: string;
  section: StudentSection;
  nrp: string;
  status: RowStatus;
  blocking: boolean;
  full_name: string | null;
  faculty_name: string | null;
  prodi_name: string | null;
  home_institution: string;
  home_student_number: string;
  home_country_code: string;
  serverError?: string;
}

export interface StaffRow {
  key: string;
  employee_id: string;
  status: RowStatus;
  blocking: boolean;
  full_name: string | null;
  unit_name: string | null;
  serverError?: string;
}

export interface ParticipantsState {
  students: StudentRow[];
  staff: StaffRow[];
}

export interface DbRowError {
  section: 'internal' | 'inbound' | 'staff';
  index: number;
  id: string;
  code: string;
}

export type ParticipantsAction =
  | { type: 'addStudents'; rows: StudentRow[] }
  | { type: 'addStaff'; rows: StaffRow[] }
  | { type: 'removeStudent'; key: string }
  | { type: 'removeStaff'; key: string }
  | { type: 'patchStudent'; key: string; patch: Partial<Omit<StudentRow, 'key'>> }
  | { type: 'markDbErrors'; errors: DbRowError[]; message: string };

const DB_CODE_STATUS: Record<string, RowStatus> = {
  R16_NRP_NOT_FOUND: 'not_found',
  R19_EMPLOYEE_NOT_FOUND: 'not_found',
  R22_DUPLICATE_NRP: 'duplicate',
  R22_DUPLICATE_EMPLOYEE: 'duplicate',
  R17_NOT_INBOUND: 'not_inbound',
  R16_SECTION_MISMATCH: 'is_inbound',
};

const newKey = () => globalThis.crypto.randomUUID();

export function fromVersion(v: ParticipantVersion | null): ParticipantsState {
  if (!v) return { students: [], staff: [] };
  return {
    students: v.students.map((s) => ({
      key: newKey(),
      section: s.section,
      nrp: s.nrp,
      status: s.registry_status === 'active' ? 'ok' : s.registry_status,
      blocking: false,
      full_name: s.full_name,
      faculty_name: s.faculty_name,
      prodi_name: s.prodi_name,
      home_institution: s.home_institution ?? '',
      home_student_number: s.home_student_number ?? '',
      home_country_code: s.home_country_code ?? '',
    })),
    staff: v.staff.map((s) => ({
      key: newKey(),
      employee_id: s.employee_id,
      status: s.registry_status === 'active' ? 'ok' : s.registry_status,
      blocking: false,
      full_name: s.full_name,
      unit_name: s.unit_name,
    })),
  };
}

export function participantsReducer(state: ParticipantsState, action: ParticipantsAction): ParticipantsState {
  switch (action.type) {
    case 'addStudents': {
      // Re-check duplicates against the latest rows: another lookup may have finished first.
      const have = new Set(state.students.map((s) => s.nrp));
      const rows = action.rows.filter((r) => (have.has(r.nrp) ? false : (have.add(r.nrp), true)));
      return rows.length ? { ...state, students: [...state.students, ...rows] } : state;
    }
    case 'addStaff': {
      const have = new Set(state.staff.map((s) => s.employee_id));
      const rows = action.rows.filter((r) => (have.has(r.employee_id) ? false : (have.add(r.employee_id), true)));
      return rows.length ? { ...state, staff: [...state.staff, ...rows] } : state;
    }
    case 'removeStudent':
      return { ...state, students: state.students.filter((s) => s.key !== action.key) };
    case 'removeStaff':
      return { ...state, staff: state.staff.filter((s) => s.key !== action.key) };
    case 'patchStudent':
      return {
        ...state,
        students: state.students.map((s) => (s.key === action.key ? { ...s, ...action.patch } : s)),
      };
    case 'markDbErrors': {
      const find = (id: string, staff: boolean) => action.errors.find((e) => e.id === id && (e.section === 'staff') === staff);
      return {
        students: state.students.map((r) => {
          const e = find(r.nrp, false);
          return e ? { ...r, blocking: true, status: DB_CODE_STATUS[e.code] ?? 'not_found', serverError: action.message } : r;
        }),
        staff: state.staff.map((r) => {
          const e = find(r.employee_id, true);
          return e ? { ...r, blocking: true, status: DB_CODE_STATUS[e.code] ?? 'not_found', serverError: action.message } : r;
        }),
      };
    }
    default: {
      const _exhaustive: never = action;
      return _exhaustive;
    }
  }
}

export function hasBlocking(s: ParticipantsState): boolean {
  return s.students.some((r) => r.blocking) || s.staff.some((r) => r.blocking);
}

export interface ParticipantsPayload {
  students: StudentRowPayload[];
  staff: StaffRowPayload[];
}

/** The `saveParticipants` payload, or null while red (blocking) rows exist (they are never saved). */
export function toParticipantsPayload(s: ParticipantsState): ParticipantsPayload | null {
  if (hasBlocking(s)) return null;
  return {
    students: s.students.map((r) =>
      r.section === 'internal'
        ? { section: 'internal', nrp: r.nrp }
        : {
            section: 'inbound',
            nrp: r.nrp,
            home_institution: r.home_institution.trim() || null,
            home_student_number: r.home_student_number.trim() || null,
            home_country_code: r.home_country_code || null,
          },
    ),
    staff: s.staff.map((r) => ({ employee_id: r.employee_id })),
  };
}

export function dbRowErrors(detail: unknown): DbRowError[] {
  if (typeof detail !== 'object' || detail === null || !('rows' in detail)) return [];
  const rows = (detail as { rows: unknown }).rows;
  return Array.isArray(rows) ? (rows.filter((r) => typeof r === 'object' && r !== null && 'id' in r) as DbRowError[]) : [];
}
