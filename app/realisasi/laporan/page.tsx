// Laporan & Ekspor (Design §3.8). Left: report list per role; right: filters + preview + Unduh Excel.
// The export link always carries the page's own searchParams, so the workbook = the preview (AT-12).
import Link from 'next/link';
import { AlertTriangle } from 'lucide-react';
import { withUser, type Tx } from '@/lib/db';
import { can, requireUser, type SessionUser } from '@/lib/session';
import { parseDbError } from '@/lib/realisasi/errors';
import { formatDate, formatNumber } from '@/lib/realisasi/format';
import { KNOWN_SOURCE_LABEL, KNOWN_STATUS_LABEL, SLA_LEVEL_LABEL, TRACK_LABEL, TRACK_STATUS_LABEL } from '@/lib/realisasi/status';
import type { ActivityListRow, ChainKpiRow, ExportKind, SlaLevel } from '@/lib/realisasi/types';
import { parseActivityFilters } from '@/lib/realisasi/schemas/filters';
import { listActivities } from '@/lib/realisasi/queries/activities';
import { parseKnownFilters } from '@/lib/realisasi/schemas/known';
import { listKnownActivities } from '@/lib/realisasi/queries/known';
import {
  BUCKET_LABEL,
  DRILLDOWN_BUCKETS,
  KPI_LABEL,
  getParam,
  isUuid,
  parseBucket,
  parseDrilldownKpi,
  parsePeriodParams,
  parsePositiveInt,
  parseRealizationStatus,
  parseReportKey,
  realizationStatusToBucket,
  type ReportKey,
} from '@/lib/realisasi/schemas/report';
import {
  getDashboard,
  getDrilldown,
  getSnapshotDetail,
  getSnapshotList,
  listAcademicYears,
  listActivityTypes,
  listUnits,
} from '@/lib/realisasi/queries/reports';
import { slaRows } from '@/lib/excel/sheets';
import { PageHeader } from '@/components/realisasi/page-header';
import { ExportButton } from '@/components/realisasi/export-button';
import { Forbidden } from '@/components/realisasi/forbidden';
import { StatusBadge } from '@/components/realisasi/status-badge';
import { Badge } from '@/components/ui/badge';
import { Card } from '@/components/ui/card';
import { Label } from '@/components/ui/label';
import { NativeSelect } from '@/components/ui/native-select';
import { Button } from '@/components/ui/button';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { PeriodSelector } from '@/components/realisasi/dashboard/period-selector';
import { PeriodBadge } from '@/components/realisasi/dashboard/period-badge';
import { ChainKpiTable, DrilldownTables, EmptyRows, SummaryTable } from '@/components/realisasi/reports/kpi-tables';
import { SnapshotDetailView, SnapshotTimeline } from '@/components/realisasi/reports/snapshot-archive';
import { ActivityFilterForm, KnownFilterForm } from '@/components/realisasi/reports/report-filters';
import { cn } from '@/lib/utils';

export const dynamic = 'force-dynamic';

type SP = Record<string, string | string[] | undefined>;
const PREVIEW_LIMIT = 50;

interface ReportDef {
  key: ReportKey;
  title: string;
  description: string;
  kind: ExportKind;
  visible: (u: SessionUser) => boolean;
}

const REPORTS: ReportDef[] = [
  { key: 'ringkasan', title: 'Ringkasan KPI', description: 'Nilai keempat KPI beserta rincian per KPI.', kind: 'kpi-summary', visible: () => true },
  { key: 'kpi', title: 'Rincian per KPI', description: 'Kegiatan/kerja sama yang membentuk satu KPI.', kind: 'kpi-drilldown', visible: () => true },
  { key: 'kegiatan', title: 'Daftar kegiatan', description: 'Seluruh kegiatan sesuai filter.', kind: 'activities', visible: () => true },
  { key: 'peserta', title: 'Daftar peserta', description: 'Nama & NRP peserta (data pribadi, dicatat).', kind: 'participants', visible: (u) => can(u, 'export.participants') },
  { key: 'register', title: 'Register kegiatan diketahui', description: 'Kegiatan dari sumber lain (register).', kind: 'known-activities', visible: (u) => can(u, 'export.known') },
  { key: 'realisasi-kerjasama', title: 'Realisasi per kerja sama', description: 'Status terlaksana tiap rantai MoU/MoA (1.19.24).', kind: 'realization-by-agreement', visible: () => true },
  { key: 'sla', title: 'SLA verifikasi', description: 'Lama verifikasi per jalur dalam hari kerja.', kind: 'sla', visible: () => true },
  { key: 'arsip', title: 'Arsip snapshot', description: 'Snapshot KPI yang dibekukan per semester.', kind: 'snapshot-archive', visible: (u) => can(u, 'snapshot.archive') },
];

/** Search params minus empties, for building the export link. */
function cleanParams(sp: SP, drop: string[] = []): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(sp)) {
    const val = Array.isArray(v) ? v[0] : v;
    if (val && !drop.includes(k)) out[k] = val;
  }
  return out;
}

export default async function LaporanPage(props: { searchParams: Promise<SP> }) {
  const user = await requireUser();
  const sp = await props.searchParams;
  const visible = REPORTS.filter((r) => r.visible(user));
  const key = parseReportKey(getParam(sp, 'report')) ?? 'ringkasan';
  const def = REPORTS.find((r) => r.key === key)!;
  const allowed = def.visible(user);

  let body: React.ReactNode;
  if (!allowed) {
    body = <Forbidden />;
  } else {
    try {
      body = await withUser(user.id, (tx) => renderReport(tx, user, key, sp));
    } catch (e) {
      const err = parseDbError(e);
      body = (
        <Card role="alert" className="flex items-start gap-3 border-red-200 bg-red-50 p-4 text-sm text-red-900">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
          <p>{err.message}</p>
        </Card>
      );
    }
  }

  return (
    <div>
      <PageHeader title="Laporan & Ekspor" description="Pilih laporan, atur filter, pratinjau, lalu unduh Excel." />
      <div className="grid gap-6 lg:grid-cols-[240px_minmax(0,1fr)]">
        <nav aria-label="Daftar laporan">
          <ul className="space-y-1">
            {visible.map((r) => (
              <li key={r.key}>
                <Link
                  href={`/realisasi/laporan?report=${r.key}`}
                  aria-current={r.key === key ? 'page' : undefined}
                  data-testid={`report-${r.key}`}
                  className={cn(
                    'block rounded-md px-3 py-2 text-sm hover:bg-accent',
                    r.key === key ? 'bg-primary/10 font-semibold text-primary' : 'text-foreground',
                  )}
                >
                  {r.title}
                  <span className="block text-xs font-normal text-muted-foreground">{r.description}</span>
                </Link>
              </li>
            ))}
          </ul>
        </nav>
        <section aria-labelledby="report-title" className="min-w-0 space-y-4">
          <h2 id="report-title" className="text-lg font-semibold">
            {def.title}
          </h2>
          {body}
        </section>
      </div>
    </div>
  );
}

async function renderReport(tx: Tx, user: SessionUser, key: ReportKey, sp: SP): Promise<React.ReactNode> {
  const isSubmitter = user.role === 'submitter';
  switch (key) {
    case 'ringkasan':
    case 'kpi':
    case 'realisasi-kerjasama':
      return renderKpiReport(tx, user, key, sp);
    case 'kegiatan':
    case 'peserta':
    case 'sla': {
      const f = parseActivityFilters(sp);
      const [rows, types, units, years] = await Promise.all([
        listActivities(tx, user, f),
        listActivityTypes(tx),
        isSubmitter ? Promise.resolve(null) : listUnits(tx),
        listAcademicYears(tx),
      ]);
      const kind: ExportKind = key === 'kegiatan' ? 'activities' : key === 'peserta' ? 'participants' : 'sla';
      const versionSel =
        key === 'peserta' ? (
          <div className="grid gap-1">
            <Label htmlFor="f-version" className="text-xs text-muted-foreground">
              Versi peserta
            </Label>
            <NativeSelect id="f-version" name="version" defaultValue={getParam(sp, 'version') === 'latest' ? 'latest' : 'approved'} className="w-44">
              <option value="approved">Versi disetujui</option>
              <option value="latest">Versi terbaru</option>
            </NativeSelect>
          </div>
        ) : null;
      return (
        <div className="space-y-4">
          <ActivityFilterForm
            report={key}
            filters={f}
            types={types.map((t) => ({ id: t.id, name: t.name }))}
            units={units ? units.map((u) => ({ id: u.id, name: u.name })) : null}
            years={years}
            extra={versionSel}
          />
          <Toolbar kind={kind} params={cleanParams(sp, ['report'])}>
            {key === 'sla' ? (
              <span>{formatNumber(slaRows(rows).length)} baris jalur verifikasi dari </span>
            ) : null}
            <span data-testid="list-total">{rows.length}</span> kegiatan
          </Toolbar>
          {key === 'peserta' ? (
            <p className="rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-900">
              Berkas berisi nama dan NRP peserta (data pribadi). Setiap unduhan dicatat sesuai UU PDP. Pratinjau di bawah menampilkan kegiatan yang pesertanya
              akan diekspor.
            </p>
          ) : null}
          {key === 'sla' ? <SlaPreview rows={rows} /> : <ActivityPreview rows={rows} />}
        </div>
      );
    }
    case 'register': {
      const f = parseKnownFilters(sp);
      const [rows, units] = await Promise.all([listKnownActivities(tx, f), listUnits(tx)]);
      return (
        <div className="space-y-4">
          <KnownFilterForm filters={f} units={units.map((u) => ({ id: u.id, name: u.name }))} />
          <Toolbar kind="known-activities" params={cleanParams(sp, ['report'])}>
            <span data-testid="list-total">{rows.length}</span> entri
          </Toolbar>
          {rows.length === 0 ? (
            <EmptyRows text="Belum ada kegiatan dicatat dari sumber lain." />
          ) : (
            <Table containerLabel="Register">
              <TableHeader>
                <TableRow>
                  <TableHead>Tanggal</TableHead>
                  <TableHead>Judul</TableHead>
                  <TableHead>Unit</TableHead>
                  <TableHead>Mitra · Negara</TableHead>
                  <TableHead>Sumber</TableHead>
                  <TableHead>Status</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.slice(0, PREVIEW_LIMIT).map((r) => (
                  <TableRow key={r.id}>
                    <TableCell className="whitespace-nowrap">{formatDate(r.activity_date)}</TableCell>
                    <TableCell className="font-medium">{r.title}</TableCell>
                    <TableCell>{r.unit_name ?? '–'}</TableCell>
                    <TableCell>
                      {r.partner_name ?? '–'} <span className="text-muted-foreground">{r.country_code ?? ''}</span>
                    </TableCell>
                    <TableCell>{KNOWN_SOURCE_LABEL[r.source] ?? r.source}</TableCell>
                    <TableCell>
                      {KNOWN_STATUS_LABEL[r.status] ?? r.status}
                      {r.matched_activity_code ? <div className="text-xs text-muted-foreground">{r.matched_activity_code}</div> : null}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
          <PreviewNote shown={Math.min(rows.length, PREVIEW_LIMIT)} total={rows.length} />
        </div>
      );
    }
    case 'arsip': {
      const ay = parsePositiveInt(getParam(sp, 'ay'));
      const snapshotId = getParam(sp, 'snapshot');
      const [years, rows] = await Promise.all([listAcademicYears(tx), getSnapshotList(tx, ay)]);
      const detail = isUuid(snapshotId) ? await getSnapshotDetail(tx, snapshotId) : null;
      return (
        <div className="space-y-4">
          <form method="get" action="/realisasi/laporan" className="flex flex-wrap items-end gap-3">
            <input type="hidden" name="report" value="arsip" />
            <div className="grid gap-1">
              <Label htmlFor="a-ay" className="text-xs text-muted-foreground">
                Tahun Akademik
              </Label>
              <NativeSelect id="a-ay" name="ay" defaultValue={ay ? String(ay) : ''} className="w-40">
                <option value="">Semua</option>
                {years.map((y) => (
                  <option key={y.id} value={y.id}>
                    {y.label}
                  </option>
                ))}
              </NativeSelect>
            </div>
            <Button type="submit" variant="secondary">
              Terapkan
            </Button>
          </form>
          <Toolbar kind="snapshot-archive" params={ay ? { ay: String(ay) } : {}} label="Unduh daftar arsip">
            {rows.length} snapshot
          </Toolbar>
          {detail ? (
            <Card className="p-4">
              <SnapshotDetailView detail={detail} />
            </Card>
          ) : null}
          <SnapshotTimeline rows={rows} selectedId={detail?.snapshot.id} />
        </div>
      );
    }
  }
}

async function renderKpiReport(tx: Tx, user: SessionUser, key: 'ringkasan' | 'kpi' | 'realisasi-kerjasama', sp: SP) {
  const isSubmitter = user.role === 'submitter';
  const p = parsePeriodParams(sp);
  if (isSubmitter) {
    p.unit = user.unitId ?? undefined;
    delete p.snapshot;
  }
  const units = isSubmitter ? null : await listUnits(tx);
  const preserve: Record<string, string> = { report: key };
  let content: React.ReactNode;
  let kind: ExportKind;
  let periodInfo;
  let exportParams: Record<string, string> = cleanParams(sp, ['report']);

  if (key === 'ringkasan') {
    const dash = await getDashboard(tx, p);
    periodInfo = dash.period;
    kind = 'kpi-summary';
    content = <SummaryTable values={dash.values} />;
  } else if (key === 'kpi') {
    const kpi = parseDrilldownKpi(getParam(sp, 'kpi')) ?? '1.1';
    const bucket = parseBucket(kpi, getParam(sp, 'bucket'));
    const dd = await getDrilldown(tx, { ...p, kpi, bucket });
    periodInfo = dd.period;
    kind = 'kpi-drilldown';
    preserve.kpi = kpi;
    if (bucket) preserve.bucket = bucket;
    if (p.snapshot) preserve.snapshot = p.snapshot;
    exportParams = { ...exportParams, kpi };
    content = (
      <div className="space-y-4">
        <form method="get" action="/realisasi/laporan" className="flex flex-wrap items-end gap-3">
          <input type="hidden" name="report" value="kpi" />
          <input type="hidden" name="ay" value={String(dd.period.ay_id)} />
          <input type="hidden" name="period" value={dd.period.period} />
          {p.unit ? <input type="hidden" name="unit" value={String(p.unit)} /> : null}
          {p.snapshot ? <input type="hidden" name="snapshot" value={p.snapshot} /> : null}
          <div className="grid gap-1">
            <Label htmlFor="k-kpi" className="text-xs text-muted-foreground">
              KPI
            </Label>
            <NativeSelect id="k-kpi" name="kpi" defaultValue={kpi} className="w-80">
              {(Object.keys(KPI_LABEL) as Array<keyof typeof KPI_LABEL>).map((k) => (
                <option key={k} value={k}>
                  {KPI_LABEL[k]}
                </option>
              ))}
            </NativeSelect>
          </div>
          <div className="grid gap-1">
            <Label htmlFor="k-bucket" className="text-xs text-muted-foreground">
              Kelompok
            </Label>
            <NativeSelect id="k-bucket" name="bucket" defaultValue={bucket ?? ''} className="w-48">
              <option value="">Semua</option>
              {DRILLDOWN_BUCKETS[kpi].map((b) => (
                <option key={b} value={b}>
                  {BUCKET_LABEL[b] ?? b}
                </option>
              ))}
            </NativeSelect>
          </div>
          <Button type="submit" variant="secondary">
            Terapkan
          </Button>
        </form>
        <p className="text-sm text-muted-foreground">
          {KPI_LABEL[kpi]}
          {bucket ? ` · ${BUCKET_LABEL[bucket] ?? bucket}` : ''} · <span data-testid="list-total">{dd.rows.length}</span> baris
        </p>
        <DrilldownTables dd={dd} />
      </div>
    );
  } else {
    const status = parseRealizationStatus(getParam(sp, 'status'));
    const dd = await getDrilldown(tx, { ...p, kpi: '1.19.24', bucket: realizationStatusToBucket(status) });
    periodInfo = dd.period;
    kind = 'realization-by-agreement';
    if (status) preserve.status = status;
    const rows = dd.rows.filter((r): r is ChainKpiRow => r.row_type === 'chain');
    content = (
      <div className="space-y-4">
        <form method="get" action="/realisasi/laporan" className="flex flex-wrap items-end gap-3">
          <input type="hidden" name="report" value="realisasi-kerjasama" />
          <input type="hidden" name="ay" value={String(dd.period.ay_id)} />
          <input type="hidden" name="period" value={dd.period.period} />
          {p.unit ? <input type="hidden" name="unit" value={String(p.unit)} /> : null}
          <div className="grid gap-1">
            <Label htmlFor="r-status" className="text-xs text-muted-foreground">
              Status
            </Label>
            <NativeSelect id="r-status" name="status" defaultValue={status ?? ''} className="w-48">
              <option value="">Semua</option>
              <option value="realized">Terlaksana</option>
              <option value="not_realized">Belum terlaksana</option>
              <option value="grace_excluded">Masa tenggang</option>
            </NativeSelect>
          </div>
          <Button type="submit" variant="secondary">
            Terapkan
          </Button>
        </form>
        <p className="text-sm text-muted-foreground">
          <span data-testid="list-total">{rows.length}</span> rantai kerja sama
        </p>
        <ChainKpiTable rows={rows} />
      </div>
    );
  }

  if (isSubmitter) delete exportParams.unit;
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <PeriodSelector
          basePath="/realisasi/laporan"
          academicYears={periodInfo.academic_years}
          ay={periodInfo.ay_id}
          period={periodInfo.period}
          unit={isSubmitter ? null : (p.unit ?? null)}
          units={units ? units.map((u) => ({ id: u.id, name: u.name })) : null}
          preserve={preserve}
        />
        <PeriodBadge period={periodInfo} />
      </div>
      <Toolbar kind={kind} params={{ ...exportParams, ay: String(periodInfo.ay_id), period: periodInfo.period }}>
        {periodInfo.label}
        {isSubmitter ? ' · unit Anda' : ''}
      </Toolbar>
      {content}
    </div>
  );
}

function Toolbar({ kind, params, children, label }: { kind: ExportKind; params: Record<string, string>; children: React.ReactNode; label?: string }) {
  return (
    <div className="flex flex-wrap items-center justify-between gap-3 border-y py-2">
      <p className="text-sm text-muted-foreground">{children}</p>
      <ExportButton kind={kind} params={params} label={label} />
    </div>
  );
}

function PreviewNote({ shown, total }: { shown: number; total: number }) {
  if (total <= shown) return null;
  return (
    <p className="text-xs text-muted-foreground">
      Menampilkan {formatNumber(shown)} dari {formatNumber(total)} baris. Unduh Excel untuk seluruh data.
    </p>
  );
}

function ActivityPreview({ rows }: { rows: ActivityListRow[] }) {
  if (rows.length === 0) return <EmptyRows />;
  return (
    <>
      <Table containerLabel="Pratinjau kegiatan">
        <TableHeader>
          <TableRow>
            <TableHead>Kode</TableHead>
            <TableHead>Nama</TableHead>
            <TableHead>Unit</TableHead>
            <TableHead>Mitra · Negara</TableHead>
            <TableHead>Tanggal</TableHead>
            <TableHead>Status</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.slice(0, PREVIEW_LIMIT).map((r) => (
            <TableRow key={r.id}>
              <TableCell className="whitespace-nowrap font-mono text-xs">
                <Link href={`/realisasi/kegiatan/${r.id}`} className="text-primary hover:underline">
                  {r.code}
                </Link>
              </TableCell>
              <TableCell>
                <div className="font-medium">{r.name}</div>
                <div className="text-xs text-muted-foreground">{r.type_name}</div>
              </TableCell>
              <TableCell className="text-sm">{r.submitter_unit_name}</TableCell>
              <TableCell className="text-sm">
                {(r.partner_names ?? []).join(', ')}
                <div className="text-xs text-muted-foreground">{(r.country_codes ?? []).join(', ')}</div>
              </TableCell>
              <TableCell className="whitespace-nowrap text-sm">
                {formatDate(r.start_date)}
                <div className="text-xs text-muted-foreground">{r.semester_label ?? ''}</div>
              </TableCell>
              <TableCell>
                <StatusBadge status={r.status} />
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
      <PreviewNote shown={Math.min(rows.length, PREVIEW_LIMIT)} total={rows.length} />
    </>
  );
}

function SlaPreview({ rows }: { rows: ActivityListRow[] }) {
  const sla = slaRows(rows);
  if (sla.length === 0) return <EmptyRows />;
  const tone = (l: string | null) => (l === 'red' ? 'red' : l === 'yellow' ? 'yellow' : 'neutral') as 'red' | 'yellow' | 'neutral';
  return (
    <>
      <Table containerLabel="Pratinjau SLA">
        <TableHeader>
          <TableRow>
            <TableHead>Kode</TableHead>
            <TableHead>Nama</TableHead>
            <TableHead>Jalur</TableHead>
            <TableHead>Status jalur</TableHead>
            <TableHead>Sejak</TableHead>
            <TableHead className="text-right">Hari kerja</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {sla.slice(0, PREVIEW_LIMIT).map((r) => (
            <TableRow key={`${r.a.id}-${r.track}`}>
              <TableCell className="whitespace-nowrap font-mono text-xs">
                <Link href={`/realisasi/kegiatan/${r.a.id}`} className="text-primary hover:underline">
                  {r.a.code}
                </Link>
              </TableCell>
              <TableCell className="text-sm">{r.a.name}</TableCell>
              <TableCell>{TRACK_LABEL[r.track]}</TableCell>
              <TableCell>{(TRACK_STATUS_LABEL as Record<string, string>)[r.status] ?? r.status}</TableCell>
              <TableCell className="whitespace-nowrap text-sm">{formatDate(r.since)}</TableCell>
              <TableCell className="text-right">
                {r.days === null ? (
                  <span className="text-muted-foreground">–</span>
                ) : (
                  <Badge variant={tone(r.level)}>
                    {r.days} hari{r.level && r.level !== 'ok' ? ` · ${SLA_LEVEL_LABEL[r.level as SlaLevel]}` : ''}
                  </Badge>
                )}
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
      <PreviewNote shown={Math.min(sla.length, PREVIEW_LIMIT)} total={sla.length} />
    </>
  );
}

