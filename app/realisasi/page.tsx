// Dashboard (Design §3.1; Revisi V.1 tabs Capaian Renstra | International Awards). Every number comes from
// realisasi.dashboard() / realisasi.international_awards() — no KPI math in TS.
import Link from 'next/link';
import { AlertTriangle, CalendarClock, Info, Inbox } from 'lucide-react';
import { withUser } from '@/lib/db';
import { requireUser } from '@/lib/session';
import { parseDbError, type AppError } from '@/lib/realisasi/errors';
import { formatDate, formatDateTime, formatNumber, formatPct } from '@/lib/realisasi/format';
import { PERIOD_LABEL } from '@/lib/realisasi/status';
import type { AwardsData, DashboardData, WorkQueue } from '@/lib/realisasi/types';
import { parsePeriodParams, type PeriodParams } from '@/lib/realisasi/schemas/report';
import { getAwards, getDashboard, listUnits, type UnitOption } from '@/lib/realisasi/queries/reports';
import { PageHeader } from '@/components/realisasi/page-header';
import { Card } from '@/components/ui/card';
import { KpiCard } from '@/components/realisasi/dashboard/kpi-card';
import { PeriodSelector } from '@/components/realisasi/dashboard/period-selector';
import { PeriodBadge } from '@/components/realisasi/dashboard/period-badge';
import { DashboardCharts } from '@/components/realisasi/dashboard/charts';
import { AwardsTables } from '@/components/realisasi/dashboard/awards-tables';
import { countDelta, pctDelta } from '@/components/realisasi/dashboard/delta';
import { cn } from '@/lib/utils';

export const dynamic = 'force-dynamic';

type SP = Record<string, string | string[] | undefined>;

function query(p: { ay: number; period: string; unit?: number | null }, extra: Record<string, string> = {}): string {
  const sp = new URLSearchParams({ ay: String(p.ay), period: p.period });
  if (p.unit) sp.set('unit', String(p.unit));
  for (const [k, v] of Object.entries(extra)) sp.set(k, v);
  return sp.toString();
}

function daysLeftText(n: number): string {
  if (n < 0) return `lewat ${formatNumber(-n)} hari`;
  if (n === 0) return 'hari ini';
  return `${formatNumber(n)} hari lagi`;
}

type DashTab = 'renstra' | 'awards';

function DashboardTabs({ current, hrefFor }: { current: DashTab; hrefFor: (t: DashTab) => string }) {
  const tabs: Array<{ id: DashTab; label: string }> = [
    { id: 'renstra', label: 'Capaian Renstra' },
    { id: 'awards', label: 'International Awards' },
  ];
  return (
    <nav aria-label="Tab dashboard" className="flex gap-1 border-b">
      {tabs.map((t) => {
        const active = t.id === current;
        return (
          <Link
            key={t.id}
            href={hrefFor(t.id)}
            aria-current={active ? 'page' : undefined}
            data-testid={`dashboard-tab-${t.id}`}
            className={cn(
              '-mb-px border-b-2 px-4 py-2 text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
              active ? 'border-primary text-foreground' : 'border-transparent text-muted-foreground hover:text-foreground',
            )}
          >
            {t.label}
          </Link>
        );
      })}
    </nav>
  );
}

/** "Perlu diproses" (Revisi V.1, replaces SLA): what the mobility team should handle next. */
function WorkQueueCard({ wq }: { wq: WorkQueue }) {
  return (
    <Card className="p-4" data-testid="work-queue">
      <h2 className="mb-2 flex items-center gap-2 text-sm font-semibold">
        <Inbox className="h-4 w-4" aria-hidden="true" />
        Perlu diproses
      </h2>
      <p className="mb-2 flex flex-wrap gap-x-4 gap-y-1 text-sm">
        <Link href="/realisasi/verifikasi/mobilitas" className="font-medium text-primary underline-offset-2 hover:underline">
          {formatNumber(wq.mobility_pending)} kegiatan menunggu verifikasi
        </Link>
        <Link href="/realisasi/verifikasi/mobilitas#duplikat" className="font-medium text-primary underline-offset-2 hover:underline">
          {formatNumber(wq.conflicts_open)} duplikat mahasiswa
        </Link>
        <span className="text-muted-foreground">{formatNumber(wq.waiting_unit_revision)} menunggu revisi unit</span>
      </p>
      {wq.items.length === 0 ? (
        <p className="text-sm text-muted-foreground">Tidak ada dokumen yang perlu diproses.</p>
      ) : (
        <ul className="divide-y">
          {wq.items.map((d) => (
            <li key={d.id} className="flex flex-wrap items-center justify-between gap-2 py-2 text-sm">
              <Link href={`/realisasi/kegiatan/${d.id}`} className="font-medium hover:underline">
                <span className="text-muted-foreground">{d.code}</span> · {d.name}
              </Link>
              <span className="text-xs text-muted-foreground">
                {d.unit_name ?? '–'} · diajukan {formatDateTime(d.submitted_at)}
                {d.open_conflicts > 0 ? ` · ${formatNumber(d.open_conflicts)} duplikat` : ''}
              </span>
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}

export default async function DashboardPage(props: { searchParams: Promise<SP> }) {
  const user = await requireUser();
  const sp = await props.searchParams;
  const p: PeriodParams = parsePeriodParams(sp);
  delete p.snapshot;
  if (user.role === 'submitter') p.unit = user.unitId ?? undefined;
  const tab: DashTab = sp.tab === 'awards' ? 'awards' : 'renstra';

  let data: DashboardData | null = null;
  let awards: AwardsData | null = null;
  let units: UnitOption[] | null = null;
  let error: AppError | null = null;
  try {
    ({ data, awards, units } = await withUser(user.id, async (tx) => ({
      data: await getDashboard(tx, p),
      awards: tab === 'awards' ? await getAwards(tx, p) : null,
      units: user.role === 'submitter' ? null : await listUnits(tx),
    })));
  } catch (e) {
    error = parseDbError(e);
  }

  if (!data) {
    return (
      <div className="space-y-6">
        <PageHeader title="Dashboard Realisasi" />
        <Card role="alert" className="flex items-start gap-3 border-red-200 bg-red-50 p-4 text-sm text-red-900">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
          <div>
            <p className="font-medium">Dashboard tidak dapat dimuat.</p>
            <p>{error?.message ?? 'Terjadi kesalahan pada server.'}</p>
          </div>
        </Card>
      </div>
    );
  }

  const { period, scope, values, previous } = data;
  const base = { ay: period.ay_id, period: period.period, unit: scope.unit_id };
  const drill = (kpi: string, bucket?: string) =>
    `/realisasi/laporan?${query(base, { report: 'kpi', kpi, ...(bucket ? { bucket } : {}) })}`;
  const exp = (kpi: string) => `/api/export/kpi-drilldown?${query(base, { kpi })}`;
  const prevLabel = previous ? `${PERIOD_LABEL[period.period] ?? ''} ${previous.ay_label}`.trim() : null;

  const k11 = values.kpi_1_1;
  const s1 = values.kpi_1_19_s1;
  const k24 = values.kpi_1_19_24;
  const tabHref = (t: DashTab) => `/realisasi?${query(base, t === 'awards' ? { tab: 'awards' } : {})}`;

  return (
    <div className="space-y-6">
      <PageHeader
        title="Dashboard Realisasi"
        description={
          scope.level === 'unit'
            ? `Lingkup unit: ${scope.unit_name ?? '–'} · ${period.label}`
            : `Lingkup universitas · ${period.label}`
        }
        actions={<PeriodBadge period={period} />}
      />

      <PeriodSelector
        basePath="/realisasi"
        academicYears={period.academic_years}
        ay={period.ay_id}
        period={period.period}
        unit={user.role === 'submitter' ? null : scope.unit_id}
        units={units ? units.map((u) => ({ id: u.id, name: u.name })) : null}
        preserve={tab === 'awards' ? { tab: 'awards' } : {}}
      />

      <DashboardTabs current={tab} hrefFor={tabHref} />

      <p className="text-xs text-muted-foreground">
        Jendela {formatDate(period.window_start)} – {formatDate(period.window_end)} · cutoff {formatDate(period.cutoff)}
        {period.frozen ? ` · snapshot dibekukan oleh ${period.frozen_by_name ?? 'Job terjadwal'}` : ''}
      </p>

      {data.work_queue ? <WorkQueueCard wq={data.work_queue} /> : null}

      {tab === 'awards' && awards ? (
        <AwardsTables data={awards} exportQuery={query(base)} />
      ) : (
        <>
          {data.late_additions > 0 ? (
            <p className="flex items-center gap-2 rounded-md border border-blue-200 bg-blue-50 px-3 py-2 text-sm text-blue-900">
              <Info className="h-4 w-4 shrink-0" aria-hidden="true" />
              {formatNumber(data.late_additions)} tambahan susulan: kegiatan dalam jendela ini yang diverifikasi setelah snapshot dibekukan.
            </p>
          ) : null}

          <section aria-label="Capaian Renstra" className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
            <KpiCard
              code="1.1"
              title="Mahasiswa inbound & outbound"
              value={formatNumber(k11.total)}
              drillHref={drill('1.1')}
              exportHref={exp('1.1')}
              delta={countDelta(k11.total, previous?.kpi_1_1.total, prevLabel)}
            >
              <p>
                Inbound {formatNumber(k11.inbound)} · Outbound {formatNumber(k11.outbound)}
              </p>
            </KpiCard>

            <KpiCard
              code="1.19.S1"
              title="Kegiatan internasional dengan mitra"
              value={formatNumber(s1.international)}
              drillHref={drill('1.19.S1', 'international')}
              exportHref={exp('1.19.S1')}
              delta={countDelta(s1.international, previous?.kpi_1_19_s1.international, prevLabel)}
            >
              <p>Domestik {formatNumber(s1.domestic)} (referensi)</p>
            </KpiCard>

            <KpiCard
              code="1.19.24"
              title="MoU & MoA terlaksana"
              value={formatPct(k24.all.pct)}
              drillHref={drill('1.19.24')}
              exportHref={exp('1.19.24')}
              delta={pctDelta(k24.all.pct, previous?.kpi_1_19_24.pct, prevLabel)}
            >
              <p>
                {formatNumber(k24.all.numerator)} dari {formatNumber(k24.all.denominator)} kerja sama
              </p>
              <p className="text-xs">
                <Link href={drill('1.19.24', 'grace_excluded')} className="underline-offset-2 hover:underline" data-testid="kpi-grace-link">
                  {formatNumber(k24.all.grace_excluded)} dalam masa tenggang
                </Link>
                {' · '}Intl {formatPct(k24.international.pct)} · Dom {formatPct(k24.domestic.pct)}
              </p>
            </KpiCard>

          </section>

          {scope.level === 'unit' ? (
            <Card className="p-4" data-testid="drafts-near-deadline">
              <h2 className="mb-2 flex items-center gap-2 text-sm font-semibold">
                <CalendarClock className="h-4 w-4" aria-hidden="true" />
                Draf mendekati tenggat
              </h2>
              {data.drafts_near_deadline.length === 0 ? (
                <p className="text-sm text-muted-foreground">Tidak ada draf yang mendekati batas pelaporan.</p>
              ) : (
                <ul className="divide-y">
                  {data.drafts_near_deadline.map((d) => (
                    <li key={d.id} className="flex flex-wrap items-center justify-between gap-2 py-2 text-sm">
                      <Link href={`/realisasi/kegiatan/baru?draft=${d.id}`} className="font-medium hover:underline">
                        <span className="text-muted-foreground">{d.code}</span> · {d.name}
                      </Link>
                      <span className={d.days_left < 0 ? 'font-medium text-red-800' : 'text-amber-900'}>
                        Batas {formatDate(d.reporting_deadline)} ({daysLeftText(d.days_left)})
                      </span>
                    </li>
                  ))}
                </ul>
              )}
            </Card>
          ) : null}

          <DashboardCharts charts={values.charts} level={scope.level} exportQuery={query(base)} />
        </>
      )}
    </div>
  );
}
