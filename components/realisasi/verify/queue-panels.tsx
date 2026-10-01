/**
 * Expanded verification-queue rows (Design §3.5: Detail + preview + actions in the row).
 * SERVER ONLY. Used by the queue pages for the first rows and by `loadQueuePanel` (server action)
 * to lazy-load any further row on first expand (frontend review M-8).
 */
import type { ReactNode } from 'react';
import Link from 'next/link';
import { ActivityDetailSummary } from '@/components/realisasi/activity/detail-summary';
import { DuplicateActions } from '@/components/realisasi/verify/duplicate-actions';
import { IaIrPreview } from '@/components/realisasi/verify/file-preview';
import { MobilityActions } from '@/components/realisasi/verify/mobility-actions';
import { PartnershipActions } from '@/components/realisasi/verify/partnership-actions';
import { ParticipantDiffTable } from '@/components/realisasi/verify/participant-diff-table';
import type { Tx } from '@/lib/db';
import { getActivityDetail, getParticipantVersion } from '@/lib/realisasi/queries/activity';
import { DIRECTION_LABEL } from '@/lib/realisasi/status';
import type { ActivityDetail, ParticipantVersion } from '@/lib/realisasi/types';

/** Rows whose panel is rendered with the page; later rows load on first expand. */
export const QUEUE_PREFETCH = 20;

export async function partnershipPanel(tx: Tx, id: string): Promise<ReactNode | null> {
  const d = await getActivityDetail(tx, id);
  return d ? <PartnershipPanel d={d} /> : null;
}

function PartnershipPanel({ d }: { d: ActivityDetail }) {
  return (
    <div className="space-y-4">
      <div className="grid gap-4 xl:grid-cols-2">
        <div className="min-w-0 rounded-md border bg-background p-4">
          <ActivityDetailSummary detail={d} compact />
        </div>
        <div className="min-w-0 rounded-md border bg-background p-4">
          <IaIrPreview files={d.files} code={d.code} />
        </div>
      </div>
      {d.duplicates.some((x) => x.status === 'open') ? (
        <DuplicateActions activityId={d.id} permissions={{ ...d.permissions, can_unlink_duplicate: false }} duplicates={d.duplicates} />
      ) : null}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <PartnershipActions activityId={d.id} code={d.code} permissions={d.permissions} />
        <Link href={`/realisasi/kegiatan/${d.id}`} className="text-sm font-medium text-primary underline underline-offset-4">
          Buka halaman detail {d.code}
        </Link>
      </div>
    </div>
  );
}

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

function MobilityPanel({ rv }: { rv: Review }) {
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-x-6 gap-y-1 text-sm">
        <span>
          <span className="text-muted-foreground">Jenis: </span>
          {rv.detail.type.name} ({DIRECTION_LABEL[rv.detail.type.direction]})
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
        />
        <Link href={`/realisasi/kegiatan/${rv.detail.id}?tab=peserta`} className="text-sm font-medium text-primary underline underline-offset-4">
          Buka halaman detail {rv.detail.code}
        </Link>
      </div>
    </div>
  );
}
