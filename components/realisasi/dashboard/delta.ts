import { formatNumber, formatPct } from '@/lib/realisasi/format';
import type { KpiDelta } from '@/components/realisasi/dashboard/kpi-card';

/** Delta of a count vs the same period last year (null previous → "no comparison"). */
export function countDelta(cur: number, prev: number | null | undefined, prevLabel: string | null): KpiDelta {
  if (prev === null || prev === undefined || prevLabel === null) return { diff: null, text: 'Belum ada data pembanding' };
  const diff = cur - prev;
  const sign = diff > 0 ? '+' : diff < 0 ? '−' : '±';
  return { diff, text: `${sign}${formatNumber(Math.abs(diff))} vs ${prevLabel} (${formatNumber(prev)})` };
}

/** Delta in percentage points. */
export function pctDelta(cur: number | null, prev: number | null | undefined, prevLabel: string | null): KpiDelta {
  if (cur === null || prev === null || prev === undefined || prevLabel === null) {
    return { diff: null, text: 'Belum ada data pembanding' };
  }
  const diff = Math.round((cur - prev) * 10) / 10;
  const sign = diff > 0 ? '+' : diff < 0 ? '−' : '±';
  return { diff, text: `${sign}${formatPct(Math.abs(diff)).replace('%', '')} poin vs ${prevLabel} (${formatPct(prev)})` };
}
