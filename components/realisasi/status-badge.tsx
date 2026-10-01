/**
 * Status language components (Design §2). Server-safe (no hooks). Status is never conveyed by colour
 * alone: every element carries visible text, a dot, and a `title` tooltip / sr-only description.
 */
import { Badge } from '@/components/ui/badge';
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
  SLA_LEVEL_LABEL,
  SLA_TONE,
  TRACK_LABEL,
  TRACK_STATUS_LABEL,
  TRACK_STATUS_TONE,
  slaText,
  type FlagKey,
  type Tone,
} from '@/lib/realisasi/status';
import type { ActivityStatus, PsetStatus, SlaLevel, Team, TrackStatus } from '@/lib/realisasi/types';

const DOT: Record<Tone, string> = {
  neutral: 'bg-slate-400',
  blue: 'bg-blue-600',
  amber: 'bg-amber-500',
  green: 'bg-green-600',
  red: 'bg-red-600',
  purple: 'bg-purple-600',
  yellow: 'bg-yellow-500',
};

export function ToneDot({ tone, className }: { tone: Tone; className?: string }) {
  return <span aria-hidden="true" className={cn('inline-block size-2 shrink-0 rounded-full', DOT[tone], className)} />;
}

export function StatusBadge({ status, className }: { status: ActivityStatus; className?: string }) {
  return (
    <Badge
      variant={ACTIVITY_STATUS_TONE[status]}
      data-testid="status-badge"
      data-status={status}
      title={ACTIVITY_STATUS_DESCRIPTION[status]}
      className={className}
    >
      <ToneDot tone={ACTIVITY_STATUS_TONE[status]} />
      {ACTIVITY_STATUS_LABEL[status]}
    </Badge>
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

/** `Kemitraan ●` `Mobilitas ●` — dot colour = track status. */
export function TrackChips({ partnership, mobility, className }: { partnership: TrackStatus; mobility: TrackStatus; className?: string }) {
  return (
    <span className={cn('inline-flex flex-wrap items-center gap-1', className)}>
      <TrackChip team="partnership" status={partnership} />
      <TrackChip team="mobility" status={mobility} />
    </span>
  );
}

/** Outline pill for Terlambat / Di luar lingkup / Duplikat? / Tambahan susulan. */
export function FlagPill({ flag, title, className }: { flag: FlagKey; title?: string; className?: string }) {
  return (
    <Badge variant={FLAG_TONE[flag]} appearance="outline" title={title ?? FLAG_DESCRIPTION[flag]} data-flag={flag} className={className}>
      {FLAG_LABEL[flag]}
    </Badge>
  );
}

/** 'SLA 4 hari' — yellow fill when yellow, red fill when red, neutral otherwise. */
export function SlaChip({ days, level, className }: { days: number; level: SlaLevel; className?: string }) {
  const tone = SLA_TONE[level];
  return (
    <Badge
      variant={tone}
      className={cn(level === 'red' && 'border-red-700 bg-red-600 text-white', className)}
      title={`${days} hari kerja sejak menunggu verifikasi (level ${SLA_LEVEL_LABEL[level]})`}
      data-sla={level}
    >
      {slaText(days)}
      {level !== 'ok' ? <span className="sr-only"> (level {SLA_LEVEL_LABEL[level]})</span> : null}
    </Badge>
  );
}

export function PsetBadge({ status, className }: { status: PsetStatus; className?: string }) {
  return (
    <Badge variant={PSET_STATUS_TONE[status]} data-pset-status={status} className={className}>
      <ToneDot tone={PSET_STATUS_TONE[status]} />
      {PSET_STATUS_LABEL[status]}
    </Badge>
  );
}
