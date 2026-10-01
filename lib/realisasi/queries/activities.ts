/**
 * Activity list / queue reads (WP-VERIFY, CONTRACTS §6.8). SERVER ONLY (takes a `withUser` tx).
 * `listActivities` is the single source for the Kegiatan list, both verification queues and the
 * `activities` / `sla` exports (AT-12: export rows === screen rows).
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

function or(tx: Tx, parts: postgres.Fragment[]): postgres.Fragment {
  if (parts.length === 0) return tx`false`;
  return parts.reduce((acc, p) => tx`${acc} or ${p}`);
}

/** `preset=mine`: what the current user should act on (CONTRACTS §6.8). */
function mineCondition(tx: Tx, user: SessionUser): postgres.Fragment {
  const partnershipPending = tx`(l.partnership_status = 'pending' and l.status not in ('draft', 'rejected'))`;
  const mobilityPending = tx`(l.mobility_status = 'pending' and l.status <> 'rejected')`;
  switch (user.role) {
    case 'submitter':
      return tx`(l.submitter_unit_id = ${user.unitId ?? -1}::int and l.status in ('draft', 'revision_requested'))`;
    case 'io_admin':
      return tx`(${partnershipPending} or ${mobilityPending})`;
    case 'io_staff': {
      const parts: postgres.Fragment[] = [];
      if (user.teams.includes('partnership')) parts.push(partnershipPending);
      if (user.teams.includes('mobility')) parts.push(mobilityPending);
      return tx`(${or(tx, parts)})`;
    }
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
  if (f.type_id !== undefined) c.push(tx`l.type_id = ${f.type_id}::int`);
  if (f.unit_id !== undefined) c.push(tx`${f.unit_id}::int = any(l.unit_ids)`);
  if (f.country) c.push(tx`${f.country}::text = any(l.country_codes)`);
  if (f.ay !== undefined) c.push(tx`l.academic_year_id = ${f.ay}::int`);
  if (f.semester !== undefined) c.push(tx`l.semester_id = ${f.semester}::int`);
  if (f.partnership) c.push(tx`l.partnership_status::text = ${f.partnership}::text`);
  if (f.mobility) c.push(tx`l.mobility_status::text = ${f.mobility}::text`);
  if (f.late) c.push(tx`l.is_late`);
  if (f.sla) c.push(tx`(l.partnership_sla_level = ${f.sla}::text or l.mobility_sla_level = ${f.sla}::text)`);
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

  if (f.queue === 'partnership') {
    c.push(tx`l.partnership_status = 'pending' and l.status not in ('draft', 'rejected')`);
  } else if (f.queue === 'mobility') {
    c.push(tx`l.mobility_status = 'pending' and l.status <> 'rejected'`);
  }

  return and(tx, c);
}

function buildOrder(tx: Tx, f: ActivityListFilters): postgres.Fragment {
  // Queues are always SLA-sorted (red first), regardless of `sort`.
  if (f.queue === 'partnership') return tx`l.partnership_sla_days desc nulls last, l.partnership_since asc nulls last, l.code`;
  if (f.queue === 'mobility') return tx`l.mobility_sla_days desc nulls last, l.mobility_since asc nulls last, l.code`;
  switch (f.sort) {
    case 'start_asc':
      return tx`l.start_date asc, l.code asc`;
    case 'code':
      return tx`l.code asc`;
    case 'sla':
      return tx`greatest(coalesce(l.partnership_sla_days, -1), coalesce(l.mobility_sla_days, -1)) desc, l.code`;
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
  types: FilterOption[];
  units: FilterOption[];
  countries: Array<{ code: string; name: string }>;
  academicYears: FilterOption[];
  semesters: Array<FilterOption & { ay_id: number; term: SemesterTerm }>;
}

/** Option lists for the per-column filters of the Kegiatan list. */
export async function getActivityFilterOptions(tx: Tx): Promise<ActivityFilterOptions> {
  const [types, units, countries, ays, semesters] = await Promise.all([
    tx<FilterOption[]>`select id, name as label from realisasi.activity_types order by sort_order, id`,
    tx<FilterOption[]>`select id, name as label from public.units order by name`,
    tx<Array<{ code: string; name: string }>>`select code, name from public.countries order by name`,
    tx<FilterOption[]>`select id, label from realisasi.academic_years order by start_date desc`,
    tx<Array<FilterOption & { ay_id: number; term: SemesterTerm }>>`
      select s.id, initcap(s.term::text) || ' ' || ay.label as label, s.academic_year_id as ay_id, s.term::text as term
        from realisasi.semesters s join realisasi.academic_years ay on ay.id = s.academic_year_id
       order by s.start_date desc`,
  ]);
  return {
    types: Array.from(types),
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
): Promise<Pick<ActivityListRow, 'id' | 'code' | 'name' | 'status' | 'submitter_unit_name' | 'event_group_id'> | null> {
  const [row] = await tx<Array<Pick<ActivityListRow, 'id' | 'code' | 'name' | 'status' | 'submitter_unit_name' | 'event_group_id'>>>`
    select id, code, name, status, submitter_unit_name, event_group_id
      from realisasi.v_activity_list where upper(code) = upper(${code}::text) limit 1`;
  return row ?? null;
}
