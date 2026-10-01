import { z } from 'zod';
import type { ActivityStatus, DateString, TrackStatus } from '@/lib/realisasi/types';
import {
  ACTIVITY_STATUS_LABEL,
  TRACK_STATUS_LABEL,
} from '@/lib/realisasi/status';

/**
 * Activity list filters (CONTRACTS §6.8). Shared by the Kegiatan list, the
 * verification queues and WP-REPORTS' `activities` / `sla` / `participants`
 * exports, so the same URL produces the same rows on screen and in Excel (AT-12).
 *
 * URL keys = field names; booleans '1'; arrays comma-separated.
 */
export interface ActivityListFilters {
  q?: string;
  status?: ActivityStatus[];
  type_id?: number;
  unit_id?: number;
  country?: string;
  ay?: number;
  semester?: number;
  partnership?: TrackStatus;
  mobility?: TrackStatus;
  late?: boolean;
  sla?: 'yellow' | 'red';
  from?: DateString;
  to?: DateString;
  preset?: 'mine' | 'late' | 'this_semester';
  queue?: 'partnership' | 'mobility';
  sort?: 'start_desc' | 'start_asc' | 'code' | 'sla';
}

export const ACTIVITY_STATUSES = [
  'draft',
  'in_verification',
  'revision_requested',
  'verified',
  'rejected',
] as const satisfies readonly ActivityStatus[];

export const TRACK_STATUSES = [
  'not_required',
  'pending',
  'revision_requested',
  'approved',
  'rejected',
] as const satisfies readonly TrackStatus[];

export const PRESETS = ['mine', 'late', 'this_semester'] as const;
export const SORTS = ['start_desc', 'start_asc', 'code', 'sla'] as const;

export const PRESET_LABEL: Record<NonNullable<ActivityListFilters['preset']>, string> = {
  mine: 'Perlu tindakan saya',
  late: 'Terlambat',
  this_semester: 'Semester ini',
};

export const SORT_LABEL: Record<NonNullable<ActivityListFilters['sort']>, string> = {
  start_desc: 'Tanggal mulai (terbaru)',
  start_asc: 'Tanggal mulai (terlama)',
  code: 'Kode',
  sla: 'SLA terlama',
};

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function isValidDate(s: string): boolean {
  if (!DATE_RE.test(s)) return false;
  const d = new Date(`${s}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
}

const positiveInt = z.coerce.number().int().positive();
const dateString = z.string().refine(isValidDate, 'Tanggal tidak valid');

export const activityListFiltersSchema: z.ZodType<ActivityListFilters> = z.object({
  q: z.string().trim().min(1).max(200).optional(),
  status: z.array(z.enum(ACTIVITY_STATUSES)).min(1).optional(),
  type_id: positiveInt.optional(),
  unit_id: positiveInt.optional(),
  country: z
    .string()
    .trim()
    .regex(/^[A-Za-z]{2}$/)
    .transform((s) => s.toUpperCase())
    .optional(),
  ay: positiveInt.optional(),
  semester: positiveInt.optional(),
  partnership: z.enum(TRACK_STATUSES).optional(),
  mobility: z.enum(TRACK_STATUSES).optional(),
  late: z.boolean().optional(),
  sla: z.enum(['yellow', 'red']).optional(),
  from: dateString.optional(),
  to: dateString.optional(),
  preset: z.enum(PRESETS).optional(),
  queue: z.enum(['partnership', 'mobility']).optional(),
  sort: z.enum(SORTS).optional(),
}) as z.ZodType<ActivityListFilters>;

type RawParams = URLSearchParams | Record<string, string | string[] | undefined>;

/** Returns the first value of a param, regardless of the container type. */
export function firstParam(sp: RawParams, key: string): string | undefined {
  if (sp instanceof URLSearchParams) {
    const v = sp.get(key);
    return v === null ? undefined : v;
  }
  const v = sp[key];
  if (Array.isArray(v)) return v[0];
  return v;
}

function allParams(sp: RawParams, key: string): string[] {
  if (sp instanceof URLSearchParams) return sp.getAll(key);
  const v = sp[key];
  if (v === undefined) return [];
  return Array.isArray(v) ? v : [v];
}

/**
 * Lenient parser: every key is validated on its own and invalid values are
 * dropped (never throws), so a hand-edited URL degrades to fewer filters.
 */
export function parseActivityFilters(sp: RawParams): ActivityListFilters {
  const out: ActivityListFilters = {};
  const shape = (activityListFiltersSchema as unknown as z.ZodObject<z.ZodRawShape>).shape;

  const take = <K extends keyof ActivityListFilters>(key: K, raw: unknown) => {
    const field = shape[key as string];
    if (!field || raw === undefined || raw === '') return;
    const r = field.safeParse(raw);
    if (r.success && r.data !== undefined) out[key] = r.data as ActivityListFilters[K];
  };

  take('q', firstParam(sp, 'q'));
  const statuses = allParams(sp, 'status')
    .flatMap((s) => s.split(','))
    .map((s) => s.trim())
    .filter((s): s is ActivityStatus => (ACTIVITY_STATUSES as readonly string[]).includes(s));
  if (statuses.length) out.status = Array.from(new Set(statuses));
  take('type_id', firstParam(sp, 'type_id'));
  take('unit_id', firstParam(sp, 'unit_id'));
  take('country', firstParam(sp, 'country'));
  take('ay', firstParam(sp, 'ay'));
  take('semester', firstParam(sp, 'semester'));
  take('partnership', firstParam(sp, 'partnership'));
  take('mobility', firstParam(sp, 'mobility'));
  const late = firstParam(sp, 'late');
  if (late === '1' || late === 'true') out.late = true;
  take('sla', firstParam(sp, 'sla'));
  take('from', firstParam(sp, 'from'));
  take('to', firstParam(sp, 'to'));
  take('preset', firstParam(sp, 'preset'));
  take('queue', firstParam(sp, 'queue'));
  take('sort', firstParam(sp, 'sort'));
  return out;
}

/** Inverse of `parseActivityFilters` (status as comma list, booleans '1'). Key order is stable. */
export function activityFiltersToSearchParams(f: ActivityListFilters): URLSearchParams {
  const sp = new URLSearchParams();
  if (f.q) sp.set('q', f.q);
  if (f.status?.length) sp.set('status', f.status.join(','));
  if (f.type_id !== undefined) sp.set('type_id', String(f.type_id));
  if (f.unit_id !== undefined) sp.set('unit_id', String(f.unit_id));
  if (f.country) sp.set('country', f.country);
  if (f.ay !== undefined) sp.set('ay', String(f.ay));
  if (f.semester !== undefined) sp.set('semester', String(f.semester));
  if (f.partnership) sp.set('partnership', f.partnership);
  if (f.mobility) sp.set('mobility', f.mobility);
  if (f.late) sp.set('late', '1');
  if (f.sla) sp.set('sla', f.sla);
  if (f.from) sp.set('from', f.from);
  if (f.to) sp.set('to', f.to);
  if (f.preset) sp.set('preset', f.preset);
  if (f.queue) sp.set('queue', f.queue);
  if (f.sort) sp.set('sort', f.sort);
  return sp;
}

/** True when any filter that narrows rows is set (sort / queue excluded). */
export function hasActiveFilters(f: ActivityListFilters): boolean {
  const { sort: _sort, queue: _queue, ...rest } = f;
  return Object.values(rest).some((v) => v !== undefined && !(Array.isArray(v) && v.length === 0));
}

const QUEUE_LABEL = { partnership: 'Antrean Verifikasi Kemitraan', mobility: 'Antrean Verifikasi Mobilitas' } as const;
const SLA_LEVEL_LABEL = { yellow: 'Kuning', red: 'Merah' } as const;

/**
 * Human-readable filter list for the Excel Info sheet ("Filter: <label>" → value).
 * Extra optional resolvers (`ayLabel`, `semesterLabel`, `countryName`) are additive to the contract.
 */
export function describeActivityFilters(
  f: ActivityListFilters,
  opts: {
    typeName?: (id: number) => string;
    unitName?: (id: number) => string;
    ayLabel?: (id: number) => string;
    semesterLabel?: (id: number) => string;
    countryName?: (code: string) => string;
  } = {},
): Array<[label: string, value: string]> {
  const rows: Array<[string, string]> = [];
  if (f.queue) rows.push(['Antrean', QUEUE_LABEL[f.queue]]);
  if (f.preset) rows.push(['Filter cepat', PRESET_LABEL[f.preset]]);
  if (f.q) rows.push(['Pencarian', f.q]);
  if (f.status?.length) rows.push(['Status', f.status.map((s) => ACTIVITY_STATUS_LABEL[s] ?? s).join(', ')]);
  if (f.type_id !== undefined) rows.push(['Jenis Kegiatan', opts.typeName?.(f.type_id) ?? `#${f.type_id}`]);
  if (f.unit_id !== undefined) rows.push(['Unit', opts.unitName?.(f.unit_id) ?? `#${f.unit_id}`]);
  if (f.country) rows.push(['Negara Mitra', opts.countryName ? `${opts.countryName(f.country)} (${f.country})` : f.country]);
  if (f.ay !== undefined) rows.push(['Tahun Akademik', opts.ayLabel?.(f.ay) ?? `#${f.ay}`]);
  if (f.semester !== undefined) rows.push(['Semester', opts.semesterLabel?.(f.semester) ?? `#${f.semester}`]);
  if (f.partnership) rows.push(['Status Kemitraan', TRACK_STATUS_LABEL[f.partnership] ?? f.partnership]);
  if (f.mobility) rows.push(['Status Mobilitas', TRACK_STATUS_LABEL[f.mobility] ?? f.mobility]);
  if (f.late) rows.push(['Terlambat', 'Ya']);
  if (f.sla) rows.push(['Level SLA', SLA_LEVEL_LABEL[f.sla]]);
  if (f.from) rows.push(['Tanggal mulai dari', f.from]);
  if (f.to) rows.push(['Tanggal mulai sampai', f.to]);
  if (f.sort) rows.push(['Urutan', SORT_LABEL[f.sort]]);
  return rows;
}
