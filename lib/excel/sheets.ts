// Column definitions shared by the export kinds (CONTRACTS §8.2 column lists, verbatim headers).
import { formatDiffLines } from '@/lib/realisasi/diff-format';
import type ExcelJS from 'exceljs';
import type {
  ActivityKpiRow,
  ActivityListRow,
  ChainKpiRow,
  DrilldownKpi,
  DrilldownResult,
  KnownKpiRow,
  KpiValues,
  LateAdditionRow,
  PeriodInfo,
  PostFreezeChangeRow,
  SnapshotListRow,
} from '@/lib/realisasi/types';
import {
  ACTIVITY_STATUS_LABEL,
  DIRECTION_LABEL,
  KNOWN_SOURCE_LABEL,
  LOG_ACTION_LABEL,
  MODE_LABEL,
  SLA_LEVEL_LABEL,
  SNAPSHOT_KIND_LABEL,
  TRACK_LABEL,
  TRACK_STATUS_LABEL,
} from '@/lib/realisasi/status';
import { formatDate, formatDateTime } from '@/lib/realisasi/format';
import { addTableSheet, type Column } from '@/lib/excel/workbook';

// ---------- small helpers ----------
export function label<K extends string>(map: Partial<Record<K, string>> | undefined, key: K | null | undefined): string | null {
  if (key === null || key === undefined) return null;
  return map?.[key] ?? String(key);
}
export const joinList = (xs: ReadonlyArray<string | null | undefined> | null | undefined): string =>
  (xs ?? []).filter((x): x is string => typeof x === 'string' && x !== '').join(', ');
export const yesNo = (b: boolean | null | undefined): string => (b ? 'Ya' : 'Tidak');

export function dataAsOf(period: PeriodInfo): string {
  if (period.frozen) {
    return `Snapshot ${period.label} · dibekukan ${formatDateTime(period.frozen_at)} · id ${period.snapshot_id ?? '–'}`;
  }
  return `Live s.d. ${formatDate(period.today)}`;
}

export function snapshotAsOf(s: SnapshotListRow): string {
  return `Snapshot ${s.label} · dibekukan ${formatDateTime(s.frozen_at)} · id ${s.id}`;
}

export function isActivityRow(r: unknown): r is ActivityKpiRow {
  return (r as { row_type?: string }).row_type === 'activity';
}
export function isChainRow(r: unknown): r is ChainKpiRow {
  return (r as { row_type?: string }).row_type === 'chain';
}
export function isKnownRow(r: unknown): r is KnownKpiRow {
  return (r as { row_type?: string }).row_type === 'known';
}

export const CHAIN_STATUS_LABEL: Record<string, string> = {
  realized: 'Terlaksana',
  not_realized: 'Belum terlaksana',
  grace_excluded: 'Masa tenggang',
};

// ---------- KPI sheets ----------
export const KPI_11_COLUMNS: Column<ActivityKpiRow>[] = [
  { header: 'Kode', key: 'code', value: (r) => r.code },
  { header: 'Nama', key: 'name', value: (r) => r.name },
  { header: 'Jenis', key: 'type', value: (r) => r.type_name },
  { header: 'Arah', key: 'dir', value: (r) => label(DIRECTION_LABEL, (r.bucket === 'inbound' || r.bucket === 'outbound' ? r.bucket : r.direction) as never) },
  { header: 'Unit', key: 'unit', value: (r) => joinList(r.unit_names) },
  { header: 'Mitra', key: 'partner', value: (r) => joinList(r.partner_names) },
  { header: 'Negara', key: 'country', value: (r) => joinList(r.country_codes) },
  { header: 'Tanggal Mulai', key: 'start', value: (r) => r.start_date, format: 'date' },
  { header: 'Semester', key: 'sem', value: (r) => r.semester_label },
  { header: 'Grup Kegiatan', key: 'group', value: (r) => (r.linked_count > 0 ? `${r.event_group_id} (+${r.linked_count} tertaut)` : r.event_group_id) },
  { header: 'Jumlah Mahasiswa', key: 'students', value: (r) => r.students ?? null, format: 'int' },
  { header: 'Tambahan Susulan', key: 'late', value: (r) => yesNo(r.is_late_addition) },
];

export const KPI_S1_COLUMNS: Column<ActivityKpiRow>[] = [
  { header: 'Kode', key: 'code', value: (r) => r.code },
  { header: 'Nama', key: 'name', value: (r) => r.name },
  { header: 'Jenis', key: 'type', value: (r) => r.type_name },
  { header: 'Unit', key: 'unit', value: (r) => joinList(r.unit_names) },
  { header: 'Mitra', key: 'partner', value: (r) => joinList(r.partner_names) },
  { header: 'Negara', key: 'country', value: (r) => joinList(r.country_codes) },
  { header: 'Tanggal Mulai', key: 'start', value: (r) => r.start_date, format: 'date' },
  { header: 'Semester', key: 'sem', value: (r) => r.semester_label },
  { header: 'Kategori', key: 'cat', value: (r) => (r.bucket === 'international' ? 'Internasional' : r.bucket === 'domestic' ? 'Domestik' : r.bucket) },
  { header: 'Kegiatan Tertaut', key: 'linked', value: (r) => r.linked_count, format: 'int' },
  { header: 'Tambahan Susulan', key: 'late', value: (r) => yesNo(r.is_late_addition) },
];

export const BASE_COLUMNS: Column<ActivityKpiRow>[] = [
  { header: 'Kode', key: 'code', value: (r) => r.code },
  { header: 'Nama', key: 'name', value: (r) => r.name },
  { header: 'Jenis', key: 'type', value: (r) => r.type_name },
  { header: 'Arah', key: 'dir', value: (r) => label(DIRECTION_LABEL, r.direction) },
  { header: 'Unit', key: 'unit', value: (r) => joinList(r.unit_names) },
  { header: 'Mitra', key: 'partner', value: (r) => joinList(r.partner_names) },
  { header: 'Negara', key: 'country', value: (r) => joinList(r.country_codes) },
  { header: 'Tanggal Mulai', key: 'start', value: (r) => r.start_date, format: 'date' },
  { header: 'Semester', key: 'sem', value: (r) => r.semester_label },
  { header: 'Kegiatan Tertaut', key: 'linked', value: (r) => r.linked_count, format: 'int' },
  { header: 'Tambahan Susulan', key: 'late', value: (r) => yesNo(r.is_late_addition) },
];

export const KPI_24_COLUMNS: Column<ChainKpiRow>[] = [
  { header: 'ID Rantai', key: 'chain', value: (r) => r.chain_id, format: 'int' },
  { header: 'No. Dokumen (saat ini)', key: 'cur', value: (r) => r.current_doc_number },
  { header: 'Dokumen dalam Rantai', key: 'docs', value: (r) => joinList(r.doc_numbers) },
  { header: 'Jenis (MoU/MoA)', key: 'kind', value: (r) => r.kind },
  { header: 'Judul', key: 'title', value: (r) => r.title },
  { header: 'Mitra', key: 'partner', value: (r) => joinList(r.partner_names) },
  { header: 'Negara', key: 'country', value: (r) => joinList(r.country_codes) },
  { header: 'Internasional', key: 'intl', value: (r) => yesNo(r.is_international) },
  { header: 'Mulai Rantai', key: 'start', value: (r) => r.chain_start, format: 'date' },
  { header: 'Akhir Rantai', key: 'end', value: (r) => r.chain_end, format: 'date' },
  { header: 'Perpanjangan Otomatis', key: 'auto', value: (r) => yesNo(r.auto_renewed) },
  { header: 'Status', key: 'status', value: (r) => CHAIN_STATUS_LABEL[r.bucket] ?? r.bucket },
  { header: 'Masa Tenggang s.d.', key: 'grace', value: (r) => r.grace_until, format: 'date' },
  { header: 'Kegiatan (kode)', key: 'acts', value: (r) => joinList((r.activities ?? []).map((a) => a.code)) },
];

export const REALIZATION_COLUMNS: Column<ChainKpiRow>[] = [
  ...KPI_24_COLUMNS,
  { header: 'Jumlah Kegiatan', key: 'n', value: (r) => (r.activities ?? []).length, format: 'int' },
  {
    header: 'Kegiatan Terakhir',
    key: 'last',
    value: (r) => (r.activities ?? []).reduce<string | null>((m, a) => (m === null || a.start_date > m ? a.start_date : m), null),
    format: 'date',
  },
];

type S8Row = { kind: 'Dilaporkan' | 'Belum dilaporkan'; ref: string; title: string; date: string | null; unit: string; partner: string; country: string; source: string };

export function s8Rows(rows: DrilldownResult['rows']): S8Row[] {
  const out: S8Row[] = [];
  for (const r of rows as unknown[]) {
    if (isActivityRow(r)) {
      out.push({ kind: 'Dilaporkan', ref: r.code, title: r.name, date: r.start_date, unit: joinList(r.unit_names), partner: joinList(r.partner_names), country: joinList(r.country_codes), source: 'SIM Realisasi' });
    } else if (isKnownRow(r)) {
      out.push({
        kind: 'Belum dilaporkan',
        ref: String(r.known_id),
        title: r.title ?? 'Kegiatan internasional (rincian hanya untuk tim IO)',
        date: r.activity_date,
        unit: r.unit_name ?? '',
        partner: r.partner_name ?? '',
        country: r.country_code ?? '',
        source: [r.source ? label(KNOWN_SOURCE_LABEL, r.source) : null, r.source_reference].filter(Boolean).join(' · '),
      });
    }
  }
  return out;
}

export const KPI_S8_COLUMNS: Column<S8Row>[] = [
  { header: 'Jenis Baris', key: 'kind', value: (r) => r.kind },
  { header: 'Kode/ID', key: 'ref', value: (r) => r.ref },
  { header: 'Judul', key: 'title', value: (r) => r.title },
  { header: 'Tanggal', key: 'date', value: (r) => r.date, format: 'date' },
  { header: 'Unit', key: 'unit', value: (r) => r.unit },
  { header: 'Mitra', key: 'partner', value: (r) => r.partner },
  { header: 'Negara', key: 'country', value: (r) => r.country },
  { header: 'Sumber', key: 'source', value: (r) => r.source },
];

/** Adds the sheet for one KPI drill-down result; returns the data row count. */
export function addKpiSheet(wb: ExcelJS.Workbook, kpi: DrilldownKpi, dd: DrilldownResult, sheetName?: string): number {
  const rows = (dd.rows ?? []) as unknown[];
  switch (kpi) {
    case '1.1': {
      const r = rows.filter(isActivityRow);
      addTableSheet(wb, sheetName ?? '1.1', KPI_11_COLUMNS, r);
      return r.length;
    }
    case '1.19.S1': {
      const r = rows.filter(isActivityRow);
      addTableSheet(wb, sheetName ?? '1.19.S1', KPI_S1_COLUMNS, r);
      return r.length;
    }
    case '1.19.24': {
      const r = rows.filter(isChainRow);
      addTableSheet(wb, sheetName ?? '1.19.24', KPI_24_COLUMNS, r);
      return r.length;
    }
    case '1.19.S8': {
      const r = s8Rows(dd.rows);
      addTableSheet(wb, sheetName ?? '1.19.S8', KPI_S8_COLUMNS, r);
      return r.length;
    }
    case 'base': {
      const r = rows.filter(isActivityRow);
      addTableSheet(wb, sheetName ?? 'Kegiatan Terverifikasi', BASE_COLUMNS, r);
      return r.length;
    }
  }
}

// ---------- Ringkasan ----------
type SummaryRow = { kpi: string; desc: string; value: number | null; isPct: boolean; num: number | null; den: number | null; grace: number | null; note: string };

export function summaryRows(v: KpiValues): SummaryRow[] {
  const rows: SummaryRow[] = [];
  const k11 = v.kpi_1_1;
  rows.push({ kpi: '1.1', desc: 'Mahasiswa inbound', value: k11.inbound, isPct: false, num: null, den: null, grace: null, note: 'Pasangan (NRP, grup kegiatan) unik' });
  rows.push({ kpi: '1.1', desc: 'Mahasiswa outbound', value: k11.outbound, isPct: false, num: null, den: null, grace: null, note: 'Pasangan (NRP, grup kegiatan) unik' });
  rows.push({ kpi: '1.1', desc: 'Total mahasiswa inbound + outbound', value: k11.total, isPct: false, num: null, den: null, grace: null, note: '' });
  for (const s of k11.by_semester ?? []) {
    rows.push({ kpi: '1.1', desc: `${s.label} — inbound / outbound`, value: s.inbound + s.outbound, isPct: false, num: null, den: null, grace: null, note: `Inbound ${s.inbound} · Outbound ${s.outbound}` });
  }
  rows.push({ kpi: '1.19.S1', desc: 'Kegiatan internasional dengan mitra', value: v.kpi_1_19_s1.international, isPct: false, num: null, den: null, grace: null, note: 'Grup kegiatan unik' });
  rows.push({ kpi: '1.19.S1', desc: 'Kegiatan domestik (referensi)', value: v.kpi_1_19_s1.domestic, isPct: false, num: null, den: null, grace: null, note: 'Ditampilkan sebagai pembanding' });
  const scopes: Array<['all' | 'international' | 'domestic', string]> = [
    ['all', 'Semua kerja sama'],
    ['international', 'Kerja sama internasional'],
    ['domestic', 'Kerja sama domestik'],
  ];
  for (const [key, desc] of scopes) {
    const t = v.kpi_1_19_24[key];
    rows.push({ kpi: '1.19.24', desc: `Persentase terlaksana — ${desc}`, value: t.pct, isPct: true, num: t.numerator, den: t.denominator, grace: t.grace_excluded, note: 'Satuan = rantai perpanjangan; masa tenggang dikecualikan dari penyebut' });
  }
  const s8 = v.kpi_1_19_s8;
  rows.push({
    kpi: '1.19.S8',
    desc: 'Persentase kegiatan internasional dilaporkan via SIM',
    value: s8.pct,
    isPct: true,
    num: s8.reported,
    den: s8.reported + s8.unmatched_known,
    grace: null,
    note: `${s8.unmatched_known} kegiatan belum dilaporkan (register)`,
  });
  return rows;
}

export const SUMMARY_COLUMNS: Column<SummaryRow>[] = [
  { header: 'KPI', key: 'kpi', value: (r) => r.kpi },
  { header: 'Uraian', key: 'desc', value: (r) => r.desc },
  { header: 'Nilai', key: 'value', value: (r) => r.value, format: (r) => (r.isPct ? 'pct' : 'int') },
  { header: 'Pembilang', key: 'num', value: (r) => r.num, format: 'int' },
  { header: 'Penyebut', key: 'den', value: (r) => r.den, format: 'int' },
  { header: 'Masa Tenggang', key: 'grace', value: (r) => r.grace, format: 'int' },
  { header: 'Catatan', key: 'note', value: (r) => r.note },
];

// ---------- Activities ----------
export const ACTIVITY_COLUMNS: Column<ActivityListRow>[] = [
  { header: 'Kode', key: 'code', value: (r) => r.code },
  { header: 'Nama Kegiatan', key: 'name', value: (r) => r.name },
  { header: 'Jenis Kegiatan', key: 'type', value: (r) => r.type_name },
  { header: 'Unit Pengaju', key: 'unit', value: (r) => r.submitter_unit_name },
  { header: 'Unit Lain', key: 'units', value: (r) => joinList((r.unit_names ?? []).filter((n) => n !== r.submitter_unit_name)) },
  { header: 'No. Dokumen Kerja Sama', key: 'docs', value: (r) => joinList(r.document_numbers) },
  { header: 'Mitra', key: 'partner', value: (r) => joinList(r.partner_names) },
  { header: 'Negara', key: 'country', value: (r) => joinList(r.country_codes) },
  { header: 'Tanggal Mulai', key: 'start', value: (r) => r.start_date, format: 'date' },
  { header: 'Tanggal Selesai', key: 'end', value: (r) => r.end_date, format: 'date' },
  { header: 'Semester', key: 'sem', value: (r) => r.semester_label },
  { header: 'Tahun Akademik', key: 'ay', value: (r) => r.ay_label },
  { header: 'Moda', key: 'mode', value: (r) => label(MODE_LABEL, r.mode) },
  { header: 'Status', key: 'status', value: (r) => label(ACTIVITY_STATUS_LABEL, r.status) },
  { header: 'Status Kemitraan', key: 'ps', value: (r) => label(TRACK_STATUS_LABEL, r.partnership_status) },
  { header: 'Status Mobilitas', key: 'ms', value: (r) => label(TRACK_STATUS_LABEL, r.mobility_status) },
  { header: 'SLA Kemitraan (hari kerja)', key: 'psla', value: (r) => r.partnership_sla_days, format: 'int' },
  { header: 'SLA Mobilitas (hari kerja)', key: 'msla', value: (r) => r.mobility_sla_days, format: 'int' },
  { header: 'Terlambat', key: 'late', value: (r) => yesNo(r.is_late) },
  { header: 'Batas Pelaporan', key: 'deadline', value: (r) => r.reporting_deadline, format: 'date' },
  { header: 'Diajukan', key: 'submitted', value: (r) => r.submitted_at, format: 'date' },
  { header: 'Diverifikasi', key: 'verified', value: (r) => r.verified_at, format: 'date' },
];

// ---------- Snapshot extras ----------
export const LATE_ADDITION_COLUMNS: Column<LateAdditionRow>[] = [
  { header: 'Kode', key: 'code', value: (r) => r.code },
  { header: 'Nama', key: 'name', value: (r) => r.name },
  { header: 'Unit', key: 'unit', value: (r) => joinList(r.unit_names) },
  { header: 'Tanggal Mulai', key: 'start', value: (r) => r.start_date, format: 'date' },
  { header: 'Diverifikasi', key: 'verified', value: (r) => r.verified_at, format: 'datetime' },
  { header: 'Snapshot Sebelumnya', key: 'prev', value: (r) => r.previous_snapshot_label },
  { header: 'Dihitung di Snapshot Ini', key: 'counted', value: (r) => yesNo(r.counted_in_this_snapshot) },
  { header: 'KPI', key: 'kpi', value: (r) => joinList(r.kpi_codes) },
];

/** Post-freeze diff as text with human field labels (requirements review L-2). */
export function formatDiff(diff: unknown): string {
  return formatDiffLines(diff).join('\n');
}

export const POST_FREEZE_COLUMNS: Column<PostFreezeChangeRow>[] = [
  { header: 'Waktu', key: 'at', value: (r) => r.created_at, format: 'datetime' },
  { header: 'Kode', key: 'code', value: (r) => r.code },
  { header: 'Nama', key: 'name', value: (r) => r.name },
  { header: 'Jalur', key: 'track', value: (r) => label(TRACK_LABEL, r.track) },
  { header: 'Aksi', key: 'action', value: (r) => (LOG_ACTION_LABEL as Record<string, string>)[r.action] ?? r.action },
  { header: 'Oleh', key: 'actor', value: (r) => r.actor_name },
  { header: 'Catatan', key: 'note', value: (r) => r.note },
  { header: 'Perubahan (field: lama → baru)', key: 'diff', value: (r) => formatDiff(r.diff) },
];

export const SNAPSHOT_ARCHIVE_COLUMNS: Column<SnapshotListRow>[] = [
  { header: 'Tahun Akademik', key: 'ay', value: (r) => r.ay_label },
  { header: 'Jenis', key: 'kind', value: (r) => label(SNAPSHOT_KIND_LABEL, r.kind) },
  { header: 'Jendela', key: 'window', value: (r) => `${formatDate(r.window_start)} – ${formatDate(r.window_end)}` },
  { header: 'Cutoff', key: 'cutoff', value: (r) => r.cutoff_date, format: 'date' },
  { header: 'Dibekukan pada', key: 'frozen', value: (r) => r.frozen_at, format: 'datetime' },
  { header: 'Oleh', key: 'by', value: (r) => r.frozen_by_name },
  { header: 'Status', key: 'status', value: (r) => (r.is_live ? 'Berlaku' : 'Digantikan') },
  { header: 'Alasan Bekukan Ulang', key: 'reason', value: (r) => r.refreeze_reason },
  { header: '1.1 Total', key: 'k11', value: (r) => r.summary?.kpi_1_1_total ?? null, format: 'int' },
  { header: '1.19.S1 Internasional', key: 's1', value: (r) => r.summary?.kpi_1_19_s1_international ?? null, format: 'int' },
  { header: '1.19.24 %', key: 'k24', value: (r) => r.summary?.kpi_1_19_24_pct ?? null, format: 'pct' },
  { header: '1.19.S8 %', key: 's8', value: (r) => r.summary?.kpi_1_19_s8_pct ?? null, format: 'pct' },
  { header: 'Tambahan Susulan', key: 'late', value: (r) => r.late_additions, format: 'int' },
  { header: 'Perubahan Pasca-Beku', key: 'pfc', value: (r) => r.post_freeze_changes, format: 'int' },
];

// ---------- SLA ----------
export interface SlaRow {
  a: ActivityListRow;
  track: 'partnership' | 'mobility';
  status: string;
  since: string | null;
  days: number | null;
  level: string | null;
}
export const SLA_LEVEL_TEXT: Record<string, string> = SLA_LEVEL_LABEL;

export function slaRows(acts: ActivityListRow[]): SlaRow[] {
  const out: SlaRow[] = [];
  for (const a of acts) {
    if (a.status === 'draft' || !a.submitted_at) continue;
    out.push({ a, track: 'partnership', status: a.partnership_status, since: a.partnership_since, days: a.partnership_sla_days, level: a.partnership_sla_level });
    if (a.mobility_status !== 'not_required') {
      out.push({ a, track: 'mobility', status: a.mobility_status, since: a.mobility_since, days: a.mobility_sla_days, level: a.mobility_sla_level });
    }
  }
  return out;
}

