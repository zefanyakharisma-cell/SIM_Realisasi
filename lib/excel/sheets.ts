// Column definitions shared by the export kinds (CONTRACTS §8.2 column lists, verbatim headers).
import { formatDiffLines } from '@/lib/realisasi/diff-format';
import type ExcelJS from 'exceljs';
import type {
  ActivityKpiRow,
  ActivityListRow,
  AwardsInitiativeRow,
  AwardsStudentRow,
  ChainKpiRow,
  ConflictRow,
  DrilldownKpi,
  DrilldownResult,
  KpiParticipantRow,
  KpiValues,
  LateAdditionRow,
  PeriodInfo,
  PostFreezeChangeRow,
  SnapshotListRow,
} from '@/lib/realisasi/types';
import {
  ACTIVITY_STATUS_LABEL,
  CONFLICT_STATUS_LABEL,
  DIRECTION_LABEL,
  LOG_ACTION_LABEL,
  MOBILITY_CATEGORY_LABEL,
  MODE_LABEL,
  SNAPSHOT_KIND_LABEL,
  TRACK_LABEL,
  TRACK_STATUS_LABEL,
} from '@/lib/realisasi/status';
import { formatDate, formatDateTime } from '@/lib/realisasi/format';
import { addTableSheet, type Column } from '@/lib/excel/workbook';
import type { RollupRow } from '@/lib/realisasi/unit-rollup';

// ---------- small helpers ----------
export function label<K extends string>(map: Partial<Record<K, string>> | undefined, key: K | null | undefined): string | null {
  if (key === null || key === undefined) return null;
  return map?.[key] ?? String(key);
}
export const joinList = (xs: ReadonlyArray<string | null | undefined> | null | undefined): string =>
  (xs ?? []).filter((x): x is string => typeof x === 'string' && x !== '').join(', ');
export const yesNo = (b: boolean | null | undefined): string => (b ? 'Ya' : 'Tidak');

export function dataAsOf(period: PeriodInfo): string {
  if (period.frozen && period.snapshot_id) {
    return `Snapshot ${period.label} · dibekukan ${formatDateTime(period.frozen_at)} · id ${period.snapshot_id}`;
  }
  if (period.frozen) return `${period.label} · per pembekuan ${formatDateTime(period.frozen_at)}`;
  return `${period.label} · data s.d. ${formatDate(period.window_end)} (live)`;
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

export const CHAIN_STATUS_LABEL: Record<string, string> = {
  realized: 'Terlaksana',
  not_realized: 'Belum terlaksana',
  grace_excluded: 'Masa tenggang',
};

// ---------- KPI sheets ----------
export const KPI_11_COLUMNS: Column<ActivityKpiRow>[] = [
  { header: 'Kode', key: 'code', value: (r) => r.code },
  { header: 'Nama', key: 'name', value: (r) => r.name },
  { header: 'Jenis', key: 'type', value: (r) => r.agenda_name },
  { header: 'Kategori Mobilitas', key: 'cat', value: (r) => label(MOBILITY_CATEGORY_LABEL, r.mobility_category) },
  { header: 'Inbound/Outbound', key: 'dir', value: (r) => label(DIRECTION_LABEL, r.direction) },
  { header: 'Unit', key: 'unit', value: (r) => joinList(r.unit_names) },
  { header: 'Mitra', key: 'partner', value: (r) => joinList(r.partner_names) },
  { header: 'Negara', key: 'country', value: (r) => joinList(r.country_codes) },
  { header: 'Tanggal Mulai', key: 'start', value: (r) => r.start_date, format: 'date' },
  { header: 'Semester', key: 'sem', value: (r) => r.semester_label },
  { header: 'Jumlah Mahasiswa', key: 'students', value: (r) => r.students ?? null, format: 'int' },
  { header: 'Tambahan Susulan', key: 'late', value: (r) => yesNo(r.is_late_addition) },
];

export const KPI_S1_COLUMNS: Column<ActivityKpiRow>[] = [
  { header: 'Kode', key: 'code', value: (r) => r.code },
  { header: 'Nama', key: 'name', value: (r) => r.name },
  { header: 'Jenis', key: 'type', value: (r) => r.agenda_name },
  { header: 'Unit', key: 'unit', value: (r) => joinList(r.unit_names) },
  { header: 'Mitra', key: 'partner', value: (r) => joinList(r.partner_names) },
  { header: 'Negara', key: 'country', value: (r) => joinList(r.country_codes) },
  { header: 'Tanggal Mulai', key: 'start', value: (r) => r.start_date, format: 'date' },
  { header: 'Semester', key: 'sem', value: (r) => r.semester_label },
  { header: 'Kategori', key: 'cat', value: (r) => (r.bucket === 'international' ? 'Internasional' : r.bucket === 'domestic' ? 'Domestik' : r.bucket) },
  { header: 'Tambahan Susulan', key: 'late', value: (r) => yesNo(r.is_late_addition) },
];

export const BASE_COLUMNS: Column<ActivityKpiRow>[] = [
  { header: 'Kode', key: 'code', value: (r) => r.code },
  { header: 'Nama', key: 'name', value: (r) => r.name },
  { header: 'Jenis', key: 'type', value: (r) => r.agenda_name },
  { header: 'Inbound/Outbound', key: 'dir', value: (r) => label(DIRECTION_LABEL, r.direction) },
  { header: 'Unit', key: 'unit', value: (r) => joinList(r.unit_names) },
  { header: 'Mitra', key: 'partner', value: (r) => joinList(r.partner_names) },
  { header: 'Negara', key: 'country', value: (r) => joinList(r.country_codes) },
  { header: 'Tanggal Mulai', key: 'start', value: (r) => r.start_date, format: 'date' },
  { header: 'Semester', key: 'sem', value: (r) => r.semester_label },
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
      addTableSheet(wb, sheetName ?? '1.19.S4', KPI_24_COLUMNS, r);
      return r.length;
    }
    case 'base': {
      const r = rows.filter(isActivityRow);
      addTableSheet(wb, sheetName ?? 'Kegiatan Terverifikasi', BASE_COLUMNS, r);
      return r.length;
    }
  }
}

// ---------- Laporan per RENSTRA (Revisi V.2) ----------
/** Sheet 1 of a RENSTRA workbook: one row per unit, Fakultas → Program Studi → Program, then the scope total. */
export interface RollupSheetRow {
  faculty: string | null;
  prodi: string | null;
  program: string | null;
  level: string;
  own: number | null;
  total: number;
  isTotal: boolean;
}

export function rollupSheetRows(rows: RollupRow[], totalLabel: string, scopeValue: number): RollupSheetRow[] {
  const out: RollupSheetRow[] = rows.map((r) => ({
    faculty: r.path[0] ?? null,
    prodi: r.depth >= 1 ? (r.path[1] ?? null) : null,
    program: r.depth >= 2 ? r.path.slice(2).join(' / ') : null,
    level: r.level,
    own: r.own,
    total: r.total,
    isTotal: false,
  }));
  out.push({ faculty: totalLabel, prodi: null, program: null, level: 'Total', own: null, total: scopeValue, isTotal: true });
  return out;
}

export function rollupColumns(valueHeader: string): Column<RollupSheetRow>[] {
  return [
    { header: 'Fakultas', key: 'fac', value: (r) => r.faculty },
    { header: 'Program Studi', key: 'prodi', value: (r) => r.prodi },
    { header: 'Program', key: 'program', value: (r) => r.program },
    { header: 'Tingkat', key: 'level', value: (r) => r.level },
    { header: `${valueHeader} (unit sendiri)`, key: 'own', value: (r) => r.own, format: 'int' },
    { header: `${valueHeader} (total)`, key: 'total', value: (r) => r.total, format: 'int' },
  ];
}

export interface OverallPctRow {
  desc: string;
  num: number;
  den: number;
  grace: number;
  pct: number | null;
}

export const KPI_S4_OVERALL_COLUMNS: Column<OverallPctRow>[] = [
  { header: 'RENSTRA', key: 'k', value: () => '1.19.S4' },
  { header: 'Uraian', key: 'desc', value: (r) => r.desc },
  { header: 'Kerja Sama Terlaksana', key: 'num', value: (r) => r.num, format: 'int' },
  { header: 'Kerja Sama Aktif (penyebut)', key: 'den', value: (r) => r.den, format: 'int' },
  { header: 'Masa Tenggang (dikecualikan)', key: 'grace', value: (r) => r.grace, format: 'int' },
  { header: 'Persentase', key: 'pct', value: (r) => r.pct, format: 'pct' },
];

/** KPI activity columns plus the Fakultas of each involved unit (data sheet of a RENSTRA workbook). */
export function withFacultyColumn(cols: Column<ActivityKpiRow>[], facultyOf: ReadonlyMap<string, string>): Column<ActivityKpiRow>[] {
  const fac: Column<ActivityKpiRow> = {
    header: 'Fakultas',
    key: 'faculty',
    value: (r) => joinList([...new Set(r.unit_names.map((n) => facultyOf.get(n) ?? n))]),
  };
  const i = cols.findIndex((c) => c.key === 'unit');
  return [...cols.slice(0, i + 1), fac, ...cols.slice(i + 1)];
}

/** Students behind 1.1 (personal data; snapshot workbook and the 1.1 RENSTRA workbooks). */
export const KPI_PARTICIPANT_COLUMNS: Column<KpiParticipantRow>[] = [
  { header: 'Kode Kegiatan', key: 'code', value: (r) => r.code },
  { header: 'Nama Kegiatan', key: 'name', value: (r) => r.name },
  { header: 'Inbound/Outbound', key: 'dir', value: (r) => label(DIRECTION_LABEL, r.direction) },
  { header: 'Bagian (PETRA/Inbound)', key: 'section', value: (r) => (r.section === 'inbound' ? 'Inbound' : 'PETRA') },
  { header: 'NRP', key: 'nrp', value: (r) => r.nrp, format: 'text' },
  { header: 'Nama', key: 'fn', value: (r) => r.full_name },
  { header: 'Fakultas', key: 'fac', value: (r) => r.faculty_name },
  { header: 'Prodi', key: 'prodi', value: (r) => r.prodi_name },
  { header: 'Institusi Asal', key: 'home', value: (r) => r.home_institution },
  { header: 'Negara Asal', key: 'homecc', value: (r) => r.home_country_code },
  { header: 'Tanggal Mulai', key: 'start', value: (r) => r.start_date, format: 'date' },
  { header: 'Semester', key: 'sem', value: (r) => r.semester_label },
];

// ---------- Ringkasan ----------
type SummaryRow = { kpi: string; desc: string; value: number | null; isPct: boolean; num: number | null; den: number | null; grace: number | null; note: string };

export function summaryRows(v: KpiValues): SummaryRow[] {
  const rows: SummaryRow[] = [];
  const k11 = v.kpi_1_1;
  rows.push({ kpi: '1.1', desc: 'Mahasiswa inbound', value: k11.inbound, isPct: false, num: null, den: null, grace: null, note: 'Pasangan (NRP, kegiatan) unik; duplikat antar-unit sesuai keputusan tim Mobilitas' });
  rows.push({ kpi: '1.1', desc: 'Mahasiswa outbound', value: k11.outbound, isPct: false, num: null, den: null, grace: null, note: 'Pasangan (NRP, kegiatan) unik; duplikat antar-unit sesuai keputusan tim Mobilitas' });
  rows.push({ kpi: '1.1', desc: 'Total mahasiswa inbound + outbound', value: k11.total, isPct: false, num: null, den: null, grace: null, note: '' });
  for (const s of k11.by_semester ?? []) {
    rows.push({ kpi: '1.1', desc: `${s.label} — inbound / outbound`, value: s.inbound + s.outbound, isPct: false, num: null, den: null, grace: null, note: `Inbound ${s.inbound} · Outbound ${s.outbound}` });
  }
  rows.push({ kpi: '1.19.S1', desc: 'Kegiatan internasional dengan mitra', value: v.kpi_1_19_s1.international, isPct: false, num: null, den: null, grace: null, note: 'Kegiatan terverifikasi' });
  rows.push({ kpi: '1.19.S1', desc: 'Kegiatan domestik (referensi)', value: v.kpi_1_19_s1.domestic, isPct: false, num: null, den: null, grace: null, note: 'Ditampilkan sebagai pembanding' });
  const scopes: Array<['all' | 'international' | 'domestic', string]> = [
    ['all', 'Semua kerja sama'],
    ['international', 'Kerja sama internasional'],
    ['domestic', 'Kerja sama domestik'],
  ];
  for (const [key, desc] of scopes) {
    const t = v.kpi_1_19_24[key];
    rows.push({ kpi: '1.19.S4', desc: `Persen terlaksana MoU & MoA — ${desc}`, value: t.pct, isPct: true, num: t.numerator, den: t.denominator, grace: t.grace_excluded, note: 'Satuan = rantai perpanjangan; masa tenggang dikecualikan dari penyebut' });
  }
  return rows;
}

export const SUMMARY_COLUMNS: Column<SummaryRow>[] = [
  { header: 'RENSTRA', key: 'kpi', value: (r) => r.kpi },
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
  { header: 'Jenis Kegiatan', key: 'type', value: (r) => r.agenda_name },
  { header: 'Inbound/Outbound', key: 'dir', value: (r) => label(DIRECTION_LABEL, r.direction) },
  { header: 'Unit Pengaju', key: 'unit', value: (r) => r.submitter_unit_name },
  { header: 'Unit Lain yang Terlibat', key: 'units', value: (r) => joinList((r.unit_names ?? []).filter((n) => n !== r.submitter_unit_name)) },
  { header: 'No. Dokumen Kerja Sama', key: 'docs', value: (r) => joinList(r.document_numbers) },
  { header: 'Mitra', key: 'partner', value: (r) => joinList(r.partner_names) },
  { header: 'Negara', key: 'country', value: (r) => joinList(r.country_codes) },
  { header: 'Tanggal Mulai', key: 'start', value: (r) => r.start_date, format: 'date' },
  { header: 'Tanggal Selesai', key: 'end', value: (r) => r.end_date, format: 'date' },
  { header: 'Semester', key: 'sem', value: (r) => r.semester_label },
  { header: 'Tahun Akademik', key: 'ay', value: (r) => r.ay_label },
  { header: 'Moda', key: 'mode', value: (r) => label(MODE_LABEL, r.mode) },
  { header: 'Status', key: 'status', value: (r) => label(ACTIVITY_STATUS_LABEL, r.status) },
  { header: 'Status Verifikasi Mobilitas', key: 'ms', value: (r) => label(TRACK_STATUS_LABEL, r.mobility_status) },
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
  { header: 'RENSTRA', key: 'kpi', value: (r) => joinList(r.kpi_codes) },
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
  { header: '1.19.S4 %', key: 'k24', value: (r) => r.summary?.kpi_1_19_24_pct ?? null, format: 'pct' },
  { header: 'Tambahan Susulan', key: 'late', value: (r) => r.late_additions, format: 'int' },
  { header: 'Perubahan Pasca-Beku', key: 'pfc', value: (r) => r.post_freeze_changes, format: 'int' },
];


// ---------- International Awards (Revisi V.1) ----------
export const AWARDS_STUDENT_COLUMNS: Column<AwardsStudentRow & { rank: number }>[] = [
  { header: 'Peringkat', key: 'rank', value: (r) => r.rank, format: 'int' },
  { header: 'Program Studi', key: 'unit', value: (r) => r.unit_name },
  { header: 'Joint Degree / Double Degree', key: 'jd', value: (r) => r.jd_dd, format: 'int' },
  { header: 'Student Exchange', key: 'ex', value: (r) => r.student_exchange, format: 'int' },
  { header: 'Short / Summer Program', key: 'ss', value: (r) => r.short_summer, format: 'int' },
  { header: 'Kegiatan Internasional (<14 hari)', key: 'short', value: (r) => r.short_international, format: 'int' },
  { header: 'Total', key: 'total', value: (r) => r.total, format: 'int' },
];

export const AWARDS_INITIATIVE_COLUMNS: Column<AwardsInitiativeRow & { rank: number }>[] = [
  { header: 'Peringkat', key: 'rank', value: (r) => r.rank, format: 'int' },
  { header: 'Program Studi', key: 'unit', value: (r) => r.unit_name },
  { header: 'Jumlah Inbound', key: 'in', value: (r) => r.inbound, format: 'int' },
  { header: 'Jumlah Outbound', key: 'out', value: (r) => r.outbound, format: 'int' },
  { header: 'Jumlah Kegiatan', key: 'act', value: (r) => r.activities, format: 'int' },
  { header: 'Total', key: 'total', value: (r) => r.total, format: 'int' },
];

export function ranked<R>(rows: R[]): Array<R & { rank: number }> {
  return rows.map((r, i) => ({ ...r, rank: i + 1 }));
}

// ---------- Student conflicts (Verifikasi Mobilitas) ----------
export const CONFLICT_COLUMNS: Column<ConflictRow>[] = [
  { header: 'NRP', key: 'nrp', value: (r) => r.nrp },
  { header: 'Nama Mahasiswa', key: 'student', value: (r) => r.student_name },
  { header: 'Kegiatan A', key: 'a', value: (r) => `${r.a.code} — ${r.a.name}` },
  { header: 'Unit A', key: 'au', value: (r) => r.a.unit_name },
  { header: 'Kegiatan B', key: 'b', value: (r) => `${r.b.code} — ${r.b.name}` },
  { header: 'Unit B', key: 'bu', value: (r) => r.b.unit_name },
  { header: 'Status', key: 'status', value: (r) => label(CONFLICT_STATUS_LABEL, r.status) },
  { header: 'Diakui pada', key: 'kept', value: (r) => (r.kept_activity_id === r.a.id ? r.a.code : r.kept_activity_id === r.b.id ? r.b.code : null) },
  { header: 'Catatan', key: 'note', value: (r) => r.note },
  { header: 'Diputuskan oleh', key: 'by', value: (r) => r.resolved_by_name },
  { header: 'Diputuskan pada', key: 'at', value: (r) => r.resolved_at, format: 'datetime' },
];
