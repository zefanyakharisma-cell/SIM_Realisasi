import type { ReactNode } from 'react';
import Link from 'next/link';
import { EmptyState } from '@/components/realisasi/empty-state';
import { ExportButton } from '@/components/realisasi/export-button';
import { Forbidden } from '@/components/realisasi/forbidden';
import { PageHeader } from '@/components/realisasi/page-header';
import { ConflictList } from '@/components/realisasi/verify/conflict-list';
import { QueueTable } from '@/components/realisasi/verify/queue-table';
import { QUEUE_PREFETCH, mobilityPanel } from '@/components/realisasi/verify/queue-panels';
import { withUser } from '@/lib/db';
import { can, requireUser } from '@/lib/session';
import { listActivities } from '@/lib/realisasi/queries/activities';
import { getConflicts } from '@/lib/realisasi/queries/reports';

type SP = Record<string, string | string[] | undefined>;

export const metadata = { title: 'Verifikasi Mobilitas · SIM Realisasi' };

export default async function MobilitasQueuePage(props: { searchParams: Promise<SP> }) {
  const user = await requireUser();
  if (!can(user, 'verify.mobility')) return <Forbidden />;

  const sp = await props.searchParams;
  const showResolved = sp.konflik === 'semua';
  const { rows, expanded, conflicts } = await withUser(user.id, async (tx) => {
    const rows = await listActivities(tx, user, { queue: 'mobility' });
    const conflicts = await getConflicts(tx, { status: showResolved ? null : 'open' });
    const expanded: Record<string, ReactNode> = {};
    for (const r of rows.slice(0, QUEUE_PREFETCH)) expanded[r.id] = await mobilityPanel(tx, r.id);
    return { rows, expanded, conflicts };
  });

  return (
    <div className="space-y-4">
      <PageHeader
        title="Verifikasi Mobilitas"
        description="Kegiatan mobilitas yang perlu diproses, diurutkan dari pengajuan terlama, serta mahasiswa yang diklaim oleh dua unit. Buka baris untuk melihat peserta, PDF mobilitas, dan perubahan terhadap versi sebelumnya."
        actions={
          <div className="flex flex-wrap gap-2">
            <ExportButton kind="activities" params={{ queue: 'mobility' }} />
            <ExportButton kind="conflicts" label="Ekspor duplikat" />
          </div>
        }
      />
      <section id="duplikat" aria-labelledby="duplikat-title" className="scroll-mt-24 space-y-3 rounded-lg border p-4">
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <h2 id="duplikat-title" className="text-base font-semibold">
            Duplikat Mahasiswa{' '}
            <span className="font-normal text-muted-foreground" data-testid="conflicts-total">
              ({conflicts.filter((c) => c.status === 'open').length} menunggu keputusan)
            </span>
          </h2>
          <Link
            href={showResolved ? '/realisasi/verifikasi/mobilitas#duplikat' : '/realisasi/verifikasi/mobilitas?konflik=semua#duplikat'}
            className="text-sm font-medium text-primary underline underline-offset-4"
          >
            {showResolved ? 'Tampilkan yang terbuka saja' : 'Tampilkan juga yang sudah diputuskan'}
          </Link>
        </div>
        <p className="text-sm text-muted-foreground">
          Mahasiswa yang sama diklaim oleh dua unit pada kegiatan dengan tanggal yang beririsan. Periksa PDF masing-masing kegiatan lalu
          pilih kegiatan tempat mahasiswa dihitung. Klaim oleh unit yang sama pada dua kegiatan tidak dianggap duplikat (dihitung di keduanya).
        </p>
        <ConflictList conflicts={conflicts} canResolve />
      </section>
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
