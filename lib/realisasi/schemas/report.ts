// Period / report URL parameters shared by the dashboard, Laporan page and exports.
// Pure module (safe for client and server).
import type { DrilldownKpi, Period } from '@/lib/realisasi/types';

export interface PeriodParams {
  ay?: number;
  period: Period;
  unit?: number;
  snapshot?: string;
}

export type SearchParamsLike = URLSearchParams | Record<string, string | string[] | undefined>;

/** Revisi V.1 cut-offs, in display order. */
export const PERIODS: readonly Period[] = ['ganjil', 'genap', 'full', 'ytd'] as const;
export const DRILLDOWN_KPIS: readonly DrilldownKpi[] = ['1.1', '1.19.S1', '1.19.24', 'base'] as const;

export const REPORT_KEYS = [
  'ringkasan',
  'kpi',
  'kegiatan',
  'peserta',
  'awards',
  'realisasi-kerjasama',
  'arsip',
] as const;
export type ReportKey = (typeof REPORT_KEYS)[number];

export const CHART_KEYS = [
  'mobility_by_semester',
  'by_country',
  'by_unit',
  'by_sdg',
  'realization_by_unit',
  'top_partners',
] as const;
export type ChartKey = (typeof CHART_KEYS)[number];

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** First value of a search param key, trimmed; undefined when absent/empty. */
export function getParam(sp: SearchParamsLike, key: string): string | undefined {
  let raw: string | string[] | null | undefined;
  if (sp instanceof URLSearchParams) raw = sp.get(key);
  else raw = sp[key];
  const v = Array.isArray(raw) ? raw[0] : raw;
  if (v === null || v === undefined) return undefined;
  const t = v.trim();
  return t === '' ? undefined : t;
}

export function parsePositiveInt(v: string | undefined): number | undefined {
  if (v === undefined || !/^\d{1,9}$/.test(v)) return undefined;
  const n = Number(v);
  return n > 0 ? n : undefined;
}

export function isUuid(v: string | undefined): v is string {
  return v !== undefined && UUID_RE.test(v);
}

export function parsePeriodParams(sp: SearchParamsLike): PeriodParams {
  const periodRaw = getParam(sp, 'period');
  const period: Period = (PERIODS as readonly string[]).includes(periodRaw ?? '') ? (periodRaw as Period) : 'ytd';
  const out: PeriodParams = { period };
  const ay = parsePositiveInt(getParam(sp, 'ay'));
  if (ay !== undefined) out.ay = ay;
  const unit = parsePositiveInt(getParam(sp, 'unit'));
  if (unit !== undefined) out.unit = unit;
  const snapshot = getParam(sp, 'snapshot');
  if (isUuid(snapshot)) out.snapshot = snapshot.toLowerCase();
  return out;
}

export function periodParamsToSearchParams(p: Partial<PeriodParams>): URLSearchParams {
  const sp = new URLSearchParams();
  if (p.ay !== undefined) sp.set('ay', String(p.ay));
  if (p.period) sp.set('period', p.period);
  if (p.unit !== undefined) sp.set('unit', String(p.unit));
  if (p.snapshot) sp.set('snapshot', p.snapshot);
  return sp;
}

export function parseDrilldownKpi(v: string | undefined): DrilldownKpi | undefined {
  return (DRILLDOWN_KPIS as readonly string[]).includes(v ?? '') ? (v as DrilldownKpi) : undefined;
}

/** Bucket values accepted by kpi_drilldown (CONTRACTS §4.6). */
export const DRILLDOWN_BUCKETS: Record<DrilldownKpi, readonly string[]> = {
  '1.1': ['outbound', 'inbound'],
  '1.19.S1': ['international', 'domestic'],
  '1.19.24': ['numerator', 'denominator', 'not_realized', 'grace_excluded'],
  base: ['verified_activity'],
};

export function parseBucket(kpi: DrilldownKpi, v: string | undefined): string | undefined {
  return v !== undefined && DRILLDOWN_BUCKETS[kpi].includes(v) ? v : undefined;
}

export function parseReportKey(v: string | undefined): ReportKey | undefined {
  return (REPORT_KEYS as readonly string[]).includes(v ?? '') ? (v as ReportKey) : undefined;
}

export function parseChartKey(v: string | undefined): ChartKey | undefined {
  return (CHART_KEYS as readonly string[]).includes(v ?? '') ? (v as ChartKey) : undefined;
}

/** Realisasi-per-kerja-sama status filter → kpi_drilldown bucket. */
export const REALIZATION_STATUS = ['realized', 'not_realized', 'grace_excluded'] as const;
export type RealizationStatus = (typeof REALIZATION_STATUS)[number];
export function parseRealizationStatus(v: string | undefined): RealizationStatus | undefined {
  return (REALIZATION_STATUS as readonly string[]).includes(v ?? '') ? (v as RealizationStatus) : undefined;
}
export function realizationStatusToBucket(s: RealizationStatus | undefined): string | undefined {
  if (s === 'realized') return 'numerator';
  return s;
}

export const KPI_LABEL: Record<DrilldownKpi, string> = {
  '1.1': 'RENSTRA 1.1 — Mahasiswa Inbound & Outbound',
  '1.19.S1': 'RENSTRA 1.19.S1 — Kegiatan Internasional dengan Mitra',
  '1.19.24': 'RENSTRA 1.19.24 — Persentase MoU/MoA Terlaksana',
  base: 'Kegiatan Terverifikasi (basis)',
};

export const BUCKET_LABEL: Record<string, string> = {
  outbound: 'Outbound',
  inbound: 'Inbound',
  international: 'Internasional',
  domestic: 'Domestik',
  numerator: 'Terlaksana',
  denominator: 'Semua (penyebut)',
  realized: 'Terlaksana',
  not_realized: 'Belum terlaksana',
  grace_excluded: 'Masa tenggang',
  verified_activity: 'Terverifikasi',
};

export const CHART_LABEL: Record<ChartKey, string> = {
  mobility_by_semester: 'Inbound vs Outbound per Semester',
  by_country: 'Kegiatan per Negara',
  by_unit: 'Kegiatan per Unit',
  by_sdg: 'Cakupan SDG',
  realization_by_unit: 'Realisasi % per Unit',
  top_partners: 'Mitra Teraktif',
};
