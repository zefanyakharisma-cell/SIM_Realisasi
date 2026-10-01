/**
 * Known Activities register reads (WP-VERIFY, CONTRACTS §6.8). SERVER ONLY.
 * Rows come from `realisasi.v_known_activities` (RLS: IO only).
 */
import type postgres from 'postgres';
import type { Tx } from '@/lib/db';
import type { KnownActivityRow, KnownSuggestion } from '@/lib/realisasi/types';
import type { KnownFilters } from '@/lib/realisasi/schemas/known';

export async function listKnownActivities(tx: Tx, f: KnownFilters): Promise<KnownActivityRow[]> {
  const c: postgres.Fragment[] = [];
  if (f.q) {
    const like = `%${f.q.replace(/[\\%_]/g, (m) => `\\${m}`)}%`;
    c.push(tx`(k.title ilike ${like} or coalesce(k.partner_name, '') ilike ${like}
               or coalesce(k.source_reference, '') ilike ${like})`);
  }
  if (f.status) c.push(tx`k.status::text = ${f.status}::text`);
  if (f.unit_id !== undefined) c.push(tx`k.unit_id = ${f.unit_id}::int`);
  if (f.intl !== undefined) c.push(tx`k.is_international = ${f.intl}::boolean`);
  if (f.from) c.push(tx`k.activity_date >= ${f.from}::date`);
  if (f.to) c.push(tx`k.activity_date <= ${f.to}::date`);
  const where = c.length ? c.reduce((acc, p) => tx`${acc} and ${p}`) : tx`true`;
  const rows = await tx<KnownActivityRow[]>`
    select k.* from realisasi.v_known_activities k
     where ${where}
     order by k.activity_date desc, k.id desc`;
  return Array.from(rows);
}

/** `known_match_suggestions()` for one entry (IO only). */
export async function getKnownSuggestions(tx: Tx, id: number): Promise<KnownSuggestion[]> {
  const [row] = await tx<Array<{ r: KnownSuggestion[] | null }>>`
    select realisasi.known_match_suggestions(${id}::bigint) as r`;
  return row?.r ?? [];
}

/** Suggestions for several unmatched entries, keyed by known id. */
export async function getKnownSuggestionsFor(tx: Tx, ids: number[]): Promise<Record<number, KnownSuggestion[]>> {
  const out: Record<number, KnownSuggestion[]> = {};
  for (const id of ids) out[id] = await getKnownSuggestions(tx, id);
  return out;
}

/** Units for the register's unit select / form. */
export async function listUnitOptions(tx: Tx): Promise<Array<{ id: number; label: string }>> {
  return Array.from(await tx<Array<{ id: number; label: string }>>`select id, name as label from kerjasama.units order by name`);
}

export async function listCountryOptions(tx: Tx): Promise<Array<{ code: string; name: string }>> {
  return Array.from(await tx<Array<{ code: string; name: string }>>`select code, name from kerjasama.countries order by name`);
}

/** Current `nudge_resend_days` setting (R-54), for the "dapat dikirim ulang" hint. */
export async function getNudgeResendDays(tx: Tx): Promise<number> {
  const [row] = await tx<Array<{ v: number | null }>>`
    select (value #>> '{}')::int as v from realisasi.settings where key = 'nudge_resend_days'`;
  return row?.v ?? 14;
}
