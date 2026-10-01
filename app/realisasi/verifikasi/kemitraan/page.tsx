import Link from 'next/link';
import { EmptyState } from '@/components/realisasi/empty-state';
import { ExportButton } from '@/components/realisasi/export-button';
import { Forbidden } from '@/components/realisasi/forbidden';
import { PageHeader } from '@/components/realisasi/page-header';
import { ActivityDetailSummary } from '@/components/realisasi/activity/detail-summary';
import { IaIrPreview } from '@/components/realisasi/verify/file-preview';
import { PartnershipActions } from '@/components/realisasi/verify/partnership-actions';
import { DuplicateActions } from '@/components/realisasi/verify/duplicate-actions';
import { QueueTable } from '@/components/realisasi/verify/queue-table';
import { withUser } from '@/lib/db';
import { can, requireUser } from '@/lib/session';
import { listActivities } from '@/lib/realisasi/queries/activities';
import { getActivityDetail } from '@/lib/realisasi/queries/activity';
import type { ActivityDetail } from '@/lib/realisasi/types';

export const metadata = { title: 'Verifikasi Kemitraan · SIM Realisasi' };

/** Expanded rows are prefetched for the first N queue entries (queues are small in practice). */
const PREFETCH = 50;

export default async function KemitraanQueuePage() {
  const user = await requireUser();
  if (!can(user, 'verify.partnership')) return <Forbidden />;

  const { rows, details } = await withUser(user.id, async (tx) => {
    const rows = await listActivities(tx, user, { queue: 'partnership' });
    const details: Record<string, ActivityDetail | null> = {};
    for (const r of rows.slice(0, PREFETCH)) details[r.id] = await getActivityDetail(tx, r.id);
    return { rows, details };
  });

  const expanded = Object.fromEntries(
    Object.entries(details).map(([id, d]) => [
      id,
      d ? (
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
      ) : null,
    ]),
  );

  return (
    <div className="space-y-4">
      <PageHeader
        title="Verifikasi Kemitraan"
        description="Antrean jalur Kemitraan, diurutkan dari SLA terlama (merah lebih dulu). Buka baris untuk memeriksa Detail serta IA/IR."
        actions={<ExportButton kind="activities" params={{ queue: 'partnership' }} />}
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
        <QueueTable track="partnership" rows={rows} expanded={expanded} caption="Antrean Verifikasi Kemitraan" />
      )}
    </div>
  );
}
