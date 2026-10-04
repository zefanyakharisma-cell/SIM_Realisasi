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
  KpiCharts,
  PeriodInfo,
  Period,
} from '@/lib/realisasi/types';
import {
  ACTIVITY_STATUS_LABEL,
  CONFLICT_STATUS_LABEL,
  PSET_STATUS_LABEL,
  DIRECTION_LABEL,
} from '@/lib/realisasi/status';
import { formatDate, formatDateTime } from '@/lib/realisasi/format';
import { parseActivityFilters, describeActivityFilters } from '@/lib/realisasi/schemas/filters';
import { listActivities } from '@/lib/realisasi/queries/activities';
import {
  CHART_LABEL,
  getParam,
  isUuid,
  parseChartKey,
  parsePeriodParams,
  parsePositiveInt,
  parseRealizationStatus,
  parseRenstraParams,
  realizationStatusToBucket,
  renstraLabel,
  type ChartKey,
  type RenstraDef,
  type PeriodParams,
} from '@/lib/realisasi/schemas/report';
import {
  getAgreementRealization,
  getAwards,
  getConflicts,
  getDashboard,
  getDrilldown,
  getKpiParticipantRows,
  getSnapshotDetail,
  getSnapshotList,
} from '@/lib/realisasi/queries/reports';
import { addInfoSheet, addTableSheet, createWorkbook, type Column } from '@/lib/excel/workbook';
import {
  ACTIVITY_COLUMNS,
  AWARDS_INITIATIVE_COLUMNS,
  AWARDS_STUDENT_COLUMNS,
  CHAIN_STATUS_LABEL,
  CONFLICT_COLUMNS,
  LATE_ADDITION_COLUMNS,
  POST_FREEZE_COLUMNS,
  REALIZATION_COLUMNS,
  SNAPSHOT_ARCHIVE_COLUMNS,
  KPI_11_COLUMNS,
  KPI_24_COLUMNS,
  KPI_PARTICIPANT_COLUMNS,
  KPI_S1_COLUMNS,
  KPI_S4_OVERALL_COLUMNS,
  SUMMARY_COLUMNS,
  addKpiSheet,
  dataAsOf,
  isChainRow,
  joinList,
  label,
  ranked,
  rollupColumns,
  rollupSheetRows,
  snapshotAsOf,
  summaryRows,
  withFacultyColumn,
} from '@/lib/excel/sheets';
import { getRenstraReport } from '@/lib/realisasi/queries/renstra';

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
  const [agendas, units, years, sems] = await Promise.all([
    tx`select id, name from kerjasama.agendas`,
    tx`select id, name from kerjasama.units`,
    tx`select id, label as name from realisasi.academic_years`,
    tx`select id, realisasi.semester_label(id) as name from realisasi.semesters`,
  ]);
  const toOpts = (rows: typeof agendas) => rows.map((r) => ({ id: Number(r.id), name: String(r.name) }));
  return {
    agendaName: lookupName(toOpts(agendas)),
    unitName: lookupName(toOpts(units)),
    ayLabel: lookupName(toOpts(years)),
    semesterLabel: lookupName(toOpts(sems)),
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
    { header: 'Jenis', key: 'type', value: (r) => r.activity.agenda_name },
    { header: 'Inbound/Outbound', key: 'dir', value: (r) => label(DIRECTION_LABEL, r.activity.direction) },
    { header: 'Tanggal Mulai', key: 'start', value: (r) => r.activity.start_date, format: 'date' },
    { header: 'Unit Pengaju', key: 'unit', value: (r) => r.activity.submitter_unit_name },
    { header: 'Versi', key: 'v', value: (r) => r.version, format: 'int' },
    { header: 'Status Versi', key: 'vs', value: (r) => (PSET_STATUS_LABEL as Record<string, string>)[r.version_status] ?? r.version_status },
    { header: 'Bagian (PETRA/Inbound)', key: 'section', value: (r) => (r.section === 'inbound' ? 'Inbound' : 'PETRA') },
    { header: 'NRP', key: 'nrp', value: (r) => r.nrp, format: 'text' },
    { header: 'Nama', key: 'fn', value: (r) => r.full_name },
    { header: 'Fakultas', key: 'fac', value: (r) => r.faculty_name },
    { header: 'Program Studi', key: 'prodi', value: (r) => r.prodi_name },
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
const SUMMARY_KPIS: DrilldownKpi[] = ['1.1', '1.19.S1', '1.19.24'];

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
    title: 'Ringkasan Capaian RENSTRA',
    filters: periodFilters(dash.period, dash.scope.unit_name),
    generatedBy: generatedBy(user),
    generatedAt: new Date(),
    dataAsOf: dataAsOf(dash.period),
    rowCount,
  });
  return { workbook: wb, periodLabel: dash.period.label, rowCount, containsPersonal: false, filters: periodRecord(p) };
}

// ---------------------------------------------------------------- kpi-drilldown (Laporan per RENSTRA, Revisi V.2)
// Sheet 1 = the RENSTRA table (per unit, or the overall % for 1.19.S4), sheet 2 = the Kegiatan / kerja sama behind it,
// sheet 3 = the students (1.1 family, roles allowed to export participants), Info last.
const RENSTRA_VALUE_HEADER: Record<RenstraDef['unit'], string> = { mahasiswa: 'Jumlah Mahasiswa', kegiatan: 'Jumlah Kegiatan', persen: 'Persentase' };

async function buildKpiDrilldown({ tx, user, params }: ExportContext): Promise<ExportResult> {
  const p = scopedPeriod(user, params);
  const key = parseRenstraParams(params);
  if (!key) throw new ExportParamError('Parameter renstra tidak valid.');
  if (p.snapshot && !can(user, 'export.snapshot')) delete p.snapshot;
  const rep = await getRenstraReport(tx, user, p, key);
  const def = rep.def;
  const scopeName = rep.scope.unit_name ?? 'Universitas';
  const wb = createWorkbook();
  let rowCount = 0;

  // Sheet 1: Rekap
  if (rep.rollup) {
    const rows = rollupSheetRows(rep.rollup, `Total ${scopeName}`, rep.scopeValue);
    const ws = addTableSheet(wb, `${key} Rekap`, rollupColumns(RENSTRA_VALUE_HEADER[def.unit]), rows);
    rows.forEach((r, i) => {
      if (r.level === 'Fakultas' || r.isTotal) ws.getRow(i + 2).font = { bold: true };
    });
    rowCount += rep.rollup.length;
  } else {
    const t = rep.overall!;
    addTableSheet(wb, `${key} Rekap`, KPI_S4_OVERALL_COLUMNS, [
      { desc: `${def.title} — ${scopeName}`, num: t.numerator, den: t.denominator, grace: t.grace_excluded, pct: t.pct },
    ]);
    rowCount += 1;
  }

  // Sheet 2: Data
  if (def.kpi === '1.19.24') {
    addTableSheet(wb, `${key} Data`, KPI_24_COLUMNS, rep.chainRows);
    rowCount += rep.chainRows.length;
  } else {
    const cols = withFacultyColumn(def.kpi === '1.1' ? KPI_11_COLUMNS : KPI_S1_COLUMNS, rep.facultyOf);
    addTableSheet(wb, `${key} Data`, cols, rep.activityRows);
    rowCount += rep.activityRows.length;
  }

  // Sheet 3: Mahasiswa (personal data, logged)
  const withStudents = def.kpi === '1.1' && user.role !== 'submitter' && user.role !== 'viewer' && can(user, 'export.participants');
  if (withStudents) {
    const ids = new Set(rep.activityRows.map((r) => r.activity_id));
    const students = (await getKpiParticipantRows(tx, { ...p, unit: undefined })).filter(
      (s) => ids.has(s.activity_id) && (!def.bucket || s.direction === def.bucket),
    );
    addTableSheet(wb, `${key} Mahasiswa`, KPI_PARTICIPANT_COLUMNS, students);
    rowCount += students.length;
  }

  addInfoSheet(wb, {
    kind: 'kpi-drilldown',
    title: `RENSTRA ${renstraLabel(key)}`,
    filters: periodFilters(rep.period, rep.scope.unit_name),
    generatedBy: generatedBy(user),
    generatedAt: new Date(),
    dataAsOf: dataAsOf(rep.period),
    rowCount,
    position: 'last',
    extra: [
      ...(rep.rollup
        ? ([
            ['Nilai per unit', 'Fakultas = kegiatan unit sendiri + total Program Studi; Program Studi = unit sendiri + total Program'],
            ['Kegiatan bersama', 'Kegiatan dengan beberapa unit dihitung pada setiap unit yang terlibat; total lingkup dihitung sekali'],
          ] as Array<[string, string]>)
        : ([['Perhitungan', 'Satuan = rantai perpanjangan MoU/MoA; masa tenggang dikecualikan dari penyebut']] as Array<[string, string]>)),
      ...(def.kpi === '1.1'
        ? ([[`Sheet ${key} Mahasiswa`, withStudents ? 'Disertakan (data pribadi, dicatat)' : 'Tidak disertakan untuk peran Anda']] as Array<[string, string]>)
        : []),
    ],
  });
  return {
    workbook: wb,
    periodLabel: `${key}-${rep.period.label}`,
    rowCount,
    containsPersonal: withStudents,
    filters: { ...periodRecord(p), renstra: key },
  };
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
      KPI_PARTICIPANT_COLUMNS,
      participants,
    );
    rowCount += participants.length;
  }
  const settings = Object.entries(detail.settings_used ?? {})
    .map(([k, v]) => `${k}=${JSON.stringify(v)}`)
    .join('; ');
  addInfoSheet(wb, {
    kind: 'snapshot',
    title: `Snapshot Capaian RENSTRA ${s.label}`,
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
    title: 'Arsip Snapshot Capaian RENSTRA',
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
    title: 'Realisasi per Kerja Sama (1.19.S4)',
    filters: [...periodFilters(dd.period, dd.scope.unit_name), ['Status', status ? (CHAIN_STATUS_LABEL[status] ?? status) : 'Semua']],
    generatedBy: generatedBy(user),
    generatedAt: new Date(),
    dataAsOf: dataAsOf(dd.period),
    rowCount: rows.length,
  });
  return { workbook: wb, periodLabel: dd.period.label, rowCount: rows.length, containsPersonal: false, filters: { ...periodRecord(p), status: status ?? null } };
}

// ---------------------------------------------------------------- awards (Revisi V.1)
async function buildAwards({ tx, user, params }: ExportContext): Promise<ExportResult> {
  const p = scopedPeriod(user, params);
  delete p.snapshot;
  const aw = await getAwards(tx, p);
  const wb = createWorkbook();
  const boards: Array<[string, typeof aw.inbound]> = [
    ['Inbound Tertinggi', aw.inbound],
    ['Outbound DN Tertinggi', aw.outbound_domestic],
    ['Outbound Intl Tertinggi', aw.outbound_international],
  ];
  let rowCount = 0;
  for (const [name, rows] of boards) {
    addTableSheet(wb, name, AWARDS_STUDENT_COLUMNS, ranked(rows));
    rowCount += rows.length;
  }
  addTableSheet(wb, 'Inisiatif Intl Tertinggi', AWARDS_INITIATIVE_COLUMNS, ranked(aw.initiatives));
  rowCount += aw.initiatives.length;
  addInfoSheet(wb, {
    kind: 'awards',
    title: 'International Awards',
    filters: periodFilters(aw.period, aw.scope.unit_name),
    generatedBy: generatedBy(user),
    generatedAt: new Date(),
    dataAsOf: dataAsOf(aw.period),
    rowCount,
    extra: [
      ['Pengelompokan', 'Per unit pengaju kegiatan'],
      ['Dalam negeri / internasional', 'Menurut negara tempat kegiatan (Indonesia = dalam negeri)'],
      ['Kegiatan Internasional (<14 hari)', 'Mahasiswa kegiatan mobilitas lain yang berlangsung kurang dari 14 hari'],
    ],
  });
  return { workbook: wb, periodLabel: aw.period.label, rowCount, containsPersonal: false, filters: periodRecord(p) };
}

// ---------------------------------------------------------------- conflicts (Verifikasi Mobilitas)
async function buildConflicts({ tx, user, params }: ExportContext): Promise<ExportResult> {
  const raw = getParam(params, 'status');
  const status = raw === 'open' || raw === 'resolved' ? raw : raw === 'all' ? null : 'open';
  const rows = await getConflicts(tx, { status });
  const wb = createWorkbook();
  addTableSheet(wb, 'Duplikat Mahasiswa', CONFLICT_COLUMNS, rows);
  addInfoSheet(wb, {
    kind: 'conflicts',
    title: 'Duplikat Mahasiswa antar-Unit (data pribadi)',
    filters: [['Status', status ? (label(CONFLICT_STATUS_LABEL, status) ?? status) : 'Semua']],
    generatedBy: generatedBy(user),
    generatedAt: new Date(),
    dataAsOf: 'Live (data saat ekspor)',
    rowCount: rows.length,
    extra: [['Catatan', 'Berisi NRP dan nama mahasiswa. Ekspor ini dicatat (export_log).']],
  });
  return { workbook: wb, periodLabel: status ?? 'semua', rowCount: rows.length, containsPersonal: true, filters: { status: status ?? 'all' } };
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
    { header: 'Jenis', key: 'type', value: (r) => r.agenda_name },
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
      ['Rantai perpanjangan', (ar.chain?.documents ?? []).map((d) => d.doc_number).join(' → ')],
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
  awards: { allowed: everyone, build: buildAwards },
  conflicts: { allowed: (u) => can(u, 'export.conflicts'), build: buildConflicts },
  'agreement-activities': { allowed: everyone, build: buildAgreementActivities },
};

export function isExportKind(k: string): k is ExportKind {
  return Object.prototype.hasOwnProperty.call(EXPORTS, k);
}
