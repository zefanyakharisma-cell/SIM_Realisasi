// Read-model queries for the dashboard, Laporan page, exports and SIM Kerjasama tab.
// Never compute KPIs here — every number comes from the SQL read RPCs (CONTRACTS §3.9, §6.7).
import type { Tx } from '@/lib/db';
import type {
  AgreementFlag,
  AgreementRealization,
  DashboardData,
  DrilldownKpi,
  DrilldownResult,
  KpiParticipantRow,
  PeriodInfo,
  SnapshotDetail,
  SnapshotListRow,
} from '@/lib/realisasi/types';
import type { PeriodParams } from '@/lib/realisasi/schemas/report';

export async function getDashboard(tx: Tx, p: PeriodParams): Promise<DashboardData> {
  const [row] = await tx`
    select realisasi.dashboard(${p.ay ?? null}::int, ${p.period}::text, ${p.unit ?? null}::int) as r`;
  return row!.r as DashboardData;
}

/** AY id to use when the URL has none: the AY containing today(), else the latest. */
export async function resolveAyId(tx: Tx, ay?: number): Promise<number | null> {
  if (ay !== undefined) return ay;
  const rows = await tx`
    select id from (
      select id, 0 as prio, start_date from realisasi.academic_years
       where realisasi.today() between start_date and end_date
      union all
      select id, 1 as prio, start_date from realisasi.academic_years
    ) x order by prio, start_date desc limit 1`;
  return rows[0] ? Number(rows[0].id) : null;
}

export async function getPeriodInfo(tx: Tx, p: PeriodParams): Promise<PeriodInfo> {
  const ay = await resolveAyId(tx, p.ay);
  const [row] = await tx`select realisasi.period_info(${ay}::int, ${p.period}::text) as r`;
  return row!.r as PeriodInfo;
}

export async function getDrilldown(
  tx: Tx,
  p: PeriodParams & { kpi: DrilldownKpi; bucket?: string },
): Promise<DrilldownResult> {
  const ay = p.snapshot ? (p.ay ?? null) : await resolveAyId(tx, p.ay);
  const [row] = await tx`
    select realisasi.kpi_drilldown(${ay}::int, ${p.period}::text, ${p.kpi}::text, ${p.bucket ?? null}::text,
                                   ${p.unit ?? null}::int, ${p.snapshot ?? null}::uuid) as r`;
  return row!.r as DrilldownResult;
}

export async function getKpiParticipantRows(tx: Tx, p: PeriodParams): Promise<KpiParticipantRow[]> {
  const ay = p.snapshot ? (p.ay ?? null) : await resolveAyId(tx, p.ay);
  const [row] = await tx`
    select realisasi.kpi_participant_rows(${ay}::int, ${p.period}::text, ${p.unit ?? null}::int,
                                          ${p.snapshot ?? null}::uuid) as r`;
  return (row!.r ?? []) as KpiParticipantRow[];
}

export async function getSnapshotList(tx: Tx, ay?: number): Promise<SnapshotListRow[]> {
  const [row] = await tx`select realisasi.snapshot_list(${ay ?? null}::int) as r`;
  return (row!.r ?? []) as SnapshotListRow[];
}

export async function getSnapshotDetail(tx: Tx, id: string): Promise<SnapshotDetail> {
  const [row] = await tx`select realisasi.snapshot_detail(${id}::uuid) as r`;
  return row!.r as SnapshotDetail;
}

export async function getAgreementRealization(tx: Tx, documentId: number): Promise<AgreementRealization> {
  const [row] = await tx`select realisasi.agreement_realization(${documentId}::int) as r`;
  return row!.r as AgreementRealization;
}

export async function getAgreementFlags(tx: Tx, ay?: number): Promise<AgreementFlag[]> {
  const [row] = await tx`select realisasi.agreement_flags(${ay ?? null}::int) as r`;
  return (row!.r ?? []) as AgreementFlag[];
}

export interface AcademicYearRow {
  id: number;
  label: string;
  start_date: string;
  end_date: string;
}

export async function listAcademicYears(tx: Tx): Promise<AcademicYearRow[]> {
  const rows = await tx`select id, label, start_date, end_date from realisasi.academic_years order by start_date`;
  return rows.map((r) => ({
    id: Number(r.id),
    label: String(r.label),
    start_date: String(r.start_date),
    end_date: String(r.end_date),
  }));
}

export interface UnitOption {
  id: number;
  name: string;
  kind: string;
}

export async function listUnits(tx: Tx): Promise<UnitOption[]> {
  const rows = await tx`select id, name, kind from public.units order by name`;
  return rows.map((r) => ({ id: Number(r.id), name: String(r.name), kind: String(r.kind) }));
}

/** Integer settings used for SLA thresholds etc. */
export async function getSettingsMap(tx: Tx): Promise<Record<string, unknown>> {
  const rows = await tx`select key, value from realisasi.settings`;
  return Object.fromEntries(rows.map((r) => [String(r.key), r.value as unknown]));
}

export interface DocumentListRow {
  id: number;
  doc_number: string;
  title: string;
  kind: string;
  status: string;
  start_date: string | null;
  end_date: string | null;
  auto_renewed: boolean;
  predecessor_id: number | null;
  partner_names: string[];
  country_codes: string[];
}

/** Minimal SIM Kerjasama document list (public stub tables are readable by authenticated). */
export async function listDocuments(tx: Tx): Promise<DocumentListRow[]> {
  const rows = await tx`
    select d.id, d.doc_number, d.title, d.kind, d.status, d.start_date, d.end_date, d.auto_renewed, d.predecessor_id,
           coalesce(array_agg(p.name order by dp.is_lead desc, p.name) filter (where p.id is not null), '{}') as partner_names,
           coalesce(array_agg(distinct p.country_code) filter (where p.id is not null), '{}') as country_codes
      from public.documents d
      left join public.document_partners dp on dp.document_id = d.id
      left join public.partners p on p.id = dp.partner_id
     group by d.id
     order by d.doc_number`;
  return rows.map((r) => ({
    id: Number(r.id),
    doc_number: String(r.doc_number),
    title: String(r.title),
    kind: String(r.kind),
    status: String(r.status),
    start_date: (r.start_date as string | null) ?? null,
    end_date: (r.end_date as string | null) ?? null,
    auto_renewed: Boolean(r.auto_renewed),
    predecessor_id: r.predecessor_id === null ? null : Number(r.predecessor_id),
    partner_names: (r.partner_names as string[]) ?? [],
    country_codes: (r.country_codes as string[]) ?? [],
  }));
}
