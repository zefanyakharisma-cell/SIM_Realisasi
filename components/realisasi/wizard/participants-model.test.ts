import { describe, expect, it } from 'vitest';
import {
  participantsReducer,
  toParticipantsPayload,
  type ParticipantsAction,
  type ParticipantsState,
  type StaffRow,
  type StudentRow,
} from './participants-model';

const student = (nrp: string, over: Partial<StudentRow> = {}): StudentRow => ({
  key: `k-${nrp}`,
  section: 'inbound',
  nrp,
  status: 'ok',
  blocking: false,
  full_name: nrp,
  faculty_name: null,
  prodi_name: null,
  home_institution: '',
  home_student_number: '',
  home_country_code: '',
  ...over,
});
const staff = (id: string, over: Partial<StaffRow> = {}): StaffRow => ({
  key: `k-${id}`,
  employee_id: id,
  status: 'ok',
  blocking: false,
  full_name: id,
  unit_name: null,
  ...over,
});

/** Simulates the editor: a single source of truth that every (possibly late) action is applied to. */
function store(initial: ParticipantsState) {
  let s = initial;
  return {
    dispatch: (a: ParticipantsAction) => (s = participantsReducer(s, a)),
    get: () => s,
  };
}

describe('participantsReducer (H-2 lost updates)', () => {
  it('two overlapping edits on different inbound rows both survive', () => {
    const st = store({ students: [student('X1'), student('X2')], staff: [] });
    st.dispatch({ type: 'patchStudent', key: 'k-X2', patch: { home_institution: 'B' } });
    st.dispatch({ type: 'patchStudent', key: 'k-X1', patch: { home_institution: 'A' } });
    expect(st.get().students.map((s) => s.home_institution)).toEqual(['A', 'B']);
    expect(toParticipantsPayload(st.get())?.students.map((s) => s.home_institution)).toEqual(['A', 'B']);
  });

  it('a slow student lookup does not restore staff rows removed meanwhile', () => {
    const st = store({ students: [], staff: [staff('PG1'), staff('PG2')] });
    // "Cek NRP" started here (slow) ... user removes PG1 ...
    st.dispatch({ type: 'removeStaff', key: 'k-PG1' });
    // ... and the lookup finally returns.
    st.dispatch({ type: 'addStudents', rows: [student('A1', { section: 'internal' })] });
    expect(st.get().staff.map((s) => s.employee_id)).toEqual(['PG2']);
    expect(st.get().students.map((s) => s.nrp)).toEqual(['A1']);
  });

  it('typing in an inbound row is kept when a later patch completes', () => {
    const st = store({ students: [student('X1')], staff: [] });
    st.dispatch({ type: 'patchStudent', key: 'k-X1', patch: { home_institution: 'NUS' } });
    st.dispatch({ type: 'patchStudent', key: 'k-X1', patch: { home_country_code: 'SG' } });
    expect(st.get().students[0]).toMatchObject({ home_institution: 'NUS', home_country_code: 'SG' });
  });

  it('concurrent lookups returning the same id add it once', () => {
    const st = store({ students: [], staff: [] });
    st.dispatch({ type: 'addStaff', rows: [staff('PG1', { key: 'a' })] });
    st.dispatch({ type: 'addStaff', rows: [staff('PG1', { key: 'b' }), staff('PG2')] });
    expect(st.get().staff.map((s) => s.employee_id)).toEqual(['PG1', 'PG2']);
  });

  it('marks DB row errors on the latest rows and blocks the payload', () => {
    const st = store({ students: [student('A1', { section: 'internal' })], staff: [staff('PG1')] });
    st.dispatch({
      type: 'markDbErrors',
      message: 'NRP tidak ditemukan',
      errors: [{ section: 'internal', index: 0, id: 'A1', code: 'R16_NRP_NOT_FOUND' }],
    });
    expect(st.get().students[0]).toMatchObject({ blocking: true, status: 'not_found' });
    expect(st.get().staff[0]!.blocking).toBe(false);
    expect(toParticipantsPayload(st.get())).toBeNull();
  });
});
