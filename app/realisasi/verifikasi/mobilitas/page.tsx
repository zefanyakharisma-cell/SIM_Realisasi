import Link from 'next/link';
import { EmptyState } from '@/components/realisasi/empty-state';
import { ExportButton } from '@/components/realisasi/export-button';
import { Forbidden } from '@/components/realisasi/forbidden';
import { PageHeader } from '@/components/realisasi/page-header';
import { MobilityActions } from '@/components/realisasi/verify/mobility-actions';
import { ParticipantDiffTable } from '@/components/realisasi/verify/participant-diff-table';
import { QueueTable } from '@/components/realisasi/verify/queue-table';
import { withUser } from '@/lib/db';
import { can, requireUser } from '@/lib/session';
import { listActivities } from '@/lib/realisasi/queries/activities';
import { getActivityDetail, getParticipantVersion } from '@/lib/realisasi/queries/activity';
import { DIRECTION_LABEL } from '@/lib/realisasi/status';
import type { ActivityDetail, ParticipantVersion } from '@/lib/realisasi/types';

export const metadata = { title: 'Verifikasi Mobilitas · SIM Realisasi' };

const PREFETCH = 50;

interface Review {
  detail: ActivityDetail;
  version: ParticipantVersion | null;
  previous: ParticipantVersion | null;
}

export default async function MobilitasQueuePage() {
  const user = await requireUser();
  if (!can(user, 'verify.mobility')) return <Forbidden />;

  const { rows, reviews } = await withUser(user.id, async (tx) => {
    const rows = await listActivities(tx, user, { queue: 'mobility' });
    const reviews: Record<string, Review | null> = {};
    for (const r of rows.slice(0, PREFETCH)) {
      const detail = await getActivityDetail(tx, r.id);
      if (!detail) {
        reviews[r.id] = null;
        continue;
      }
      // Version under review = latest `pending`; compare with the previous non-draft version.
      const versions = [...detail.participants.versions].sort((a, b) => b.version - a.version);
      const pending = versions.find((v) => v.status === 'pending') ?? versions.find((v) => v.status !== 'draft');
      const prev = pending ? versions.find((v) => v.version < pending.version && v.status !== 'draft') : undefined;
      reviews[r.id] = {
        detail,
        version: pending ? await getParticipantVersion(tx, r.id, pending.version) : null,
        previous: prev ? await getParticipantVersion(tx, r.id, prev.version) : null,
      };
    }
    return { rows, reviews };
  });

  const expanded = Object.fromEntries(
    Object.entries(reviews).map(([id, rv]) => [
      id,
      rv ? (
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
      ) : null,
    ]),
  );

  return (
    <div className="space-y-4">
      <PageHeader
        title="Verifikasi Mobilitas"
        description="Antrean jalur Mobilitas, diurutkan dari SLA terlama. Buka baris untuk melihat peserta beserta perubahan terhadap versi sebelumnya."
        actions={<ExportButton kind="activities" params={{ queue: 'mobility' }} />}
      />
      <p className="text-sm text-muted-foreground">
        <span data-testid="list-total" className="font-semibold text-foreground">
          {rows.length}
        </span>{' '}
        kegiatan menunggu verifikasi
      </p>
      {rows.length === 0 ? (
        <EmptyState title="Tidak ada antrean verifikasi. 🎉" />
      ) : (
        <QueueTable track="mobility" rows={rows} expanded={expanded} caption="Antrean Verifikasi Mobilitas" />
      )}
    </div>
  );
}
