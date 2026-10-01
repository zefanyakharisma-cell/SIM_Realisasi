// Export kinds (CONTRACTS §8.2). Each entry declares who may export (server-side gate, 403 otherwise)
// and how to build the workbook. All data comes from RLS-scoped reads / read RPCs inside `withUser`.
import type ExcelJS from 'exceljs';
import type { Tx } from '@/lib/db';
import { can, type SessionUser } from '@/lib/session';
import type {
  ActivityListRow,
  ChainKpiRow,
  DrilldownKpi,
  ExportKind,
  KnownActivityRow,
  DuplicateCandidateRow,
  KpiCharts,
  PeriodInfo,
  Period,
} from '@/lib/realisasi/types';
import {
  ACTIVITY_STATUS_LABEL,
  DUP_STATUS_LABEL,
  KNOWN_SOURCE_LABEL,
  KNOWN_STATUS_LABEL,
  PSET_STATUS_LABEL,
  TRACK_LABEL,
  TRACK_STATUS_LABEL,
  DIRECTION_LABEL,
} from '@/lib/realisasi/status';
import { formatDate, formatDateTime } from '@/lib/realisasi/format';
import { parseActivityFilters, describeActivityFilters } from '@/lib/realisasi/schemas/filters';
import { listActivities } from '@/lib/realisasi/queries/activities';
import { parseKnownFilters } from '@/lib/realisasi/schemas/known';
import { listKnownActivities } from '@/lib/realisasi/queries/known';
import { listDuplicateCandidates } from '@/lib/realisasi/queries/duplicates';
import {
  BUCKET_LABEL,
  CHART_LABEL,
  KPI_LABEL,
  getParam,
  isUuid,
  parseBucket,
  parseChartKey,
  parseDrilldownKpi,
  parsePeriodParams,
  parsePositiveInt,
  parseRealizationStatus,
  realizationStatusToBucket,
  type ChartKey,
  type PeriodParams,
} from '@/lib/realisasi/schemas/report';
import {
  getAgreementRealization,
  getDashboard,
  getDrilldown,
  getKpiParticipantRows,
  getSettingsMap,
  getSnapshotDetail,
  getSnapshotList,
} from '@/lib/realisasi/queries/reports';
import { addInfoSheet, addTableSheet, createWorkbook, type Column } from '@/lib/excel/workbook';
import {
  ACTIVITY_COLUMNS,
  CHAIN_STATUS_LABEL,
  LATE_ADDITION_COLUMNS,
  POST_FREEZE_COLUMNS,
  REALIZATION_COLUMNS,
  SNAPSHOT_ARCHIVE_COLUMNS,
  SUMMARY_COLUMNS,
  addKpiSheet,
  dataAsOf,
  isChainRow,
  joinList,
  label,
  snapshotAsOf,
  summaryRows,
  yesNo,
} from '@/lib/excel/sheets';

export interface ExportContext {
  tx: Tx;
  user: SessionUser;
  params: URLSearchParams;
}
export interface ExportResult {
  workbook: ExcelJS.Workbook;
  periodLabel: string;
  rowCount: number;
  containsPersonal: boolean;
  filters: Record<string, unknown>;
}
export interface ExportDef {
  allowed: (u: SessionUser) => boolean;
  build: (ctx: ExportContext) => Promise<ExportResult>;
}

export class ExportParamError extends Error {
  readonly code = 'BAD_REQUEST';
}

const everyone = () => true;

function generatedBy(u: SessionUser): string {
  return `${u.displayName} (${u.email})`;
}

/** Submitters are always scoped to their own unit for KPI/dashboard kinds (CONTRACTS §8.2). */
function scopedPeriod(user: SessionUser, params: URLSearchParams): PeriodParams {
  const p = parsePeriodParams(params);
  if (user.role === 'submitter') {
    if (user.unitId !== null) p.unit = user.unitId;
    delete p.snapshot;
  }
  return p;
}

function periodFilters(period: PeriodInfo, scopeName: string | null): Array<[string, string]> {
  return [
    ['Tahun Akademik', period.ay_label],
    ['Periode', period.label],
    ['Lingkup', scopeName ?? 'Universitas'],
  ];
}

function periodRecord(p: PeriodParams): Record<string, unknown> {
  return { ay: p.ay ?? null, period: p.period, unit: p.unit ?? null, snapshot: p.snapshot ?? null };
}

function lookupName<T extends { id: number; name: string }>(rows: T[]) {
  const m = new Map(rows.map((r) => [r.id, r.name]));
  return (id: number) => m.get(id) ?? String(id);
}

async function nameLookups(tx: Tx) {
  const [types, units] = await Promise.all([
    tx`select id, name from realisasi.activity_types`,
    tx`select id, name from public.units`,
  ]);
  return {
    typeName: lookupName(types.map((r) => ({ id: Number(r.id), name: String(r.name) }))),
    unitName: lookupName(units.map((r) => ({ id: Number(r.id), name: String(r.name) }))),
  };
}

// ---------------------------------------------------------------- activities
async function buildActivities({ tx, user, params }: ExportContext): Promise<ExportResult> {
  const f = parseActivityFilters(params);
  const [rows, names] = await Promise.all([listActivities(tx, user, f), nameLookups(tx)]);
  const wb = createWorkbook();
  addInfoSheet(wb, {
    kind: 'activities',
    title: 'Daftar Kegiatan',
    filters: describeActivityFilters(f, names),
    generatedBy: generatedBy(user),
    generatedAt: new Date(),
    dataAsOf: 'Live (data saat ekspor)',
    rowCount: rows.length,
  });
  addTableSheet(wb, 'Kegiatan', ACTIVITY_COLUMNS, rows);
  return { workbook: wb, periodLabel: activitiesPeriodLabel(rows, f.ay), rowCount: rows.length, containsPersonal: false, filters: { ...f } };
}

function activitiesPeriodLabel(rows: ActivityListRow[], ay: number | undefined): string {
  if (ay === undefined) return 'semua';
  return rows.find((r) => r.academic_year_id === ay)?.ay_label ?? `TA-${ay}`;
}

// ---------------------------------------------------------------- participants
interface StudentExportRow {
  activity: ActivityListRow;
  version: number;
  version_status: string;
  section: string;
  nrp: string;
  full_name: string;
  faculty_name: string | null;
  prodi_name: string | null;
  home_institution: string | null;
  home_student_number: string | null;
  home_country_code: string | null;
}
interface StaffExportRow {
  activity: ActivityListRow;
  version: number;
  employee_id: string;
  full_name: string;
  unit_name: string | null;
}

async function buildParticipants({ tx, user, params }: ExportContext): Promise<ExportResult> {
  const f = parseActivityFilters(params);
  const versionMode = getParam(params, 'version') === 'latest' ? 'latest' : 'approved';
  const [acts, names] = await Promise.all([listActivities(tx, user, f), nameLookups(tx)]);
  const byId = new Map(acts.map((a) => [a.id, a]));
  const ids = acts.map((a) => a.id);

  // Chosen version per activity (RLS: participant rows only visible where can_view_participants()).
  const versions = ids.length
    ? versionMode === 'approved'
      ? await tx`
          select id, activity_id, version, status::text as status from realisasi.participant_set_versions
           where activity_id = any(${ids}::uuid[]) and status = 'approved'`
      : await tx`
          select distinct on (activity_id) id, activity_id, version, status::text as status
            from realisasi.participant_set_versions
           where activity_id = any(${ids}::uuid[]) and status <> 'draft'
           order by activity_id, version desc`
    : [];
  const vIds = versions.map((v) => String(v.id));
  const vMeta = new Map(versions.map((v) => [String(v.id), { activity_id: String(v.activity_id), version: Number(v.version), status: String(v.status) }]));

  const [students, staff] = vIds.length
    ? await Promise.all([
        tx`select set_version_id, section::text as section, nrp, full_name, faculty_name, prodi_name,
                  home_institution, home_student_number, home_country_code
             from realisasi.participant_students where set_version_id = any(${vIds}::uuid[])
            order by section, nrp`,
        tx`select set_version_id, employee_id, full_name, unit_name
             from realisasi.participant_staff where set_version_id = any(${vIds}::uuid[])
            order by employee_id`,
      ])
    : [[], []];

  const order = new Map(ids.map((id, i) => [id, i]));
  const studentRows: StudentExportRow[] = [];
  for (const s of students) {
    const meta = vMeta.get(String(s.set_version_id));
    const activity = meta && byId.get(meta.activity_id);
    if (!meta || !activity) continue;
    studentRows.push({
      activity,
      version: meta.version,
      version_status: meta.status,
      section: String(s.section),
      nrp: String(s.nrp),
      full_name: String(s.full_name),
      faculty_name: (s.faculty_name as string | null) ?? null,
      prodi_name: (s.prodi_name as string | null) ?? null,
      home_institution: (s.home_institution as string | null) ?? null,
      home_student_number: (s.home_student_number as string | null) ?? null,
      home_country_code: (s.home_country_code as string | null) ?? null,
    });
  }
  const staffRows: StaffExportRow[] = [];
  for (const s of staff) {
    const meta = vMeta.get(String(s.set_version_id));
    const activity = meta && byId.get(meta.activity_id);
    if (!meta || !activity) continue;
    staffRows.push({ activity, version: meta.version, employee_id: String(s.employee_id), full_name: String(s.full_name), unit_name: (s.unit_name as string | null) ?? null });
  }
  const byActivity = (a: { activity: ActivityListRow }, b: { activity: ActivityListRow }) =>
    (order.get(a.activity.id) ?? 0) - (order.get(b.activity.id) ?? 0);
  studentRows.sort(byActivity);
  staffRows.sort(byActivity);

  const studentCols: Column<StudentExportRow>[] = [
    { header: 'Kode Kegiatan', key: 'code', value: (r) => r.activity.code },
    { header: 'Nama Kegiatan', key: 'name', value: (r) => r.activity.name },
    { header: 'Jenis', key: 'type', value: (r) => r.activity.type_name },
    { header: 'Arah', key: 'dir', value: (r) => label(DIRECTION_LABEL, r.activity.direction) },
    { header: 'Tanggal Mulai', key: 'start', value: (r) => r.activity.start_date, format: 'date' },
    { header: 'Unit Pengaju', key: 'unit', value: (r) => r.activity.submitter_unit_name },
    { header: 'Versi', key: 'v', value: (r) => r.version, format: 'int' },
    { header: 'Status Versi', key: 'vs', value: (r) => (PSET_STATUS_LABEL as Record<string, string>)[r.version_status] ?? r.version_status },
    { header: 'Bagian (PETRA/Inbound)', key: 'section', value: (r) => (r.section === 'inbound' ? 'Inbound' : 'PETRA') },
    { header: 'NRP', key: 'nrp', value: (r) => r.nrp, format: 'text' },
    { header: 'Nama', key: 'fn', value: (r) => r.full_name },
    { header: 'Fakultas', key: 'fac', value: (r) => r.faculty_name },
    { header: 'Prodi', key: 'prodi', value: (r) => r.prodi_name },
    { header: 'Institusi Asal', key: 'home', value: (r) => r.home_institution },
    { header: 'No. Mahasiswa Asal', key: 'homeno', value: (r) => r.home_student_number, format: 'text' },
    { header: 'Negara Asal', key: 'homecc', value: (r) => r.home_country_code },
  ];
  const staffCols: Column<StaffExportRow>[] = [
    { header: 'Kode Kegiatan', key: 'code', value: (r) => r.activity.code },
    { header: 'Nama Kegiatan', key: 'name', value: (r) => r.activity.name },
    { header: 'Versi', key: 'v', value: (r) => r.version, format: 'int' },
    { header: 'ID Pegawai', key: 'eid', value: (r) => r.employee_id, format: 'text' },
    { header: 'Nama', key: 'fn', value: (r) => r.full_name },
    { header: 'Unit', key: 'unit', value: (r) => r.unit_name },
  ];

  const rowCount = studentRows.length + staffRows.length;
  const wb = createWorkbook();
  addInfoSheet(wb, {
    kind: 'participants',
    title: 'Daftar Peserta (data pribadi — UU PDP)',
    filters: [...describeActivityFilters(f, names), ['Versi peserta', versionMode === 'approved' ? 'Versi disetujui' : 'Versi terbaru (non-draf)']],
    generatedBy: generatedBy(user),
    generatedAt: new Date(),
    dataAsOf: 'Live (data saat ekspor)',
    rowCount,
    extra: [['Catatan', 'Berisi data pribadi. Ekspor ini dicatat (export_log).']],
  });
  addTableSheet(wb, 'Mahasiswa', studentCols, studentRows);
  addTableSheet(wb, 'Pegawai', staffCols, staffRows);
  return {
    workbook: wb,
    periodLabel: activitiesPeriodLabel(acts, f.ay),
    rowCount,
    containsPersonal: true,
    filters: { ...f, version: versionMode },
  };
}

// ---------------------------------------------------------------- kpi-summary
const SUMMARY_KPIS: DrilldownKpi[] = ['1.1', '1.19.S1', '1.19.24', '1.19.S8'];

async function buildKpiSummary({ tx, user, params }: ExportContext): Promise<ExportResult> {
  const p = scopedPeriod(user, params);
  const dash = await getDashboard(tx, p);
  const ddp: PeriodParams = { ...p, ay: dash.period.ay_id };
  const drills = await Promise.all(SUMMARY_KPIS.map((kpi) => getDrilldown(tx, { ...ddp, kpi })));
  const summary = summaryRows(dash.values);

  const wb = createWorkbook();
  addTableSheet(wb, 'Ringkasan', SUMMARY_COLUMNS, summary);
  let rowCount = summary.length;
  SUMMARY_KPIS.forEach((kpi, i) => {
    rowCount += addKpiSheet(wb, kpi, drills[i]!);
  });
  addInfoSheet(wb, {
    kind: 'kpi-summary',
    title: 'Ringkasan KPI',
    filters: periodFilters(dash.period, dash.scope.unit_name),
    generatedBy: generatedBy(user),
    generatedAt: new Date(),
    dataAsOf: dataAsOf(dash.period),
    rowCount,
  });
  return { workbook: wb, periodLabel: dash.period.label, rowCount, containsPersonal: false, filters: periodRecord(p) };
}

// ---------------------------------------------------------------- kpi-drilldown
async function buildKpiDrilldown({ tx, user, params }: ExportContext): Promise<ExportResult> {
  const p = scopedPeriod(user, params);
  const kpi = parseDrilldownKpi(getParam(params, 'kpi'));
  if (!kpi) throw new ExportParamError('Parameter kpi tidak valid.');
  const bucket = parseBucket(kpi, getParam(params, 'bucket'));
  if (p.snapshot && !can(user, 'export.snapshot')) delete p.snapshot;
  const dd = await getDrilldown(tx, { ...p, kpi, bucket });
  const wb = createWorkbook();
  const rowCount = addKpiSheet(wb, kpi, dd);
  addInfoSheet(wb, {
    kind: 'kpi-drilldown',
    title: `Rincian ${KPI_LABEL[kpi]}`,
    filters: [
      ...periodFilters(dd.period, dd.scope.unit_name),
      ['KPI', kpi],
      ['Kelompok', bucket ? (BUCKET_LABEL[bucket] ?? bucket) : 'Semua'],
    ],
    generatedBy: generatedBy(user),
    generatedAt: new Date(),
    dataAsOf: dataAsOf(dd.period),
    rowCount,
  });
  return { workbook: wb, periodLabel: dd.period.label, rowCount, containsPersonal: false, filters: { ...periodRecord(p), kpi, bucket: bucket ?? null } };
}

// ---------------------------------------------------------------- chart
type ChartRow = Record<string, string | number | null>;
const CHART_COLUMNS: Record<ChartKey, Column<ChartRow>[]> = {
  mobility_by_semester: [
    { header: 'Semester', key: 'label', value: (r) => r.label ?? null },
    { header: 'Inbound', key: 'inbound', value: (r) => r.inbound ?? null, format: 'int' },
    { header: 'Outbound', key: 'outbound', value: (r) => r.outbound ?? null, format: 'int' },
  ],
  by_country: [
    { header: 'Kode Negara', key: 'country_code', value: (r) => r.country_code ?? null },
    { header: 'Negara', key: 'country_name', value: (r) => r.country_name ?? null },
    { header: 'Jumlah Kegiatan', key: 'activities', value: (r) => r.activities ?? null, format: 'int' },
  ],
  by_unit: [
    { header: 'ID Unit', key: 'unit_id', value: (r) => r.unit_id ?? null, format: 'int' },
    { header: 'Unit', key: 'unit_name', value: (r) => r.unit_name ?? null },
    { header: 'Jumlah Kegiatan', key: 'activities', value: (r) => r.activities ?? null, format: 'int' },
  ],
  by_sdg: [
    { header: 'SDG', key: 'sdg_id', value: (r) => r.sdg_id ?? null, format: 'int' },
    { header: 'Nama SDG', key: 'name', value: (r) => r.name ?? null },
    { header: 'Jumlah Kegiatan', key: 'activities', value: (r) => r.activities ?? null, format: 'int' },
  ],
  realization_by_unit: [
    { header: 'ID Unit', key: 'unit_id', value: (r) => r.unit_id ?? null, format: 'int' },
    { header: 'Unit', key: 'unit_name', value: (r) => r.unit_name ?? null },
    { header: 'Terlaksana', key: 'numerator', value: (r) => r.numerator ?? null, format: 'int' },
    { header: 'Jumlah Kerja Sama', key: 'denominator', value: (r) => r.denominator ?? null, format: 'int' },
    { header: 'Persentase', key: 'pct', value: (r) => r.pct ?? null, format: 'pct' },
  ],
  top_partners: [
    { header: 'ID Mitra', key: 'partner_id', value: (r) => r.partner_id ?? null, format: 'int' },
    { header: 'Mitra', key: 'partner_name', value: (r) => r.partner_name ?? null },
    { header: 'Negara', key: 'country_code', value: (r) => r.country_code ?? null },
    { header: 'Jumlah Kegiatan', key: 'activities', value: (r) => r.activities ?? null, format: 'int' },
  ],
};

async function buildChart({ tx, user, params }: ExportContext): Promise<ExportResult> {
  const p = scopedPeriod(user, params);
  const chart = parseChartKey(getParam(params, 'chart'));
  if (!chart) throw new ExportParamError('Parameter chart tidak valid.');
  const dash = await getDashboard(tx, p);
  const charts = dash.values.charts as KpiCharts;
  const rows = ((charts[chart] ?? []) as unknown as ChartRow[]).slice();
  const wb = createWorkbook();
  addTableSheet(wb, CHART_LABEL[chart], CHART_COLUMNS[chart], rows);
  addInfoSheet(wb, {
    kind: 'chart',
    title: `Grafik: ${CHART_LABEL[chart]}`,
    filters: [...periodFilters(dash.period, dash.scope.unit_name), ['Grafik', CHART_LABEL[chart]]],
    generatedBy: generatedBy(user),
    generatedAt: new Date(),
    dataAsOf: dataAsOf(dash.period),
    rowCount: rows.length,
  });
  return { workbook: wb, periodLabel: dash.period.label, rowCount: rows.length, containsPersonal: false, filters: { ...periodRecord(p), chart } };
}

// ---------------------------------------------------------------- snapshot
function snapshotPeriod(kind: string): Period {
  return kind === 'ganjil_ytd' ? 'ganjil' : 'full';
}

async function buildSnapshot({ tx, user, params }: ExportContext): Promise<ExportResult> {
  const id = getParam(params, 'snapshot');
  if (!isUuid(id)) throw new ExportParamError('Parameter snapshot tidak valid.');
  const detail = await getSnapshotDetail(tx, id);
  const s = detail.snapshot;
  const p: PeriodParams = { ay: s.ay_id, period: snapshotPeriod(s.kind), snapshot: s.id };
  const drills = await Promise.all(SUMMARY_KPIS.map((kpi) => getDrilldown(tx, { ...p, kpi })));
  // Personal sheet only for roles allowed to see participant names (mobility team / io_admin).
  const withParticipants = user.role !== 'submitter' && user.role !== 'viewer' && can(user, 'export.participants');
  const participants = withParticipants ? await getKpiParticipantRows(tx, p) : [];

  const wb = createWorkbook();
  const summary = summaryRows(detail.values);
  addTableSheet(wb, 'Ringkasan', SUMMARY_COLUMNS, summary);
  let rowCount = summary.length;
  SUMMARY_KPIS.forEach((kpi, i) => {
    rowCount += addKpiSheet(wb, kpi, drills[i]!);
  });
  addTableSheet(wb, 'Tambahan Susulan', LATE_ADDITION_COLUMNS, detail.late_additions ?? []);
  addTableSheet(wb, 'Perubahan Pasca-Beku', POST_FREEZE_COLUMNS, detail.post_freeze_changes ?? []);
  rowCount += (detail.late_additions?.length ?? 0) + (detail.post_freeze_changes?.length ?? 0);
  if (withParticipants) {
    addTableSheet(
      wb,
      '1.1 Peserta',
      [
        { header: 'Kode Kegiatan', key: 'code', value: (r) => r.code },
        { header: 'Nama Kegiatan', key: 'name', value: (r) => r.name },
        { header: 'Arah', key: 'dir', value: (r) => label(DIRECTION_LABEL, r.direction) },
        { header: 'Grup Kegiatan', key: 'group', value: (r) => r.event_group_id },
        { header: 'Bagian (PETRA/Inbound)', key: 'section', value: (r) => (r.section === 'inbound' ? 'Inbound' : 'PETRA') },
        { header: 'NRP', key: 'nrp', value: (r) => r.nrp, format: 'text' },
        { header: 'Nama', key: 'fn', value: (r) => r.full_name },
        { header: 'Fakultas', key: 'fac', value: (r) => r.faculty_name },
        { header: 'Prodi', key: 'prodi', value: (r) => r.prodi_name },
        { header: 'Institusi Asal', key: 'home', value: (r) => r.home_institution },
        { header: 'Negara Asal', key: 'homecc', value: (r) => r.home_country_code },
        { header: 'Tanggal Mulai', key: 'start', value: (r) => r.start_date, format: 'date' },
        { header: 'Semester', key: 'sem', value: (r) => r.semester_label },
      ],
      participants,
    );
    rowCount += participants.length;
  }
  const settings = Object.entries(detail.settings_used ?? {})
    .map(([k, v]) => `${k}=${JSON.stringify(v)}`)
    .join('; ');
  addInfoSheet(wb, {
    kind: 'snapshot',
    title: `Snapshot KPI ${s.label}`,
    filters: [
      ['Snapshot', s.label],
      ['Tahun Akademik', s.ay_label],
      ['Jendela', `${formatDate(s.window_start)} – ${formatDate(s.window_end)}`],
      ['Cutoff', formatDate(s.cutoff_date)],
    ],
    generatedBy: generatedBy(user),
    generatedAt: new Date(),
    dataAsOf: snapshotAsOf(s),
    rowCount,
    extra: [
      ['Dibekukan pada', formatDateTime(s.frozen_at)],
      ['Dibekukan oleh', s.frozen_by_name ?? 'Job terjadwal'],
      ['Status', s.is_live ? 'Berlaku' : `Digantikan (oleh ${s.superseded_by ?? '–'})`],
      ['Alasan bekukan ulang', s.refreeze_reason ?? '–'],
      ['Pengaturan yang dipakai', settings || '–'],
      ['Sheet 1.1 Peserta', withParticipants ? 'Disertakan (data pribadi, dicatat)' : 'Tidak disertakan untuk peran Anda'],
    ],
  });
  return {
    workbook: wb,
    periodLabel: s.label,
    rowCount,
    containsPersonal: withParticipants,
    filters: { snapshot: s.id },
  };
}

// ---------------------------------------------------------------- snapshot-archive
async function buildSnapshotArchive({ tx, user, params }: ExportContext): Promise<ExportResult> {
  const ay = parsePositiveInt(getParam(params, 'ay'));
  const rows = await getSnapshotList(tx, ay);
  const wb = createWorkbook();
  addTableSheet(wb, 'Arsip Snapshot', SNAPSHOT_ARCHIVE_COLUMNS, rows);
  const ayLabel = ay !== undefined ? (rows[0]?.ay_label ?? `TA-${ay}`) : 'Semua';
  addInfoSheet(wb, {
    kind: 'snapshot-archive',
    title: 'Arsip Snapshot KPI',
    filters: [['Tahun Akademik', ayLabel]],
    generatedBy: generatedBy(user),
    generatedAt: new Date(),
    dataAsOf: 'Daftar snapshot saat ekspor',
    rowCount: rows.length,
  });
  return { workbook: wb, periodLabel: ayLabel, rowCount: rows.length, containsPersonal: false, filters: { ay: ay ?? null } };
}

// ---------------------------------------------------------------- realization-by-agreement
async function buildRealization({ tx, user, params }: ExportContext): Promise<ExportResult> {
  const p = scopedPeriod(user, params);
  const status = parseRealizationStatus(getParam(params, 'status'));
  const dd = await getDrilldown(tx, { ...p, kpi: '1.19.24', bucket: realizationStatusToBucket(status) });
  const rows = (dd.rows as unknown[]).filter(isChainRow) as ChainKpiRow[];
  const wb = createWorkbook();
  addTableSheet(wb, 'Realisasi per Kerja Sama', REALIZATION_COLUMNS, rows);
  addInfoSheet(wb, {
    kind: 'realization-by-agreement',
    title: 'Realisasi per Kerja Sama (1.19.24)',
    filters: [...periodFilters(dd.period, dd.scope.unit_name), ['Status', status ? (CHAIN_STATUS_LABEL[status] ?? status) : 'Semua']],
    generatedBy: generatedBy(user),
    generatedAt: new Date(),
    dataAsOf: dataAsOf(dd.period),
    rowCount: rows.length,
  });
  return { workbook: wb, periodLabel: dd.period.label, rowCount: rows.length, containsPersonal: false, filters: { ...periodRecord(p), status: status ?? null } };
}

// ---------------------------------------------------------------- sla
interface SlaRow {
  a: ActivityListRow;
  track: 'partnership' | 'mobility';
  status: string;
  since: string | null;
  days: number | null;
  level: string | null;
}
const SLA_LEVEL_LABEL: Record<string, string> = { ok: 'Normal', yellow: 'Kuning', red: 'Merah' };

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

async function buildSla({ tx, user, params }: ExportContext): Promise<ExportResult> {
  const f = parseActivityFilters(params);
  const [acts, names, settings] = await Promise.all([listActivities(tx, user, f), nameLookups(tx), getSettingsMap(tx)]);
  const yellow = Number(settings.sla_yellow_days ?? 3);
  const red = Number(settings.sla_red_days ?? 5);
  const rows = slaRows(acts);
  const cols: Column<SlaRow>[] = [
    { header: 'Kode', key: 'code', value: (r) => r.a.code },
    { header: 'Nama', key: 'name', value: (r) => r.a.name },
    { header: 'Unit', key: 'unit', value: (r) => r.a.submitter_unit_name },
    { header: 'Jalur', key: 'track', value: (r) => label(TRACK_LABEL, r.track) },
    { header: 'Status Jalur', key: 'status', value: (r) => (TRACK_STATUS_LABEL as Record<string, string>)[r.status] ?? r.status },
    { header: 'Sejak', key: 'since', value: (r) => r.since, format: 'datetime' },
    { header: 'Hari Kerja', key: 'days', value: (r) => r.days, format: 'int' },
    { header: 'Level (Normal/Kuning/Merah)', key: 'level', value: (r) => (r.level ? (SLA_LEVEL_LABEL[r.level] ?? r.level) : null) },
    { header: 'Ambang Kuning', key: 'y', value: () => yellow, format: 'int' },
    { header: 'Ambang Merah', key: 'r', value: () => red, format: 'int' },
  ];
  const wb = createWorkbook();
  addTableSheet(wb, 'SLA Verifikasi', cols, rows);
  addInfoSheet(wb, {
    kind: 'sla',
    title: 'SLA Verifikasi',
    filters: describeActivityFilters(f, names),
    generatedBy: generatedBy(user),
    generatedAt: new Date(),
    dataAsOf: 'Live (data saat ekspor)',
    rowCount: rows.length,
    extra: [['Catatan', 'Hari kerja dihitung hanya selama jalur berstatus Menunggu (tidak termasuk akhir pekan dan hari libur).']],
  });
  return { workbook: wb, periodLabel: activitiesPeriodLabel(acts, f.ay), rowCount: rows.length, containsPersonal: false, filters: { ...f } };
}

// ---------------------------------------------------------------- known-activities
async function buildKnown({ tx, user, params }: ExportContext): Promise<ExportResult> {
  const f = parseKnownFilters(params);
  const rows = await listKnownActivities(tx, f);
  const cols: Column<KnownActivityRow>[] = [
    { header: 'ID', key: 'id', value: (r) => r.id, format: 'int' },
    { header: 'Tanggal', key: 'date', value: (r) => r.activity_date, format: 'date' },
    { header: 'Judul', key: 'title', value: (r) => r.title },
    { header: 'Unit', key: 'unit', value: (r) => r.unit_name },
    { header: 'Mitra', key: 'partner', value: (r) => r.partner_name },
    { header: 'Negara', key: 'country', value: (r) => r.country_name ?? r.country_code },
    { header: 'Internasional', key: 'intl', value: (r) => yesNo(r.is_international) },
    { header: 'Sumber', key: 'source', value: (r) => label(KNOWN_SOURCE_LABEL, r.source) },
    { header: 'Referensi', key: 'ref', value: (r) => r.source_reference },
    { header: 'Status', key: 'status', value: (r) => label(KNOWN_STATUS_LABEL, r.status) },
    { header: 'Kegiatan SIM (Kode)', key: 'match', value: (r) => r.matched_activity_code },
    { header: 'Diingatkan', key: 'nudged', value: (r) => r.nudged_at, format: 'datetime' },
    { header: 'Dicatat oleh', key: 'by', value: (r) => r.created_by_name },
    { header: 'Dicatat pada', key: 'at', value: (r) => r.created_at, format: 'datetime' },
  ];
  const filters: Array<[string, string]> = [];
  if (f.q) filters.push(['Pencarian', f.q]);
  if (f.status) filters.push(['Status', label(KNOWN_STATUS_LABEL, f.status) ?? f.status]);
  if (f.unit_id) filters.push(['Unit', String(rows.find((r) => r.unit_id === f.unit_id)?.unit_name ?? f.unit_id)]);
  if (f.intl !== undefined) filters.push(['Internasional', yesNo(f.intl)]);
  if (f.from) filters.push(['Dari tanggal', formatDate(f.from)]);
  if (f.to) filters.push(['Sampai tanggal', formatDate(f.to)]);
  const wb = createWorkbook();
  addTableSheet(wb, 'Register', cols, rows);
  addInfoSheet(wb, {
    kind: 'known-activities',
    title: 'Register Kegiatan Diketahui',
    filters,
    generatedBy: generatedBy(user),
    generatedAt: new Date(),
    dataAsOf: 'Live (data saat ekspor)',
    rowCount: rows.length,
  });
  return { workbook: wb, periodLabel: 'register', rowCount: rows.length, containsPersonal: false, filters: { ...f } };
}

// ---------------------------------------------------------------- duplicates
async function buildDuplicates({ tx, user, params }: ExportContext): Promise<ExportResult> {
  const raw = getParam(params, 'status');
  const status = raw === 'open' || raw === 'linked' || raw === 'dismissed' ? raw : undefined;
  const rows = await listDuplicateCandidates(tx, status ? { status } : {});
  const cols: Column<DuplicateCandidateRow>[] = [
    { header: 'Skor', key: 'score', value: (r) => r.score, format: 'decimal' },
    { header: 'Kode A', key: 'ac', value: (r) => r.a_code },
    { header: 'Nama A', key: 'an', value: (r) => r.a_name },
    { header: 'Unit A', key: 'au', value: (r) => r.a_unit_name },
    { header: 'Tanggal A', key: 'ad', value: (r) => r.a_start_date, format: 'date' },
    { header: 'Kode B', key: 'bc', value: (r) => r.b_code },
    { header: 'Nama B', key: 'bn', value: (r) => r.b_name },
    { header: 'Unit B', key: 'bu', value: (r) => r.b_unit_name },
    { header: 'Tanggal B', key: 'bd', value: (r) => r.b_start_date, format: 'date' },
    { header: 'Status', key: 'status', value: (r) => label(DUP_STATUS_LABEL, r.status) },
    { header: 'Diselesaikan oleh', key: 'by', value: (r) => r.resolved_by_name },
    { header: 'Diselesaikan pada', key: 'at', value: (r) => r.resolved_at, format: 'datetime' },
  ];
  const wb = createWorkbook();
  addTableSheet(wb, 'Kandidat Duplikat', cols, rows);
  addInfoSheet(wb, {
    kind: 'duplicates',
    title: 'Kandidat Duplikat',
    filters: [['Status', status ? (label(DUP_STATUS_LABEL, status) ?? status) : label(DUP_STATUS_LABEL, 'open') ?? 'Terbuka']],
    generatedBy: generatedBy(user),
    generatedAt: new Date(),
    dataAsOf: 'Live (data saat ekspor)',
    rowCount: rows.length,
  });
  return { workbook: wb, periodLabel: status ?? 'open', rowCount: rows.length, containsPersonal: false, filters: { status: status ?? 'open' } };
}

// ---------------------------------------------------------------- agreement-activities
async function buildAgreementActivities({ tx, user, params }: ExportContext): Promise<ExportResult> {
  const documentId = parsePositiveInt(getParam(params, 'document_id'));
  if (documentId === undefined) throw new ExportParamError('Parameter document_id tidak valid.');
  const ar = await getAgreementRealization(tx, documentId);
  type Row = (typeof ar.activities)[number];
  const cols: Column<Row>[] = [
    { header: 'Kode', key: 'code', value: (r) => r.code },
    { header: 'Nama', key: 'name', value: (r) => r.name },
    { header: 'Jenis', key: 'type', value: (r) => r.type_name },
    { header: 'Tanggal Mulai', key: 'start', value: (r) => r.start_date, format: 'date' },
    { header: 'Tanggal Selesai', key: 'end', value: (r) => r.end_date, format: 'date' },
    { header: 'Status', key: 'status', value: (r) => label(ACTIVITY_STATUS_LABEL, r.status) },
    { header: 'Unit', key: 'unit', value: (r) => joinList(r.unit_names) },
    { header: 'Dokumen saat Kegiatan', key: 'orig', value: (r) => r.original_doc_number },
    { header: 'Dokumen Saat Ini', key: 'cur', value: (r) => r.current_doc_number },
  ];
  const rows = ar.activities ?? [];
  const wb = createWorkbook();
  addTableSheet(wb, 'Realisasi Kerja Sama', cols, rows);
  addInfoSheet(wb, {
    kind: 'agreement-activities',
    title: `Realisasi Kerja Sama ${ar.document.doc_number}`,
    filters: [
      ['Dokumen', `${ar.document.doc_number} — ${ar.document.title}`],
      ['Rantai perpanjangan', (ar.chain.documents ?? []).map((d) => d.doc_number).join(' → ')],
    ],
    generatedBy: generatedBy(user),
    generatedAt: new Date(),
    dataAsOf: 'Live (data saat ekspor)',
    rowCount: rows.length,
  });
  return { workbook: wb, periodLabel: ar.document.doc_number, rowCount: rows.length, containsPersonal: false, filters: { document_id: documentId } };
}

export const EXPORTS: Record<ExportKind, ExportDef> = {
  activities: { allowed: everyone, build: buildActivities },
  participants: { allowed: (u) => can(u, 'export.participants'), build: buildParticipants },
  'kpi-summary': { allowed: everyone, build: buildKpiSummary },
  'kpi-drilldown': { allowed: everyone, build: buildKpiDrilldown },
  chart: { allowed: everyone, build: buildChart },
  snapshot: { allowed: (u) => can(u, 'export.snapshot'), build: buildSnapshot },
  'snapshot-archive': { allowed: (u) => can(u, 'export.snapshot'), build: buildSnapshotArchive },
  'realization-by-agreement': { allowed: everyone, build: buildRealization },
  sla: { allowed: everyone, build: buildSla },
  'known-activities': { allowed: (u) => can(u, 'export.known'), build: buildKnown },
  duplicates: { allowed: (u) => can(u, 'export.duplicates'), build: buildDuplicates },
  'agreement-activities': { allowed: everyone, build: buildAgreementActivities },
};

export function isExportKind(k: string): k is ExportKind {
  return Object.prototype.hasOwnProperty.call(EXPORTS, k);
}
