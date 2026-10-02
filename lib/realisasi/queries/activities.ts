/**
 * Activity list / queue reads (WP-VERIFY, CONTRACTS §6.8). SERVER ONLY (takes a `withUser` tx).
 * `listActivities` is the single source for the Kegiatan list, the Mobility queue and the
 * `activities` export (AT-12: export rows === screen rows).
 */
import type postgres from 'postgres';
import type { Tx } from '@/lib/db';
import type { SessionUser } from '@/lib/session';
import type { ActivityListRow, SemesterTerm } from '@/lib/realisasi/types';
import type { ActivityListFilters } from '@/lib/realisasi/schemas/filters';

export const ACTIVITY_LIST_LIMIT = 2000;

function and(tx: Tx, parts: postgres.Fragment[]): postgres.Fragment {
  if (parts.length === 0) return tx`true`;
  return parts.reduce((acc, p) => tx`${acc} and ${p}`);
}

/** `preset=mine`: what the current user should act on (CONTRACTS §6.8). */
function mineCondition(tx: Tx, user: SessionUser): postgres.Fragment {
  const mobilityPending = tx`(l.mobility_status = 'pending' and l.status <> 'draft')`;
  switch (user.role) {
    case 'submitter':
      return tx`(l.submitter_unit_id = ${user.unitId ?? -1}::int and l.status in ('draft', 'revision_requested'))`;
    case 'io_admin':
      return mobilityPending;
    case 'io_staff':
      return user.teams.includes('mobility') ? mobilityPending : tx`false`;
    default:
      return tx`false`;
  }
}

function buildWhere(tx: Tx, user: SessionUser, f: ActivityListFilters): postgres.Fragment {
  const c: postgres.Fragment[] = [];

  if (f.q) {
    const like = `%${f.q.replace(/[\\%_]/g, (m) => `\\${m}`)}%`;
    c.push(tx`(l.name ilike ${like} or l.code ilike ${like}
               or array_to_string(l.partner_names, ' ') ilike ${like}
               or array_to_string(l.document_numbers, ' ') ilike ${like})`);
  }
  if (f.status?.length) c.push(tx`l.status::text = any(${tx.array(f.status)}::text[])`);
  if (f.agenda_id !== undefined) c.push(tx`l.agenda_id = ${f.agenda_id}::int`);
  if (f.direction) c.push(tx`l.direction::text = ${f.direction}::text`);
  if (f.unit_id !== undefined) c.push(tx`${f.unit_id}::int = any(l.unit_ids)`);
  if (f.country) c.push(tx`${f.country}::text = any(l.country_codes)`);
  if (f.ay !== undefined) c.push(tx`l.academic_year_id = ${f.ay}::int`);
  if (f.semester !== undefined) c.push(tx`l.semester_id = ${f.semester}::int`);
  if (f.mobility) c.push(tx`l.mobility_status::text = ${f.mobility}::text`);
  if (f.late) c.push(tx`l.is_late`);
  if (f.from) c.push(tx`l.start_date >= ${f.from}::date`);
  if (f.to) c.push(tx`l.start_date <= ${f.to}::date`);

  switch (f.preset) {
    case 'mine':
      c.push(mineCondition(tx, user));
      break;
    case 'late':
      c.push(tx`(l.is_late or (l.status = 'draft' and l.reporting_deadline < realisasi.today()))`);
      break;
    case 'this_semester':
      c.push(tx`l.semester_id = (select s.id from realisasi.semesters s
                                  where realisasi.today() between s.start_date and s.end_date
                                  order by s.start_date desc limit 1)`);
      break;
    default:
      break;
  }

  if (f.queue === 'mobility') c.push(tx`l.mobility_status = 'pending' and l.status <> 'draft'`);

  return and(tx, c);
}

function buildOrder(tx: Tx, f: ActivityListFilters): postgres.Fragment {
  // The queue always lists the longest-waiting submissions first (no SLA since Revisi V.1).
  if (f.queue === 'mobility') return tx`l.mobility_since asc nulls last, l.code`;
  switch (f.sort) {
    case 'start_asc':
      return tx`l.start_date asc, l.code asc`;
    case 'code':
      return tx`l.code asc`;
    case 'waiting':
      return tx`(l.mobility_status = 'pending') desc, l.mobility_since asc nulls last, l.code`;
    case 'start_desc':
    default:
      return tx`l.start_date desc, l.code desc`;
  }
}

/**
 * Rows of `realisasi.v_activity_list` visible to the caller (RLS via security_invoker view),
 * narrowed by `f`. No pagination; hard limit 2000.
 */
export async function listActivities(tx: Tx, user: SessionUser, f: ActivityListFilters): Promise<ActivityListRow[]> {
  const rows = await tx<ActivityListRow[]>`
    select l.*
      from realisasi.v_activity_list l
     where ${buildWhere(tx, user, f)}
     order by ${buildOrder(tx, f)}
     limit ${ACTIVITY_LIST_LIMIT}`;
  return Array.from(rows);
}

export interface FilterOption {
  id: number;
  label: string;
}

export interface ActivityFilterOptions {
  agendas: FilterOption[];
  units: FilterOption[];
  countries: Array<{ code: string; name: string }>;
  academicYears: FilterOption[];
  semesters: Array<FilterOption & { ay_id: number; term: SemesterTerm }>;
}

/** Option lists for the per-column filters of the Kegiatan list. */
export async function getActivityFilterOptions(tx: Tx): Promise<ActivityFilterOptions> {
  const [agendas, units, countries, ays, semesters] = await Promise.all([
    tx<FilterOption[]>`select id, name as label from kerjasama.agendas order by name`,
    tx<FilterOption[]>`select id, name as label from kerjasama.units where is_academic order by name`,
    tx<Array<{ code: string; name: string }>>`select code, name from kerjasama.countries order by name`,
    tx<FilterOption[]>`select id, label from realisasi.academic_years order by start_date desc`,
    tx<Array<FilterOption & { ay_id: number; term: SemesterTerm }>>`
      select s.id, initcap(s.term::text) || ' ' || ay.label as label, s.academic_year_id as ay_id, s.term::text as term
        from realisasi.semesters s join realisasi.academic_years ay on ay.id = s.academic_year_id
       order by s.start_date desc`,
  ]);
  return {
    agendas: Array.from(agendas),
    units: Array.from(units),
    countries: Array.from(countries),
    academicYears: Array.from(ays),
    semesters: Array.from(semesters),
  };
}

/** Resolves an activity code (e.g. `RL-2026-0013`) to its id if visible to the caller. */
export async function findActivityByCode(
  tx: Tx,
  code: string,
): Promise<Pick<ActivityListRow, 'id' | 'code' | 'name' | 'status' | 'submitter_unit_name'> | null> {
  const [row] = await tx<Array<Pick<ActivityListRow, 'id' | 'code' | 'name' | 'status' | 'submitter_unit_name'>>>`
    select id, code, name, status, submitter_unit_name
      from realisasi.v_activity_list where upper(code) = upper(${code}::text) limit 1`;
  return row ?? null;
}
