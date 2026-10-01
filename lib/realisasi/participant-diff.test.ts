import { describe, expect, it } from 'vitest';
import type { ParticipantStaffRow, ParticipantStudentRow, ParticipantVersion } from '@/lib/realisasi/types';
import { diffParticipantVersions, summarizeDiff } from './participant-diff';

function student(nrp: string, over: Partial<ParticipantStudentRow> = {}): ParticipantStudentRow {
  return {
    id: Math.floor(Math.random() * 1e6),
    section: 'internal',
    nrp,
    full_name: `Mahasiswa ${nrp}`,
    faculty_name: 'FTI',
    prodi_name: 'Informatika',
    home_institution: null,
    home_student_number: null,
    home_country_code: null,
    transcript_path: null,
    transcript_href: null,
    row_note: null,
    registry_status: 'active',
    ...over,
  } as ParticipantStudentRow;
}

function staff(id: string, over: Partial<ParticipantStaffRow> = {}): ParticipantStaffRow {
  return { id: 1, employee_id: id, full_name: `Pegawai ${id}`, unit_name: 'IO', row_note: null, registry_status: 'active', ...over } as ParticipantStaffRow;
}

function version(n: number, students: ParticipantStudentRow[], staffRows: ParticipantStaffRow[] = []): ParticipantVersion {
  return {
    id: `v${n}`,
    activity_id: 'a',
    version: n,
    status: 'pending',
    submitted_at: null,
    submitted_by_name: null,
    reviewed_at: null,
    reviewed_by_name: null,
    review_note: null,
    students,
    staff: staffRows,
  } as ParticipantVersion;
}

describe('diffParticipantVersions', () => {
  it('marks everything same when there is no previous version', () => {
    const d = diffParticipantVersions(null, version(1, [student('B11220001')], [staff('PG1')]));
    expect(d.students.map((e) => e.change)).toEqual(['same']);
    expect(d.staff.map((e) => e.change)).toEqual(['same']);
  });

  it('detects added, removed and changed rows by NRP / employee id', () => {
    const prev = version(1, [student('A1'), student('A2'), student('A3', { home_institution: 'X' })], [staff('PG1'), staff('PG2')]);
    const next = version(
      2,
      [student('A1'), student('A3', { home_institution: 'Y', row_note: 'abaikan' }), student('A4')],
      [staff('PG1', { unit_name: 'FTI' }), staff('PG3')],
    );
    const d = diffParticipantVersions(prev, next);
    expect(d.students.map((e) => [e.key, e.change])).toEqual([
      ['A1', 'same'],
      ['A3', 'changed'],
      ['A4', 'added'],
      ['A2', 'removed'],
    ]);
    expect(d.students[1]!.changedFields).toEqual(['home_institution']);
    expect(d.staff.map((e) => [e.key, e.change])).toEqual([
      ['PG1', 'changed'],
      ['PG3', 'added'],
      ['PG2', 'removed'],
    ]);
    expect(summarizeDiff(d)).toEqual({ added: 2, removed: 2, changed: 2 });
  });

  it('treats empty string and null as equal', () => {
    const d = diffParticipantVersions(
      version(1, [student('A1', { prodi_name: '' })]),
      version(2, [student('A1', { prodi_name: null })]),
    );
    expect(d.students[0]!.change).toBe('same');
  });
});
