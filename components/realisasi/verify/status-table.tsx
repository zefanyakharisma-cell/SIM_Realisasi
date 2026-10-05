/**
 * Read-only Mobility status list (Revisi V.1 item 7). Server-safe (no hooks).
 * - KUI view: kegiatan sent back to the unit ("Dikembalikan untuk Revisi"), each flagged "Revisi".
 * - Submitter view: the unit's own mobility kegiatan still in verification, flagged "Menunggu verifikasi" or
 *   "Revisi" (with the KUI note and a "Revisi sekarang" button).
 */
import Link from 'next/link';
import { Button } from '@/components/ui/button';
import { FlagPill } from '@/components/realisasi/status-badge';
import { DateRange, UnitCell } from '@/components/realisasi/list/activity-table';
import { formatDateTime } from '@/lib/realisasi/format';
import { DIRECTION_LABEL } from '@/lib/realisasi/status';
import type { MobilityRevisionNote } from '@/lib/realisasi/queries/activities';
import type { ActivityListRow } from '@/lib/realisasi/types';

export interface MobilityStatusTableProps {
  rows: ActivityListRow[];
  notes: Record<string, MobilityRevisionNote>;
  /** 'submitter' adds the "Revisi sekarang" action on rows in revision. */
  audience: 'kui' | 'submitter';
  caption: string;
  testId: string;
}

export function MobilityStatusTable({ rows, notes, audience, caption, testId }: MobilityStatusTableProps) {
  return (
    <div className="overflow-x-auto rounded-lg border bg-card" role="region" aria-label={caption} tabIndex={0}>
      <table className="w-full min-w-[900px] text-sm" data-testid={testId}>
        <caption className="sr-only">{caption}</caption>
        <thead className="bg-muted/60 text-left">
          <tr className="border-b">
            {['Kode', 'Nama', 'Unit', 'Jenis', 'Tanggal', 'Status', 'Catatan revisi KUI', ''].map((h, i) => (
              <th key={i} scope="col" className="h-10 px-3 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                {h || <span className="sr-only">Tindakan</span>}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => {
            const inRevision = r.status === 'revision_requested';
            const note = inRevision ? notes[r.id] : undefined;
            return (
              <tr key={r.id} className="border-b last:border-0" data-testid="status-row" data-code={r.code} data-flag={inRevision ? 'revision' : 'waiting'}>
                <td className="whitespace-nowrap px-3 py-2.5 align-top font-mono text-xs">
                  <Link href={`/realisasi/kegiatan/${r.id}`} className="underline-offset-4 hover:underline">
                    {r.code}
                  </Link>
                </td>
                <td className="max-w-[260px] px-3 py-2.5 align-top font-medium">{r.name}</td>
                <td className="max-w-[200px] px-3 py-2.5 align-top">
                  <UnitCell row={r} />
                </td>
                <td className="max-w-[180px] px-3 py-2.5 align-top">
                  {r.agenda_name ?? '–'}
                  <span className="block text-xs text-muted-foreground">{DIRECTION_LABEL[r.direction]}</span>
                </td>
                <td className="px-3 py-2.5 align-top">
                  <DateRange start={r.start_date} end={r.end_date} />
                </td>
                <td className="whitespace-nowrap px-3 py-2.5 align-top">
                  <FlagPill flag={inRevision ? 'revision' : 'waiting'} />
                  <span className="mt-1 block text-xs text-muted-foreground">
                    {inRevision ? 'Diminta ' : 'Diajukan '}
                    {formatDateTime(inRevision ? (note?.requested_at ?? r.mobility_since) : (r.mobility_since ?? r.submitted_at))}
                  </span>
                </td>
                <td className="max-w-[280px] px-3 py-2.5 align-top text-sm">{inRevision ? (note?.note ?? '–') : '–'}</td>
                <td className="whitespace-nowrap px-3 py-2.5 align-top">
                  {audience === 'submitter' && inRevision ? (
                    <Button asChild size="sm" data-testid="status-revise">
                      <Link href={`/realisasi/kegiatan/${r.id}/revisi`}>Revisi sekarang</Link>
                    </Button>
                  ) : (
                    <Button asChild size="sm" variant="outline">
                      <Link href={`/realisasi/kegiatan/${r.id}`}>Lihat</Link>
                    </Button>
                  )}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
