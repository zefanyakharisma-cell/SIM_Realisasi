'use client';

import { useState, type ReactNode } from 'react';
import {
  Bar,
  BarChart,
  CartesianGrid,
  LabelList,
  Legend,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
  type TooltipProps,
} from 'recharts';
import { Card } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { formatNumber, formatPct } from '@/lib/realisasi/format';
import type { KpiCharts } from '@/lib/realisasi/types';
import { CHART_LABEL, type ChartKey } from '@/lib/realisasi/schemas/report';
import { CardMenu } from '@/components/realisasi/dashboard/card-menu';
import { SdgHeatmap } from '@/components/realisasi/dashboard/sdg-heatmap';
import { VIZ } from '@/components/realisasi/dashboard/viz';

const C = VIZ.light;
const AXIS_TICK = { fill: C.textSecondary, fontSize: 12 };

type Datum = { name: string; value: number; extra?: string };

// ---------------------------------------------------------------- shell
function ChartCard({
  chart,
  description,
  exportHref,
  table,
  children,
}: {
  chart: ChartKey;
  description?: string;
  exportHref: string;
  table: { headers: string[]; rows: Array<Array<string>> };
  children: ReactNode;
}) {
  const [showTable, setShowTable] = useState(false);
  const title = CHART_LABEL[chart];
  const headingId = `chart-${chart}-title`;
  return (
    <Card className="flex min-w-0 flex-col p-4" aria-labelledby={headingId} role="region" data-testid={`chart-${chart}`}>
      <div className="mb-3 flex items-start justify-between gap-2">
        <div className="min-w-0">
          <h3 id={headingId} className="text-sm font-semibold text-foreground">
            {title}
          </h3>
          {description ? <p className="text-xs text-muted-foreground">{description}</p> : null}
        </div>
        <CardMenu
          exportHref={exportHref}
          label={title}
          showingTable={showTable}
          onToggleTable={() => setShowTable((v) => !v)}
        />
      </div>
      {showTable ? <DataTable caption={title} {...table} /> : children}
    </Card>
  );
}

function DataTable({ caption, headers, rows }: { caption: string; headers: string[]; rows: string[][] }) {
  if (rows.length === 0) return <EmptyChart />;
  return (
    <div className="max-h-80 overflow-auto">
      <Table>
        <caption className="sr-only">{caption}</caption>
        <TableHeader>
          <TableRow>
            {headers.map((h, i) => (
              <TableHead key={h} className={i > 0 ? 'text-right' : undefined}>
                {h}
              </TableHead>
            ))}
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((r, ri) => (
            <TableRow key={`${r[0]}-${ri}`}>
              {r.map((c, ci) => (
                <TableCell key={ci} className={ci > 0 ? 'text-right tabular-nums' : undefined}>
                  {c}
                </TableCell>
              ))}
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}

function EmptyChart({ text = 'Belum ada data pada periode ini.' }: { text?: string }) {
  return (
    <div className="flex h-40 items-center justify-center rounded-md border border-dashed text-sm text-muted-foreground">
      {text}
    </div>
  );
}

// ---------------------------------------------------------------- tooltip
function ValueTooltip({ active, payload, label, valueFormat }: TooltipProps<number, string> & { valueFormat?: (n: number) => string }) {
  if (!active || !payload || payload.length === 0) return null;
  const datum = payload[0]?.payload as Datum | undefined;
  return (
    <div className="rounded-md border bg-background px-3 py-2 text-xs shadow-md">
      <p className="mb-1 font-medium text-muted-foreground">{datum?.name ?? label}</p>
      {payload.map((p) => (
        <p key={String(p.dataKey)} className="flex items-center gap-2">
          {payload.length > 1 ? (
            <span aria-hidden="true" className="inline-block h-0.5 w-3 rounded" style={{ background: p.color }} />
          ) : null}
          <span className="font-semibold text-foreground tabular-nums">
            {valueFormat ? valueFormat(Number(p.value)) : formatNumber(Number(p.value))}
          </span>
          {payload.length > 1 ? <span className="text-muted-foreground">{p.name}</span> : null}
        </p>
      ))}
      {datum?.extra ? <p className="mt-1 text-muted-foreground">{datum.extra}</p> : null}
    </div>
  );
}

// ---------------------------------------------------------------- horizontal bars (single series)
function HBar({ data, valueFormat, domainMax }: { data: Datum[]; valueFormat?: (n: number) => string; domainMax?: number }) {
  if (data.length === 0) return <EmptyChart />;
  const longest = data.reduce((m, d) => Math.max(m, d.name.length), 0);
  const yWidth = Math.min(200, Math.max(70, longest * 7));
  const height = data.length * 34 + 32;
  return (
    <div style={{ height }} className="w-full">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={data} layout="vertical" margin={{ top: 4, right: 48, bottom: 4, left: 4 }} barCategoryGap={6}>
          <CartesianGrid horizontal={false} stroke={C.grid} strokeWidth={1} />
          <XAxis
            type="number"
            domain={[0, domainMax ?? 'auto']}
            allowDecimals={false}
            tick={AXIS_TICK}
            axisLine={{ stroke: C.axis }}
            tickLine={false}
            tickFormatter={(v: number) => (valueFormat ? valueFormat(v) : formatNumber(v))}
          />
          <YAxis type="category" dataKey="name" width={yWidth} tick={AXIS_TICK} axisLine={{ stroke: C.axis }} tickLine={false} interval={0} />
          <Tooltip cursor={{ fill: C.grid, opacity: 0.4 }} content={<ValueTooltip valueFormat={valueFormat} />} />
          <Bar dataKey="value" name="Nilai" fill={C.series1} radius={[0, 4, 4, 0]} maxBarSize={24} isAnimationActive={false}>
            <LabelList
              dataKey="value"
              position="right"
              fill={C.textSecondary}
              fontSize={12}
              formatter={(v: number) => (valueFormat ? valueFormat(v) : formatNumber(v))}
            />
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}

// ---------------------------------------------------------------- grouped bars (inbound vs outbound)
function MobilityChart({ data }: { data: KpiCharts['mobility_by_semester'] }) {
  if (data.length === 0) return <EmptyChart />;
  const rows = data.map((d) => ({ name: d.label, Outbound: d.outbound, Inbound: d.inbound }));
  return (
    <div className="h-64 w-full">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={rows} margin={{ top: 20, right: 8, bottom: 4, left: 0 }} barGap={2} barCategoryGap="25%">
          <CartesianGrid vertical={false} stroke={C.grid} strokeWidth={1} />
          <XAxis dataKey="name" tick={AXIS_TICK} axisLine={{ stroke: C.axis }} tickLine={false} />
          <YAxis allowDecimals={false} tick={AXIS_TICK} axisLine={false} tickLine={false} width={40} tickFormatter={(v: number) => formatNumber(v)} />
          <Tooltip cursor={{ fill: C.grid, opacity: 0.4 }} content={<ValueTooltip />} />
          <Legend iconType="rect" iconSize={10} wrapperStyle={{ fontSize: 12, color: C.textSecondary }} />
          <Bar dataKey="Outbound" fill={C.series1} radius={[4, 4, 0, 0]} maxBarSize={24} isAnimationActive={false}>
            <LabelList dataKey="Outbound" position="top" fill={C.textSecondary} fontSize={12} />
          </Bar>
          <Bar dataKey="Inbound" fill={C.series2} radius={[4, 4, 0, 0]} maxBarSize={24} isAnimationActive={false}>
            <LabelList dataKey="Inbound" position="top" fill={C.textSecondary} fontSize={12} />
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}

// ---------------------------------------------------------------- grid
export function DashboardCharts({
  charts,
  level,
  exportQuery,
}: {
  charts: KpiCharts;
  level: 'university' | 'unit';
  /** Period query string without leading '?', e.g. 'ay=2&period=live' */
  exportQuery: string;
}) {
  const href = (chart: ChartKey) => `/api/export/chart?${exportQuery}${exportQuery ? '&' : ''}chart=${chart}`;
  const unitOnly = 'Hanya tersedia pada tingkat universitas.';
  const pct = (n: number) => formatPct(n);

  const countries: Datum[] = charts.by_country.slice(0, 10).map((d) => ({ name: d.country_name || d.country_code, value: d.activities, extra: d.country_code }));
  const units: Datum[] = charts.by_unit.map((d) => ({ name: d.unit_name, value: d.activities }));
  // M-5: units without active agreements have pct = null ("–"), not 0 %; they get no bar.
  const realization: Datum[] = charts.realization_by_unit
    .filter((d) => d.pct !== null)
    .map((d) => ({
      name: d.unit_name,
      value: d.pct ?? 0,
      extra: `${formatNumber(d.numerator)} dari ${formatNumber(d.denominator)} kerja sama`,
    }));
  const noAgreements = charts.realization_by_unit.filter((d) => d.pct === null).map((d) => d.unit_name);
  const partners: Datum[] = charts.top_partners.slice(0, 10).map((d) => ({ name: d.partner_name, value: d.activities, extra: d.country_code }));

  return (
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
      <ChartCard
        chart="mobility_by_semester"
        description="Mahasiswa unik per (NRP, grup kegiatan), menurut semester tanggal mulai"
        exportHref={href('mobility_by_semester')}
        table={{
          headers: ['Semester', 'Outbound', 'Inbound'],
          rows: charts.mobility_by_semester.map((d) => [d.label, formatNumber(d.outbound), formatNumber(d.inbound)]),
        }}
      >
        <MobilityChart data={charts.mobility_by_semester} />
      </ChartCard>

      <ChartCard
        chart="by_country"
        description="10 negara mitra teratas (kegiatan terverifikasi)"
        exportHref={href('by_country')}
        table={{ headers: ['Negara', 'Kegiatan'], rows: countries.map((d) => [d.name, formatNumber(d.value)]) }}
      >
        <HBar data={countries} />
      </ChartCard>

      <ChartCard
        chart="by_unit"
        description="Kegiatan terverifikasi per unit (termasuk unit pendamping)"
        exportHref={href('by_unit')}
        table={{ headers: ['Unit', 'Kegiatan'], rows: units.map((d) => [d.name, formatNumber(d.value)]) }}
      >
        {level === 'unit' ? <EmptyChart text={unitOnly} /> : <HBar data={units} />}
      </ChartCard>

      <ChartCard
        chart="by_sdg"
        description="Jumlah kegiatan per tujuan SDG — makin gelap makin banyak"
        exportHref={href('by_sdg')}
        table={{ headers: ['SDG', 'Kegiatan'], rows: charts.by_sdg.map((d) => [`${d.sdg_id}. ${d.name}`, formatNumber(d.activities)]) }}
      >
        <SdgHeatmap data={charts.by_sdg} />
      </ChartCard>

      <ChartCard
        chart="realization_by_unit"
        description="KPI 1.19.24 per unit: kerja sama terlaksana ÷ kerja sama aktif"
        exportHref={href('realization_by_unit')}
        table={{
          headers: ['Unit', 'Terlaksana', 'Kerja sama', 'Persentase'],
          rows: charts.realization_by_unit.map((d) => [d.unit_name, formatNumber(d.numerator), formatNumber(d.denominator), formatPct(d.pct)]),
        }}
      >
        {level === 'unit' ? (
          <EmptyChart text={unitOnly} />
        ) : (
          <>
            <HBar data={realization} valueFormat={pct} domainMax={100} />
            {noAgreements.length > 0 && (
              <p className="mt-2 text-xs text-muted-foreground" data-testid="realization-no-agreements">
                Tidak ada kerja sama aktif (–): {noAgreements.join(', ')}
              </p>
            )}
          </>
        )}
      </ChartCard>

      <ChartCard
        chart="top_partners"
        description="10 mitra dengan kegiatan terverifikasi terbanyak"
        exportHref={href('top_partners')}
        table={{ headers: ['Mitra', 'Kegiatan'], rows: partners.map((d) => [`${d.name} (${d.extra ?? ''})`, formatNumber(d.value)]) }}
      >
        <HBar data={partners} />
      </ChartCard>
    </div>
  );
}
