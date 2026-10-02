import { describe, expect, it } from 'vitest';
import { parseIdList, participantsSchema, splitIdTokens } from './participants';
import { activityDetailSchema, activityDetailSubmitSchema } from './activity';
import { classifyEmployees, classifyStudents } from '../queries/lookups';
import type { StudentRecord } from '../types';

describe('parseIdList', () => {
  it('splits lines/commas, trims, upper-cases and dedupes preserving order', () => {
    expect(parseIdList(' d31240187\nB11220031, d31240187 ;X01260012\t\n')).toEqual(['D31240187', 'B11220031', 'X01260012']);
  });
  it('keeps repeats in splitIdTokens', () => {
    expect(splitIdTokens('a1\na1')).toEqual(['A1', 'A1']);
  });
});

describe('participantsSchema', () => {
  it('rejects duplicate NRP (R-22)', () => {
    const r = participantsSchema.safeParse({
      students: [{ section: 'internal', nrp: 'D31240187' }, { section: 'inbound', nrp: 'D31240187' }],
      staff: [],
    });
    expect(r.success).toBe(false);
  });
});

const student = (nrp: string, category: StudentRecord['category'], status: StudentRecord['status'] = 'active'): StudentRecord => ({
  nrp, full_name: nrp, faculty_code: 'D', faculty_name: 'F', prodi_name: 'P', category, home_institution: null,
  home_country_code: null, intake_year: 2024, status,
});

describe('classifyStudents', () => {
  it('flags not_found, section mismatch, warnings and duplicates', () => {
    const res = classifyStudents(
      ['Z99999999', 'X01260012', 'B11200005', 'D31240187', 'D31240187'],
      'internal',
      [student('X01260012', 'inbound_exchange'), student('B11200005', 'regular', 'graduated'), student('D31240187', 'regular')],
    );
    expect(res.map((r) => [r.status, r.blocking])).toEqual([
      ['not_found', true],
      ['is_inbound', true],
      ['graduated', false],
      ['ok', false],
      ['duplicate', true],
    ]);
  });
  it('flags regular NRP in inbound section', () => {
    expect(classifyStudents(['D31240187'], 'inbound', [student('D31240187', 'regular')])[0]?.status).toBe('not_inbound');
  });
  it('classifies employees', () => {
    expect(classifyEmployees(['PG1', 'PG2'], [{ employee_id: 'PG2', full_name: 'x', unit_name: 'u', position: null, status: 'inactive' }]).map((r) => r.status)).toEqual(['not_found', 'inactive']);
  });
});

describe('activity schemas', () => {
  const base = {
    name: 'Summer', agenda_id: 23, direction: 'outbound' as const, start_date: '2026-08-03', end_date: '2026-08-21',
    mode: 'offline' as const, venue: null, country_code: null, sks_recognized: null, description: 'x',
    submitter_unit_id: 10, co_unit_ids: [], document_id: null, sdg_ids: [], external_persons: [],
  };
  it('accepts a minimal draft', () => expect(activityDetailSchema.safeParse(base).success).toBe(true));
  it('rejects end before start', () => expect(activityDetailSchema.safeParse({ ...base, end_date: '2026-08-01' }).success).toBe(false));
  it('requires a direction (Inbound/Outbound)', () =>
    expect(activityDetailSchema.safeParse({ ...base, direction: undefined }).success).toBe(false));
  it('allows exactly one kerja sama', () =>
    expect(activityDetailSchema.safeParse({ ...base, document_id: [101, 102] }).success).toBe(false));
  it('submit schema requires venue/country and the kerja sama', () => {
    const r = activityDetailSubmitSchema.safeParse(base);
    expect(r.success).toBe(false);
    if (!r.success) expect(r.error.issues.map((i) => i.path[0]).sort()).toEqual(['country_code', 'document_id', 'venue']);
  });
});
