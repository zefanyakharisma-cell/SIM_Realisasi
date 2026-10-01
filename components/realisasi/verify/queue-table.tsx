'use client';

import { Fragment, useState, type ReactNode } from 'react';
import Link from 'next/link';
import { ChevronRight } from 'lucide-react';
import { SlaChip, TrackChips } from '@/components/realisasi/status-badge';
import { DateRange, PartnerCell, UnitCell } from '@/components/realisasi/list/activity-table';
import { formatDateTime } from '@/lib/realisasi/format';
import { cn } from '@/lib/utils';
import type { ActivityListRow, Team } from '@/lib/realisasi/types';

export interface QueueTableProps {
  track: Team;
  rows: ActivityListRow[];
  /** Server-rendered expanded content per activity id (Detail + preview + actions). */
  expanded: Record<string, ReactNode>;
  caption: string;
}

const COLS = 9;

/**
 * Verification queue (Design §3.5): SLA-sorted rows (red first, sorted server-side). Each row
 * expands inline; the toggle is a real button (Enter / Space) with aria-expanded + aria-controls,
 * and clicking anywhere on the row (outside links/buttons) toggles too.
 */
export function QueueTable({ track, rows, expanded, caption }: QueueTableProps) {
  const [open, setOpen] = useState<Set<string>>(() => new Set(rows.length === 1 && rows[0] ? [rows[0].id] : []));

  function toggle(id: string) {
    setOpen((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  return (
    <div className="overflow-x-auto rounded-lg border bg-card" role="region" aria-label={caption} tabIndex={0}>
      <table className="w-full min-w-[1000px] text-sm" data-testid={`queue-${track}`}>
        <caption className="sr-only">{caption}. Tekan Enter pada tombol baris untuk menampilkan detail.</caption>
        <thead className="bg-muted/60 text-left">
          <tr className="border-b">
            <th scope="col" className="w-10 px-2">
              <span className="sr-only">Detail</span>
            </th>
            {['SLA', 'Kode', 'Nama', 'Unit', 'Jenis', 'Mitra', 'Tanggal', track === 'partnership' ? 'Diajukan' : 'Menunggu sejak'].map((h) => (
              <th key={h} scope="col" className="h-10 px-3 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => {
            const isOpen = open.has(r.id);
            const panelId = `queue-panel-${r.id}`;
            const days = track === 'partnership' ? r.partnership_sla_days : r.mobility_sla_days;
            const level = track === 'partnership' ? r.partnership_sla_level : r.mobility_sla_level;
            const since = track === 'partnership' ? r.partnership_since : r.mobility_since;
            return (
              <Fragment key={r.id}>
                <tr
                  className={cn('cursor-pointer border-b hover:bg-muted/40', isOpen && 'bg-muted/40')}
                  data-testid="queue-row"
                  data-code={r.code}
                  onClick={(e) => {
                    if ((e.target as HTMLElement).closest('a,button,input,select,textarea')) return;
                    toggle(r.id);
                  }}
                >
                  <td className="px-2 py-2 align-top">
                    <button
                      type="button"
                      aria-expanded={isOpen}
                      aria-controls={panelId}
                      onClick={() => toggle(r.id)}
                      data-testid="queue-toggle"
                      className="inline-flex h-8 w-8 items-center justify-center rounded-md hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                    >
                      <ChevronRight className={cn('h-4 w-4 transition-transform', isOpen && 'rotate-90')} aria-hidden="true" />
                      <span className="sr-only">
                        {isOpen ? 'Sembunyikan' : 'Tampilkan'} detail {r.code}
                      </span>
                    </button>
                  </td>
                  <td className="whitespace-nowrap px-3 py-2.5 align-top">
                    {days !== null && level ? <SlaChip days={days} level={level} /> : '–'}
                  </td>
                  <td className="whitespace-nowrap px-3 py-2.5 align-top font-mono text-xs">
                    <Link href={`/realisasi/kegiatan/${r.id}`} className="underline-offset-4 hover:underline">
                      {r.code}
                    </Link>
                  </td>
                  <td className="max-w-[280px] px-3 py-2.5 align-top font-medium">
                    {r.name}
                    <span className="mt-1 block">
                      <TrackChips partnership={r.partnership_status} mobility={r.mobility_status} />
                    </span>
                  </td>
                  <td className="max-w-[200px] px-3 py-2.5 align-top">
                    <UnitCell row={r} />
                  </td>
                  <td className="max-w-[180px] px-3 py-2.5 align-top">{r.type_name}</td>
                  <td className="max-w-[200px] px-3 py-2.5 align-top">
                    <PartnerCell row={r} />
                  </td>
                  <td className="px-3 py-2.5 align-top">
                    <DateRange start={r.start_date} end={r.end_date} />
                  </td>
                  <td className="whitespace-nowrap px-3 py-2.5 align-top">
                    {formatDateTime(track === 'partnership' ? r.submitted_at : since)}
                  </td>
                </tr>
                <tr id={panelId} hidden={!isOpen} className="border-b bg-muted/20" data-testid="queue-panel">
                  <td colSpan={COLS} className="p-4">
                    {isOpen ? (expanded[r.id] ?? <p className="text-sm text-muted-foreground">Detail tidak tersedia.</p>) : null}
                  </td>
                </tr>
              </Fragment>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
