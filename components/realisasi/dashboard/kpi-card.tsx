import Link from 'next/link';
import type { ReactNode } from 'react';
import { ArrowDownRight, ArrowRight, ArrowUpRight } from 'lucide-react';
import { Card } from '@/components/ui/card';
import { cn } from '@/lib/utils';
import { CardMenu } from '@/components/realisasi/dashboard/card-menu';

export interface KpiDelta {
  /** Signed difference (count or percentage points); null when there is no comparison. */
  diff: number | null;
  /** e.g. '+12 vs Live 2025/2026' */
  text: string;
}

/** Server-safe RENSTRA (KPI) stat tile: label · big value · sub-lines · delta; title/value link to the drill-down. */
export function KpiCard({
  code,
  title,
  value,
  drillHref,
  exportHref,
  children,
  delta,
}: {
  code: string;
  title: string;
  value: string;
  drillHref: string;
  exportHref: string;
  children?: ReactNode;
  delta?: KpiDelta | null;
}) {
  const DeltaIcon = !delta || delta.diff === null || delta.diff === 0 ? ArrowRight : delta.diff > 0 ? ArrowUpRight : ArrowDownRight;
  return (
    <Card data-testid={`kpi-card-${code}`} className="flex flex-col gap-2 p-4">
      <div className="flex items-start justify-between gap-2">
        <Link
          href={drillHref}
          className="group min-w-0 rounded-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
          <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">RENSTRA {code}</p>
          <h2 className="text-sm font-medium leading-snug text-foreground group-hover:underline">{title}</h2>
        </Link>
        <CardMenu exportHref={exportHref} label={`RENSTRA ${code}`} />
      </div>
      <Link
        href={drillHref}
        className="w-fit rounded-sm text-4xl font-semibold leading-none tracking-tight text-foreground hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        aria-label={`${title}: ${value}. Lihat rincian`}
      >
        <span data-testid="kpi-value">{value}</span>
      </Link>
      <div className="space-y-1 text-sm text-muted-foreground">{children}</div>
      {delta ? (
        <p
          className={cn(
            'mt-auto flex items-center gap-1 text-xs font-medium',
            delta.diff === null || delta.diff === 0
              ? 'text-muted-foreground'
              : delta.diff > 0
                ? 'text-success-fg'
                : 'text-danger-fg',
          )}
        >
          <DeltaIcon className="h-3.5 w-3.5" aria-hidden="true" />
          {delta.text}
        </p>
      ) : null}
    </Card>
  );
}
