/**
 * Expanded verification-queue rows (Design §3.5: Detail + preview + actions in the row).
 * SERVER ONLY. Used by the queue pages for the first rows and by `loadQueuePanel` (server action)
 * to lazy-load any further row on first expand (frontend review M-8).
 */
import type { ReactNode } from 'react';
import Link from 'next/link';
import { FileText } from 'lucide-react';
import { ConflictList } from '@/components/realisasi/verify/conflict-list';
import { MobilityActions } from '@/components/realisasi/verify/mobility-actions';
import { ParticipantDiffTable } from '@/components/realisasi/verify/participant-diff-table';
import type { Tx } from '@/lib/db';
import { getActivityDetail, getParticipantVersion } from '@/lib/realisasi/queries/activity';
import { DIRECTION_LABEL } from '@/lib/realisasi/status';
import type { ActivityDetail, ParticipantVersion } from '@/lib/realisasi/types';

/** Rows whose panel is rendered with the page; later rows load on first expand. */
export const QUEUE_PREFETCH = 20;

interface Review {
  detail: ActivityDetail;
  version: ParticipantVersion | null;
  previous: ParticipantVersion | null;
}

export async function mobilityPanel(tx: Tx, id: string): Promise<ReactNode | null> {
  const detail = await getActivityDetail(tx, id);
  if (!detail) return null;
  // Version under review = latest `pending`; compare with the previous non-draft version.
  const versions = [...detail.participants.versions].sort((a, b) => b.version - a.version);
  const pending = versions.find((v) => v.status === 'pending') ?? versions.find((v) => v.status !== 'draft');
  const prev = pending ? versions.find((v) => v.version < pending.version && v.status !== 'draft') : undefined;
  const rv: Review = {
    detail,
    version: pending ? await getParticipantVersion(tx, id, pending.version) : null,
    previous: prev ? await getParticipantVersion(tx, id, prev.version) : null,
  };
  return <MobilityPanel rv={rv} />;
}

function MobilityBundleLink({ detail }: { detail: ActivityDetail }) {
  const bundle = detail.files.find((f) => f.kind === 'mobility_bundle' && f.is_current);
  return bundle ? (
    <a
      href={bundle.href}
      target="_blank"
      rel="noopener noreferrer"
      className="inline-flex items-center gap-1.5 text-sm font-medium text-primary underline underline-offset-4"
    >
      <FileText className="h-4 w-4" aria-hidden /> PDF transkrip, poster &amp; dokumentasi ({bundle.filename})
    </a>
  ) : (
    <p className="text-sm text-danger-fg">PDF transkrip, poster &amp; dokumentasi belum diunggah.</p>
  );
}

function MobilityPanel({ rv }: { rv: Review }) {
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-x-6 gap-y-1 text-sm">
        <span>
          <span className="text-muted-foreground">Jenis: </span>
          {rv.detail.agenda.name} ({DIRECTION_LABEL[rv.detail.direction]})
        </span>
        <span>
          <span className="text-muted-foreground">Unit: </span>
          {rv.detail.submitter_unit.name}
        </span>
        {rv.detail.revision.mobility ? (
          <span>
            <span className="text-muted-foreground">Revisi sebelumnya: </span>
            {rv.detail.revision.mobility.note}
          </span>
        ) : null}
      </div>
      <MobilityBundleLink detail={rv.detail} />
      {rv.detail.conflicts.length > 0 ? (
        <section aria-label="Duplikat mahasiswa" className="space-y-2 rounded-md border border-renewal-line bg-renewal-subtle p-3">
          <h4 className="text-sm font-semibold">Duplikat mahasiswa ({rv.detail.flags.conflicts_open} menunggu keputusan)</h4>
          <ConflictList conflicts={rv.detail.conflicts} canResolve={rv.detail.permissions.can_mobility_verify} currentActivityId={rv.detail.id} />
        </section>
      ) : null}
      {rv.version ? (
        <ParticipantDiffTable version={rv.version} previous={rv.previous} />
      ) : (
        <p className="text-sm text-muted-foreground">Versi peserta yang diajukan tidak ditemukan.</p>
      )}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <MobilityActions
          activityId={rv.detail.id}
          code={rv.detail.code}
          version={rv.version}
          previous={rv.previous}
          permissions={rv.detail.permissions}
          conflictsOpen={rv.detail.flags.conflicts_open}
        />
        <Link href={`/realisasi/kegiatan/${rv.detail.id}?tab=peserta`} className="text-sm font-medium text-primary underline underline-offset-4">
          Buka halaman detail {rv.detail.code}
        </Link>
      </div>
    </div>
  );
}
