/**
 * Activity detail header: code, name, status badge, Mobility chip and flags (Design §3.4; no SLA since Revisi V.1).
 * Server-safe. `actions` is the role-based action bar rendered by the page.
 */
import { FlagPill, StatusBadge, TrackChips } from '@/components/realisasi/status-badge';
import type { ActivityDetail } from '@/lib/realisasi/types';

export function ActivityHeader({ detail, actions }: { detail: ActivityDetail; actions?: React.ReactNode }) {
  const { flags } = detail;
  return (
    <header className="space-y-3 border-b pb-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0 space-y-1">
          <p className="font-mono text-sm text-muted-foreground" data-testid="activity-code">
            {detail.code}
          </p>
          <h1 className="text-xl font-semibold leading-tight sm:text-2xl">{detail.name}</h1>
        </div>
        {actions ? (
          <div className="flex flex-wrap items-center gap-2" role="group" aria-label="Tindakan kegiatan">
            {actions}
          </div>
        ) : null}
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <StatusBadge status={detail.status} />
        {detail.status !== 'draft' && <TrackChips mobility={detail.mobility_status} />}
        {flags.late && <FlagPill flag="late" />}
        {flags.out_of_scope && <FlagPill flag="out_of_scope" />}
        {flags.conflicts_open > 0 && <FlagPill flag="conflict" title={`${flags.conflicts_open} mahasiswa juga diklaim unit lain; menunggu keputusan tim Mobilitas.`} />}
        {flags.late_addition && <FlagPill flag="late_addition" />}
      </div>
    </header>
  );
}
