'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useTransition } from 'react';
import { Label } from '@/components/ui/label';
import { NativeSelect } from '@/components/ui/native-select';
import { PERIOD_LABEL } from '@/lib/realisasi/status';
import { cn } from '@/lib/utils';
import type { Period } from '@/lib/realisasi/types';

/** Revisi V.1 cut-offs: Ganjil only, Genap only, the whole AY cumulative, and AY-to-date. */
export const PERIOD_OPTIONS: Array<{ value: Period; label: string }> = (['ganjil', 'genap', 'full', 'ytd'] as const).map((value) => ({
  value,
  label: PERIOD_LABEL[value],
}));

function buildHref(basePath: string, preserve: Record<string, string>, next: { ay?: number; period: Period; unit?: number | null }) {
  const sp = new URLSearchParams(preserve);
  if (next.ay !== undefined) sp.set('ay', String(next.ay));
  sp.set('period', next.period);
  if (next.unit) sp.set('unit', String(next.unit));
  const s = sp.toString();
  return s ? `${basePath}?${s}` : basePath;
}

/** Tahun Akademik dropdown + segmented Ganjil | Genap | Setahun (kumulatif) | YTD (+ unit filter for university-level roles). */
export function PeriodSelector({
  basePath,
  academicYears,
  ay,
  period,
  unit,
  units,
  preserve = {},
}: {
  basePath: string;
  academicYears: Array<{ id: number; label: string }>;
  ay: number;
  period: Period;
  unit?: number | null;
  /** null → unit filter hidden (submitters are fixed to their unit) */
  units: Array<{ id: number; name: string }> | null;
  preserve?: Record<string, string>;
}) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const go = (next: { ay?: number; period: Period; unit?: number | null }) =>
    startTransition(() => router.push(buildHref(basePath, preserve, next)));

  return (
    <div className={cn('flex flex-wrap items-end gap-3', pending && 'opacity-70')} aria-busy={pending}>
      <div className="grid gap-1">
        <Label htmlFor="period-ay" className="text-xs text-muted-foreground">
          Tahun Akademik
        </Label>
        <NativeSelect
          id="period-ay"
          value={String(ay)}
          onChange={(e) => go({ ay: Number(e.target.value), period, unit })}
          className="w-36"
        >
          {academicYears.map((y) => (
            <option key={y.id} value={y.id}>
              {y.label}
            </option>
          ))}
        </NativeSelect>
      </div>
      <div className="grid gap-1">
        <span id="period-seg-label" className="text-xs font-medium text-muted-foreground">
          Periode
        </span>
        {/* L-10: these are navigation links, so links + aria-current (not role="radio" without arrow keys). */}
        <nav aria-labelledby="period-seg-label" className="inline-flex h-9 rounded-md border bg-background p-0.5">
          {PERIOD_OPTIONS.map((o) => {
            const active = o.value === period;
            return (
              <Link
                key={o.value}
                aria-current={active ? 'page' : undefined}
                href={buildHref(basePath, preserve, { ay, period: o.value, unit })}
                data-testid={`period-${o.value}`}
                className={cn(
                  'inline-flex items-center rounded px-3 text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                  active ? 'bg-primary text-primary-foreground' : 'text-foreground hover:bg-accent',
                )}
              >
                {o.label}
              </Link>
            );
          })}
        </nav>
      </div>
      {units ? (
        <div className="grid gap-1">
          <Label htmlFor="period-unit" className="text-xs text-muted-foreground">
            Lingkup
          </Label>
          <NativeSelect
            id="period-unit"
            value={unit ? String(unit) : ''}
            onChange={(e) => go({ ay, period, unit: e.target.value ? Number(e.target.value) : null })}
            className="w-64"
          >
            <option value="">Universitas (semua unit)</option>
            {units.map((u) => (
              <option key={u.id} value={u.id}>
                {u.name}
              </option>
            ))}
          </NativeSelect>
        </div>
      ) : null}
    </div>
  );
}
