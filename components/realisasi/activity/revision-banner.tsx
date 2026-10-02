/**
 * Amber revision banner for the unit (Design §3.4): who requested, note, which track, "Perbaiki sekarang".
 * Server-safe.
 */
import Link from 'next/link';
import { AlertTriangle } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Button } from '@/components/ui/button';
import { formatDateTime } from '@/lib/realisasi/format';
import { TRACK_LABEL } from '@/lib/realisasi/status';
import type { ActivityDetail, Team } from '@/lib/realisasi/types';

export function RevisionBanner({ detail, showAction = true }: { detail: ActivityDetail; showAction?: boolean }) {
  const tracks = (['mobility'] as Team[]).filter((t) => detail.mobility_status === 'revision_requested' && detail.revision[t]);
  if (tracks.length === 0) return null;
  return (
    <Alert variant="warning" data-testid="revision-banner">
      <AlertTriangle aria-hidden />
      <AlertTitle>Perlu revisi dari unit</AlertTitle>
      <AlertDescription>
        <ul className="mt-2 space-y-2">
          {tracks.map((t) => {
            const r = detail.revision[t]!;
            return (
              <li key={t}>
                <span className="font-medium">Jalur {TRACK_LABEL[t]}</span>
                <span className="text-amber-900/80">
                  {' '}
                  — diminta oleh {r.requested_by_name ?? 'IO'} pada {formatDateTime(r.requested_at)}
                </span>
                {r.note && <p className="mt-0.5 whitespace-pre-line">“{r.note}”</p>}
              </li>
            );
          })}
        </ul>
        {showAction && detail.permissions.can_submit && (
          <Button asChild size="sm" className="mt-3">
            <Link href={`/realisasi/kegiatan/${detail.id}/revisi`} data-testid="fix-now">
              Perbaiki sekarang
            </Link>
          </Button>
        )}
      </AlertDescription>
    </Alert>
  );
}
