import type { ReactNode } from 'react';
import { EmptyState } from '@/components/realisasi/empty-state';
import { ExportButton } from '@/components/realisasi/export-button';
import { Forbidden } from '@/components/realisasi/forbidden';
import { PageHeader } from '@/components/realisasi/page-header';
import { QueueTable } from '@/components/realisasi/verify/queue-table';
import { QUEUE_PREFETCH, mobilityPanel } from '@/components/realisasi/verify/queue-panels';
import { withUser } from '@/lib/db';
import { can, requireUser } from '@/lib/session';
import { listActivities } from '@/lib/realisasi/queries/activities';

export const metadata = { title: 'Verifikasi Mobilitas · SIM Realisasi' };

export default async function MobilitasQueuePage() {
  const user = await requireUser();
  if (!can(user, 'verify.mobility')) return <Forbidden />;

  const { rows, expanded } = await withUser(user.id, async (tx) => {
    const rows = await listActivities(tx, user, { queue: 'mobility' });
    const expanded: Record<string, ReactNode> = {};
    for (const r of rows.slice(0, QUEUE_PREFETCH)) expanded[r.id] = await mobilityPanel(tx, r.id);
    return { rows, expanded };
  });

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
