/**
 * Status language components (Design §2). Server-safe (no hooks). Status is never conveyed by colour
 * alone: every element carries visible text, a dot, and a description that is available to mouse,
 * keyboard and screen-reader users (focusable `Hint` tooltip or sr-only text — frontend review M-9).
 */
import { Badge } from '@/components/ui/badge';
import { Hint } from '@/components/realisasi/hint';
import { cn } from '@/lib/utils';
import {
  ACTIVITY_STATUS_DESCRIPTION,
  ACTIVITY_STATUS_LABEL,
  ACTIVITY_STATUS_TONE,
  FLAG_DESCRIPTION,
  FLAG_LABEL,
  FLAG_TONE,
  PSET_STATUS_LABEL,
  PSET_STATUS_TONE,
  TRACK_LABEL,
  TRACK_STATUS_LABEL,
  TRACK_STATUS_TONE,
  type FlagKey,
  type Tone,
} from '@/lib/realisasi/status';
import type { ActivityStatus, PsetStatus, Team, TrackStatus } from '@/lib/realisasi/types';

/** Signal hues from the PCU Design System (see ui/badge.tsx for the tone → token map). */
const DOT: Record<Tone, string> = {
  neutral: 'bg-neutral',
  blue: 'bg-info',
  amber: 'bg-pending',
  green: 'bg-success',
  red: 'bg-danger',
  purple: 'bg-renewal',
  yellow: 'bg-warning',
};

export function ToneDot({ tone, className }: { tone: Tone; className?: string }) {
  return <span aria-hidden="true" className={cn('inline-block size-1.5 shrink-0 rounded-full', DOT[tone], className)} />;
}

export function StatusBadge({ status, className }: { status: ActivityStatus; className?: string }) {
  return (
    <Hint content={ACTIVITY_STATUS_DESCRIPTION[status]}>
      <Badge variant={ACTIVITY_STATUS_TONE[status]} data-testid="status-badge" data-status={status} className={className}>
        <ToneDot tone={ACTIVITY_STATUS_TONE[status]} />
        {ACTIVITY_STATUS_LABEL[status]}
      </Badge>
    </Hint>
  );
}

function TrackChip({ team, status }: { team: Team; status: TrackStatus }) {
  const label = `${TRACK_LABEL[team]}: ${TRACK_STATUS_LABEL[status]}`;
  return (
    <span
      className="inline-flex items-center gap-1.5 whitespace-nowrap rounded-full border bg-background px-2 py-0.5 text-xs text-foreground"
      title={label}
      data-testid={`track-chip-${team}`}
      data-status={status}
    >
      {TRACK_LABEL[team]}
      <ToneDot tone={TRACK_STATUS_TONE[status]} />
      <span className="sr-only">: {TRACK_STATUS_LABEL[status]}</span>
    </span>
  );
}

/** `Mobilitas ●` — dot colour = track status; nothing for kegiatan without Mobility verification (Revisi V.1). */
export function TrackChips({ mobility, className }: { mobility: TrackStatus; className?: string }) {
  if (mobility === 'not_required') return null;
  return (
    <span className={cn('inline-flex flex-wrap items-center gap-1', className)}>
      <TrackChip team="mobility" status={mobility} />
    </span>
  );
}

/** Outline pill for Terlambat / Di luar lingkup / Duplikat mahasiswa / Tambahan susulan. */
export function FlagPill({ flag, title, className, plain }: { flag: FlagKey; title?: string; className?: string; plain?: boolean }) {
  const badge = (
    <Badge variant={FLAG_TONE[flag]} appearance="outline" data-flag={flag} className={className}>
      {FLAG_LABEL[flag]}
    </Badge>
  );
  // `plain`: inside a link/button, which carries the description itself (no nested focus stop).
  return plain ? badge : <Hint content={title ?? FLAG_DESCRIPTION[flag]}>{badge}</Hint>;
}

export function PsetBadge({ status, className }: { status: PsetStatus; className?: string }) {
  return (
    <Badge variant={PSET_STATUS_TONE[status]} data-pset-status={status} className={className}>
      <ToneDot tone={PSET_STATUS_TONE[status]} />
      {PSET_STATUS_LABEL[status]}
    </Badge>
  );
}
