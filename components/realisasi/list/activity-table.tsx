import type { ReactNode } from 'react';
import Link from 'next/link';
import { DeleteDraftButton } from '@/components/realisasi/activity/delete-draft-button';
import { CountryFlag } from '@/components/realisasi/country-flag';
import { FlagPill, StatusBadge, TrackChips } from '@/components/realisasi/status-badge';
import { Badge } from '@/components/ui/badge';
import { Hint } from '@/components/realisasi/hint';
import { daysBetween, formatDate } from '@/lib/realisasi/format';
import { DIRECTION_LABEL, FLAG_DESCRIPTION } from '@/lib/realisasi/status';
import type { ActivityListRow } from '@/lib/realisasi/types';

/** Partner cell: flag + first partner name, "+n" for the rest (full list in title). */
export function PartnerCell({ row }: { row: Pick<ActivityListRow, 'partner_names' | 'country_codes'> }) {
  const first = row.partner_names[0];
  if (!first) return <span className="text-muted-foreground">–</span>;
  const more = row.partner_names.length - 1;
  return (
    <span className="flex min-w-0 items-center gap-1.5" title={row.partner_names.join(', ')}>
      <span className="flex shrink-0 gap-0.5">
        {row.country_codes.slice(0, 3).map((c) => (
          <CountryFlag key={c} code={c} />
        ))}
      </span>
      <span className="truncate">{first}</span>
      {more > 0 ? <span className="shrink-0 text-xs text-muted-foreground">+{more}</span> : null}
    </span>
  );
}

export function UnitCell({ row }: { row: Pick<ActivityListRow, 'submitter_unit_name' | 'unit_names'> }) {
  const others = row.unit_names.filter((n) => n !== row.submitter_unit_name);
  return (
    <span title={row.unit_names.join(', ')}>
      {row.submitter_unit_name}
      {others.length > 0 ? <span className="text-xs text-muted-foreground"> +{others.length} unit</span> : null}
    </span>
  );
}

export function DateRange({ start, end }: { start: string; end: string }) {
  return (
    <span className="whitespace-nowrap">
      {formatDate(start)}
      {end !== start ? (
        <>
          <span aria-hidden="true"> – </span>
          <span className="sr-only"> sampai </span>
          {formatDate(end)}
        </>
      ) : null}
    </span>
  );
}

/** Reporting-deadline context for draft rows (requirements review M-2, R-62). */
export interface DeadlineContext {
  today: string;
  /** `settings.deadline_reminder_before_days`: amber from this many days before the deadline. */
  reminderDays: number;
}

/** Draft deadline pill: "Lewat tenggat" (red) or "Tenggat 13 Sep 2026" (amber, inside the reminder window). */
function DeadlinePill({ row, ctx }: { row: ActivityListRow; ctx: DeadlineContext }) {
  if (row.status !== 'draft' || !row.reporting_deadline) return null;
  const left = daysBetween(ctx.today, row.reporting_deadline);
  if (left < 0) {
    return (
      <Hint content={`Batas pelaporan ${formatDate(row.reporting_deadline)} telah lewat ${-left} hari; kegiatan akan ditandai Terlambat saat diajukan.`}>
        <Badge variant="red" appearance="outline" data-flag="deadline_overdue">
          Lewat tenggat
        </Badge>
      </Hint>
    );
  }
  if (left > ctx.reminderDays) return null;
  return (
    <Hint content={`Batas pelaporan ${formatDate(row.reporting_deadline)} (${left === 0 ? 'hari ini' : `${left} hari lagi`}).`}>
      <Badge variant="amber" appearance="outline" data-flag="deadline_soon">
        Tenggat {formatDate(row.reporting_deadline)}
      </Badge>
    </Hint>
  );
}

/** Flags column (Design §2): Terlambat / tenggat draf, Di luar lingkup, Duplikat mahasiswa (Revisi V.1: no SLA). */
export function FlagsCell({ row, deadline }: { row: ActivityListRow; deadline?: DeadlineContext }) {
  const items: ReactNode[] = [];
  if (row.is_late) items.push(<FlagPill key="late" flag="late" />);
  if (deadline && row.status === 'draft' && row.reporting_deadline) items.push(<DeadlinePill key="deadline" row={row} ctx={deadline} />);
  if (row.out_of_scope) items.push(<FlagPill key="scope" flag="out_of_scope" />);
  if (row.open_conflicts > 0) {
    items.push(
      <Link
        key="conflict"
        href={`/realisasi/kegiatan/${row.id}#duplikat`}
        className="rounded-full focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        title={FLAG_DESCRIPTION.conflict}
      >
        <FlagPill flag="conflict" plain />
        <span className="sr-only">: {FLAG_DESCRIPTION.conflict}. Lihat duplikat.</span>
      </Link>,
    );
  }
  if (items.length === 0) return <span className="sr-only">Tidak ada penanda</span>;
  return <div className="flex flex-wrap gap-1">{items}</div>;
}

export interface ActivityTableProps {
  rows: ActivityListRow[];
  /** Optional per-column filter row (client component rendering one `<tr>`). */
  filterRow?: ReactNode;
  caption: string;
  /** Rendered in the body when `rows` is empty (spans all columns). */
  empty?: ReactNode;
  /** Enables the draft deadline flags (M-2). */
  deadline?: DeadlineContext;
  /** Shows "Hapus draf" on drafts this viewer may delete (R-15: own drafts; IO Admin: all). */
  viewer?: { id: string; isAdmin: boolean };
}

export const ACTIVITY_TABLE_COLUMNS = 10;

/**
 * Kegiatan list table (Design §3.2): Kode · Nama · Jenis · Unit · Mitra · Tanggal · Semester ·
 * Status · Jalur (track chips) · Penanda. Server-safe (no hooks).
 */
export function ActivityTable({ rows, filterRow, caption, empty, deadline, viewer }: ActivityTableProps) {
  const canDelete = (r: ActivityListRow) => r.status === 'draft' && !!viewer && (viewer.isAdmin || r.created_by === viewer.id);
  return (
    <div className="overflow-x-auto rounded-lg border bg-card" role="region" aria-label={caption} tabIndex={0}>
      <table className="w-full min-w-[1100px] text-sm" data-testid="activity-table">
        <caption className="sr-only">{caption}</caption>
        <thead className="bg-muted/60 text-left">
          <tr className="border-b">
            {['Kode', 'Nama', 'Jenis', 'Unit', 'Mitra', 'Tanggal', 'Semester', 'Status', 'Jalur', 'Penanda'].map((h) => (
              <th key={h} scope="col" className="h-10 px-3 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                {h}
              </th>
            ))}
          </tr>
          {filterRow}
        </thead>
        <tbody>
          {rows.length === 0 && empty ? (
            <tr>
              <td colSpan={ACTIVITY_TABLE_COLUMNS} className="p-0">
                {empty}
              </td>
            </tr>
          ) : null}
          {rows.map((r) => (
            <tr key={r.id} className="border-b last:border-0 hover:bg-muted/40" data-testid="activity-row">
              <td className="whitespace-nowrap px-3 py-2.5 align-top font-mono text-xs">
                <Link href={`/realisasi/kegiatan/${r.id}`} className="underline-offset-4 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
                  {r.code}
                </Link>
              </td>
              <td className="max-w-[280px] px-3 py-2.5 align-top">
                <Link href={`/realisasi/kegiatan/${r.id}`} className="font-medium hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
                  {r.name}
                </Link>
              </td>
              <td className="max-w-[180px] px-3 py-2.5 align-top [overflow-wrap:anywhere]">
                {r.agenda_name ?? '–'}
                <span className="block text-xs text-muted-foreground">{DIRECTION_LABEL[r.direction]}</span>
              </td>
              <td className="max-w-[200px] px-3 py-2.5 align-top">
                <UnitCell row={r} />
              </td>
              <td className="max-w-[220px] px-3 py-2.5 align-top">
                <PartnerCell row={r} />
              </td>
              <td className="px-3 py-2.5 align-top">
                <DateRange start={r.start_date} end={r.end_date} />
              </td>
              <td className="whitespace-nowrap px-3 py-2.5 align-top">{r.semester_label ?? '–'}</td>
              <td className="px-3 py-2.5 align-top">
                <div className="flex items-center gap-1">
                  <StatusBadge status={r.status} />
                  {canDelete(r) ? <DeleteDraftButton activityId={r.id} code={r.code} compact /> : null}
                </div>
              </td>
              <td className="px-3 py-2.5 align-top">
                {r.status === 'draft' ? (
                  // L-1: a draft has not entered any verification track yet.
                  <span className="text-xs text-muted-foreground">Belum diajukan</span>
                ) : (
                  <TrackChips mobility={r.mobility_status} />
                )}
              </td>
              <td className="px-3 py-2.5 align-top">
                <FlagsCell row={r} deadline={deadline} />
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
