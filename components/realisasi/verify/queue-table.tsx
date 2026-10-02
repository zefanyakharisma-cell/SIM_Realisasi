'use client';

import { Fragment, useState, type ReactNode } from 'react';
import Link from 'next/link';
import { ChevronRight } from 'lucide-react';
import { FlagPill } from '@/components/realisasi/status-badge';
import { DateRange, PartnerCell, UnitCell } from '@/components/realisasi/list/activity-table';
import { formatDateTime } from '@/lib/realisasi/format';
import { loadQueuePanel } from '@/lib/realisasi/actions/queue';
import { cn } from '@/lib/utils';
import { DIRECTION_LABEL } from '@/lib/realisasi/status';
import type { ActivityListRow, Team } from '@/lib/realisasi/types';

export interface QueueTableProps {
  track: Team;
  rows: ActivityListRow[];
  /**
   * Server-rendered expanded content for the first rows (Detail + preview + actions). Rows not in
   * this map load their panel on first expand (frontend review M-8).
   */
  expanded: Record<string, ReactNode>;
  caption: string;
}

const COLS = 9;

/**
 * Verification queue (Design §3.5): longest-waiting first (sorted server-side; no SLA since Revisi V.1). Each row
 * expands inline; the toggle is a real button (Enter / Space) with aria-expanded + aria-controls,
 * and clicking anywhere on the row (outside links/buttons) toggles too.
 */
export function QueueTable({ track, rows, expanded, caption }: QueueTableProps) {
  const [open, setOpen] = useState<Set<string>>(() => new Set(rows.length === 1 && rows[0] ? [rows[0].id] : []));
  const [loaded, setLoaded] = useState<Record<string, ReactNode | 'loading' | 'error'>>({});

  async function load(id: string) {
    setLoaded((m) => ({ ...m, [id]: 'loading' }));
    try {
      const node = await loadQueuePanel(track, id);
      setLoaded((m) => ({ ...m, [id]: node ?? 'error' }));
    } catch {
      setLoaded((m) => ({ ...m, [id]: 'error' }));
    }
  }

  function toggle(id: string) {
    const opening = !open.has(id);
    setOpen((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
    if (opening && !(id in expanded) && (loaded[id] === undefined || loaded[id] === 'error')) void load(id);
  }

  function panel(r: ActivityListRow): ReactNode {
    if (r.id in expanded && expanded[r.id]) return expanded[r.id];
    const l = loaded[r.id];
    if (l === undefined || l === 'loading') {
      return (
        <p className="text-sm text-muted-foreground" role="status">
          Memuat detail {r.code}…
        </p>
      );
    }
    if (l === 'error' || (r.id in expanded && !expanded[r.id])) {
      return (
        <p className="text-sm text-muted-foreground">
          Detail tidak dapat dimuat.{' '}
          <Link href={`/realisasi/kegiatan/${r.id}`} className="font-medium text-primary underline underline-offset-4">
            Buka halaman detail {r.code}
          </Link>
        </p>
      );
    }
    return l;
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
            {['Kode', 'Nama', 'Unit', 'Jenis', 'Mitra', 'Tanggal', 'Menunggu sejak', 'Duplikat'].map((h) => (
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
                  <td className="whitespace-nowrap px-3 py-2.5 align-top font-mono text-xs">
                    <Link href={`/realisasi/kegiatan/${r.id}`} className="underline-offset-4 hover:underline">
                      {r.code}
                    </Link>
                  </td>
                  <td className="max-w-[280px] px-3 py-2.5 align-top font-medium">
                    {r.name}
                  </td>
                  <td className="max-w-[200px] px-3 py-2.5 align-top">
                    <UnitCell row={r} />
                  </td>
                  <td className="max-w-[180px] px-3 py-2.5 align-top">
                    {r.agenda_name ?? '–'}
                    <span className="block text-xs text-muted-foreground">{DIRECTION_LABEL[r.direction]}</span>
                  </td>
                  <td className="max-w-[200px] px-3 py-2.5 align-top">
                    <PartnerCell row={r} />
                  </td>
                  <td className="px-3 py-2.5 align-top">
                    <DateRange start={r.start_date} end={r.end_date} />
                  </td>
                  <td className="whitespace-nowrap px-3 py-2.5 align-top">
                    {formatDateTime(r.mobility_since ?? r.submitted_at)}
                  </td>
                  <td className="whitespace-nowrap px-3 py-2.5 align-top">
                    {r.open_conflicts > 0 ? <FlagPill flag="conflict" title={`${r.open_conflicts} mahasiswa menunggu keputusan`} /> : '–'}
                  </td>
                </tr>
                <tr id={panelId} hidden={!isOpen} className="border-b bg-muted/20" data-testid="queue-panel">
                  <td colSpan={COLS} className="p-4">
                    {isOpen ? panel(r) : null}
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
