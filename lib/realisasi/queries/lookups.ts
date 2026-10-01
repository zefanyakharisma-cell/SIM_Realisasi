/**
 * Form options + registry lookups (WP-SUBMIT, CONTRACTS §3.1 / §6.8 / §8.1). SERVER ONLY.
 * Result row types are exported for client components (`import type` only).
 */
import type { Tx } from '@/lib/db';
import type { Direction, DocumentOption, EmployeeRecord, StudentRecord } from '@/lib/realisasi/types';

export interface ActivityTypeOption {
  id: number;
  name: string;
  direction: Direction;
  counts_as_mobility: boolean;
  counts_for_s1: boolean;
  requires_mobility_review: boolean;
  is_active: boolean;
  sort_order: number | null;
}
export interface UnitOption {
  id: number;
  name: string;
  kind: string;
  parent_id: number | null;
}
export interface CountryOption {
  code: string;
  name: string;
}
export interface SdgOption {
  id: number;
  name: string;
}
export interface SemesterOption {
  id: number;
  term: 'ganjil' | 'genap';
  label: string;
  start_date: string;
  end_date: string;
  cutoff_date: string;
}
export interface AcademicYearOption {
  id: number;
  label: string;
  start_date: string;
  end_date: string;
  semesters: SemesterOption[];
}
export interface FormOptions {
  activityTypes: ActivityTypeOption[];
  units: UnitOption[];
  countries: CountryOption[];
  sdgs: SdgOption[];
  academicYears: AcademicYearOption[];
}

export async function getFormOptions(tx: Tx): Promise<FormOptions> {
  const activityTypes = await tx<ActivityTypeOption[]>`
    select id, name, direction::text as direction, counts_as_mobility, counts_for_s1,
           requires_mobility_review, is_active, sort_order
      from realisasi.activity_types
     order by sort_order nulls last, id`;
  const units = await tx<UnitOption[]>`select id, name, kind, parent_id from public.units order by id`;
  const countries = await tx<CountryOption[]>`select code, name from public.countries order by name`;
  const sdgs = await tx<SdgOption[]>`select id::int as id, name from realisasi.sdgs order by id`;
  const years = await tx<Omit<AcademicYearOption, 'semesters'>[]>`
    select id, label, start_date, end_date from realisasi.academic_years order by start_date`;
  const semesters = await tx<(SemesterOption & { academic_year_id: number })[]>`
    select s.id, s.academic_year_id, s.term::text as term,
           initcap(s.term::text) || ' ' || y.label as label,
           s.start_date, s.end_date, s.cutoff_date
      from realisasi.semesters s join realisasi.academic_years y on y.id = s.academic_year_id
     order by s.start_date`;
  const academicYears = years.map((y) => ({
    ...y,
    semesters: semesters
      .filter((s) => s.academic_year_id === y.id)
      .map(({ academic_year_id: _ay, ...s }) => s),
  }));
  return {
    activityTypes: [...activityTypes],
    units: [...units],
    countries: [...countries],
    sdgs: [...sdgs],
    academicYears,
  };
}

export async function getValidDocuments(tx: Tx, start: string, end: string, unitId: number | null): Promise<DocumentOption[]> {
  const rows = await tx<DocumentOption[]>`
    select * from realisasi.documents_valid_between(${start}::date, ${end}::date, ${unitId}::int)`;
  return [...rows];
}

// ---------------------------------------------------------------------------------------------
// Registry lookups (R-16..R-19, R-22)

export type StudentLookupStatus = 'ok' | 'not_found' | 'graduated' | 'inactive' | 'not_inbound' | 'is_inbound' | 'duplicate';
export interface StudentLookupResult {
  nrp: string;
  status: StudentLookupStatus;
  blocking: boolean;
  student: StudentRecord | null;
}
export type EmployeeLookupStatus = 'ok' | 'not_found' | 'inactive' | 'duplicate';
export interface EmployeeLookupResult {
  employee_id: string;
  status: EmployeeLookupStatus;
  blocking: boolean;
  employee: EmployeeRecord | null;
}

const BLOCKING_STUDENT: ReadonlySet<StudentLookupStatus> = new Set(['not_found', 'not_inbound', 'is_inbound', 'duplicate']);

/** Pure classification (exported for tests). Repeats after the first occurrence are `duplicate`. */
export function classifyStudents(
  nrps: string[],
  section: 'internal' | 'inbound',
  found: StudentRecord[],
): StudentLookupResult[] {
  const byNrp = new Map(found.map((s) => [s.nrp, s]));
  const seen = new Set<string>();
  return nrps.map((nrp) => {
    const student = byNrp.get(nrp) ?? null;
    let status: StudentLookupStatus;
    if (seen.has(nrp)) status = 'duplicate';
    else if (!student) status = 'not_found';
    else if (section === 'inbound' && student.category !== 'inbound_exchange') status = 'not_inbound';
    else if (section === 'internal' && student.category === 'inbound_exchange') status = 'is_inbound';
    else if (student.status === 'graduated') status = 'graduated';
    else if (student.status === 'inactive') status = 'inactive';
    else status = 'ok';
    seen.add(nrp);
    return { nrp, status, blocking: BLOCKING_STUDENT.has(status), student };
  });
}

export function classifyEmployees(ids: string[], found: EmployeeRecord[]): EmployeeLookupResult[] {
  const byId = new Map(found.map((e) => [e.employee_id, e]));
  const seen = new Set<string>();
  return ids.map((id) => {
    const employee = byId.get(id) ?? null;
    let status: EmployeeLookupStatus;
    if (seen.has(id)) status = 'duplicate';
    else if (!employee) status = 'not_found';
    else if (employee.status === 'inactive') status = 'inactive';
    else status = 'ok';
    seen.add(id);
    return { employee_id: id, status, blocking: status === 'not_found' || status === 'duplicate', employee };
  });
}

export async function lookupStudents(tx: Tx, nrps: string[], section: 'internal' | 'inbound'): Promise<StudentLookupResult[]> {
  const unique = [...new Set(nrps)];
  const found = await tx<StudentRecord[]>`select * from realisasi.lookup_students(${unique}::text[])`;
  return classifyStudents(nrps, section, [...found]);
}

export async function lookupEmployees(tx: Tx, ids: string[]): Promise<EmployeeLookupResult[]> {
  const unique = [...new Set(ids)];
  const found = await tx<EmployeeRecord[]>`select * from realisasi.lookup_employees(${unique}::text[])`;
  return classifyEmployees(ids, [...found]);
}
