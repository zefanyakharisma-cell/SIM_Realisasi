// Dashboard (Design §3.1). Every number comes from realisasi.dashboard() — no KPI math in TS.
import Link from 'next/link';
import { AlertTriangle, CalendarClock, Info } from 'lucide-react';
import { withUser } from '@/lib/db';
import { can, requireUser } from '@/lib/session';
import { parseDbError, type AppError } from '@/lib/realisasi/errors';
import { formatDate, formatNumber, formatPct } from '@/lib/realisasi/format';
import { PERIOD_LABEL } from '@/lib/realisasi/status';
import type { DashboardData } from '@/lib/realisasi/types';
import { parsePeriodParams, type PeriodParams } from '@/lib/realisasi/schemas/report';
import { getDashboard, listUnits, type UnitOption } from '@/lib/realisasi/queries/reports';
import { PageHeader } from '@/components/realisasi/page-header';
import { Card } from '@/components/ui/card';
import { KpiCard } from '@/components/realisasi/dashboard/kpi-card';
import { PeriodSelector } from '@/components/realisasi/dashboard/period-selector';
import { PeriodBadge } from '@/components/realisasi/dashboard/period-badge';
import { DashboardCharts } from '@/components/realisasi/dashboard/charts';
import { countDelta, pctDelta } from '@/components/realisasi/dashboard/delta';

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

export default async function DashboardPage(props: { searchParams: Promise<SP> }) {
  const user = await requireUser();
  const sp = await props.searchParams;
  const p: PeriodParams = parsePeriodParams(sp);
  delete p.snapshot;
  if (user.role === 'submitter') p.unit = user.unitId ?? undefined;

  let data: DashboardData | null = null;
  let units: UnitOption[] | null = null;
  let error: AppError | null = null;
  try {
    ({ data, units } = await withUser(user.id, async (tx) => ({
      data: await getDashboard(tx, p),
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
  const s8 = values.kpi_1_19_s8;
  const canRegister = can(user, 'known.view');
  // M-3: open the register with the same scope the S8 card counts (CONTRACTS §4.2): international,
  // unmatched, inside the period window, and the unit when unit-scoped.
  const unmatchedHref = `/realisasi/kegiatan-diketahui?${new URLSearchParams({
    status: 'unmatched',
    intl: '1',
    from: period.window_start,
    to: period.window_end,
    ...(scope.unit_id ? { unit_id: String(scope.unit_id) } : {}),
  }).toString()}`;

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
      />

      <p className="text-xs text-muted-foreground">
        Jendela {formatDate(period.window_start)} – {formatDate(period.window_end)} · cutoff {formatDate(period.cutoff)}
        {period.frozen ? ` · snapshot dibekukan oleh ${period.frozen_by_name ?? 'Job terjadwal'}` : ''}
      </p>

      {data.late_additions > 0 ? (
        <p className="flex items-center gap-2 rounded-md border border-blue-200 bg-blue-50 px-3 py-2 text-sm text-blue-900">
          <Info className="h-4 w-4 shrink-0" aria-hidden="true" />
          {formatNumber(data.late_additions)} tambahan susulan: kegiatan dalam jendela ini yang diverifikasi setelah snapshot dibekukan.
        </p>
      ) : null}

      <section aria-label="Indikator kinerja" className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
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

        <KpiCard
          code="1.19.S8"
          title="Kegiatan internasional dilaporkan via SIM"
          value={formatPct(s8.pct)}
          drillHref={drill('1.19.S8')}
          exportHref={exp('1.19.S8')}
          delta={pctDelta(s8.pct, previous?.kpi_1_19_s8.pct, prevLabel)}
        >
          <p>{formatNumber(s8.reported)} dilaporkan via SIM</p>
          <p data-testid="kpi-s8-unmatched">
            {canRegister ? (
              <Link
                href={unmatchedHref}
                className="font-medium text-amber-900 underline underline-offset-2"
              >
                {formatNumber(s8.unmatched_known)} kegiatan belum dilaporkan
              </Link>
            ) : (
              <span className="font-medium text-amber-900">{formatNumber(s8.unmatched_known)} kegiatan belum dilaporkan</span>
            )}
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
    </div>
  );
}
