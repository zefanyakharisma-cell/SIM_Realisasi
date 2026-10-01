/** Participant version selector `v1 · v2 (disetujui)` (Design §3.4). Server-safe links. */
import Link from 'next/link';
import { PSET_STATUS_LABEL } from '@/lib/realisasi/status';
import type { ParticipantVersionSummary } from '@/lib/realisasi/types';
import { cn } from '@/lib/utils';

export function VersionSelector({ activityId, versions, current }: { activityId: string; versions: ParticipantVersionSummary[]; current: number | null }) {
  const sorted = [...versions].sort((a, b) => a.version - b.version);
  if (sorted.length === 0) return null;
  return (
    <nav aria-label="Versi data peserta">
      <ul className="flex flex-wrap items-center gap-2 text-sm">
        {sorted.map((v) => (
          <li key={v.id}>
            <Link
              href={`/realisasi/kegiatan/${activityId}?tab=peserta&v=${v.version}`}
              aria-current={v.version === current ? 'true' : undefined}
              data-testid={`version-v${v.version}`}
              className={cn(
                'inline-flex items-center gap-1 rounded-full border px-3 py-1',
                v.version === current ? 'border-primary bg-primary text-primary-foreground' : 'hover:bg-accent',
              )}
            >
              v{v.version} <span className="text-xs opacity-90">({PSET_STATUS_LABEL[v.status].toLowerCase()})</span>
            </Link>
          </li>
        ))}
      </ul>
    </nav>
  );
}
