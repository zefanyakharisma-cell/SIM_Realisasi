'use client';

import type { KpiCharts } from '@/lib/realisasi/types';
import { formatNumber } from '@/lib/realisasi/format';
import { SEQ_BLUE, inkOn, seqStep } from '@/components/realisasi/dashboard/viz';

/** 17-cell SDG coverage grid: sequential blue by activity count; number printed in every cell. */
export function SdgHeatmap({ data }: { data: KpiCharts['by_sdg'] }) {
  const max = data.reduce((m, d) => Math.max(m, d.activities), 0);
  const cells = [...data].sort((a, b) => a.sdg_id - b.sdg_id);
  return (
    <div>
      <ul className="grid grid-cols-4 gap-0.5 sm:grid-cols-6" aria-label="Cakupan SDG">
        {cells.map((d) => {
          const step = seqStep(d.activities, max);
          return (
            <li
              key={d.sdg_id}
              tabIndex={0}
              title={`SDG ${d.sdg_id} — ${d.name}: ${formatNumber(d.activities)} kegiatan`}
              aria-label={`SDG ${d.sdg_id} ${d.name}: ${d.activities} kegiatan`}
              className="flex h-16 flex-col justify-between rounded p-1.5 outline-none ring-offset-1 transition hover:ring-2 hover:ring-slate-400 focus-visible:ring-2 focus-visible:ring-ring"
              style={{ background: SEQ_BLUE[step], color: inkOn(step) }}
            >
              <span className="text-[11px] font-semibold leading-none">SDG {d.sdg_id}</span>
              <span className="text-lg font-semibold leading-none tabular-nums">{formatNumber(d.activities)}</span>
            </li>
          );
        })}
      </ul>
      <div className="mt-3 flex items-center gap-2 text-xs text-muted-foreground" aria-hidden="true">
        <span>0</span>
        <span className="flex">
          {SEQ_BLUE.map((c) => (
            <span key={c} className="h-2.5 w-5 first:rounded-l last:rounded-r" style={{ background: c }} />
          ))}
        </span>
        <span>{formatNumber(max)} kegiatan</span>
      </div>
    </div>
  );
}
