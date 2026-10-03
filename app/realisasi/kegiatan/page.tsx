import Link from 'next/link';
import { Plus } from 'lucide-react';
import { buttonVariants } from '@/components/ui/button';
import { EmptyState } from '@/components/realisasi/empty-state';
import { ExportButton } from '@/components/realisasi/export-button';
import { PageHeader } from '@/components/realisasi/page-header';
import { ActivityTable } from '@/components/realisasi/list/activity-table';
import { ColumnFilterRow } from '@/components/realisasi/list/column-filters';
import { ListToolbar } from '@/components/realisasi/list/list-toolbar';
import { withUser } from '@/lib/db';
import { can, getToday, requireUser } from '@/lib/session';
import { getSettingsMap } from '@/lib/realisasi/queries/reports';
import { ACTIVITY_LIST_LIMIT, getActivityFilterOptions, listActivities } from '@/lib/realisasi/queries/activities';
import {
  PRESETS,
  activityFiltersToSearchParams,
  hasActiveFilters,
  parseActivityFilters,
} from '@/lib/realisasi/schemas/filters';

export const metadata = { title: 'Kegiatan · SIM Realisasi' };

type SearchParams = Record<string, string | string[] | undefined>;

export default async function KegiatanPage(props: { searchParams: Promise<SearchParams> }) {
  const user = await requireUser();
  const filters = parseActivityFilters(await props.searchParams);
  // The list never runs as a queue; queue views live under /realisasi/verifikasi/*.
  delete filters.queue;

  const [{ rows, options, reminderDays }, today] = await Promise.all([
    withUser(user.id, async (tx) => ({
      rows: await listActivities(tx, user, filters),
      options: await getActivityFilterOptions(tx),
      reminderDays: Number((await getSettingsMap(tx)).deadline_reminder_before_days ?? 7) || 7,
    })),
    getToday(),
  ]);

  const filtered = hasActiveFilters(filters);
  const exportParams = activityFiltersToSearchParams(filters);
  const presets = user.role === 'viewer' ? PRESETS.filter((p) => p !== 'mine') : PRESETS;
  const canCreate = can(user, 'activity.create');

  const description =
    user.role === 'submitter'
      ? `Kegiatan unit ${user.unitName ?? 'Anda'} (termasuk sebagai unit lain).`
      : user.role === 'viewer'
        ? 'Kegiatan yang sudah terverifikasi.'
        : 'Semua kegiatan realisasi kerja sama.';

  const empty = filtered ? (
    <EmptyState
      className="m-4"
      title="Tidak ada kegiatan yang cocok dengan filter."
      description="Ubah atau hapus filter untuk melihat kegiatan lain."
      action={
        <Link href="/realisasi/kegiatan" className={buttonVariants({ variant: 'outline', size: 'sm' })}>
          Hapus filter
        </Link>
      }
    />
  ) : user.role === 'submitter' ? (
    <EmptyState
      className="m-4"
      title="Belum ada kegiatan."
      description="Laporkan realisasi kerja sama pertama unit Anda."
      action={
        <Link href="/realisasi/kegiatan/baru" className={buttonVariants({ size: 'sm' })}>
          <Plus aria-hidden="true" />
          Kegiatan Baru
        </Link>
      }
    />
  ) : (
    <EmptyState className="m-4" title="Belum ada kegiatan." />
  );

  return (
    <div className="space-y-4">
      <PageHeader
        title="Kegiatan"
        description={description}
        actions={
          <>
            <ExportButton kind="activities" params={exportParams} />
            {canCreate ? (
              <Link href="/realisasi/kegiatan/baru" className={buttonVariants({ size: 'sm' })} data-testid="nav-kegiatan-baru-cta">
                <Plus aria-hidden="true" />
                Kegiatan Baru
              </Link>
            ) : null}
          </>
        }
      />
      <ListToolbar filters={filters} presets={presets} total={rows.length} limited={rows.length >= ACTIVITY_LIST_LIMIT} />
      <ActivityTable
        rows={rows}
        caption="Daftar kegiatan"
        filterRow={<ColumnFilterRow filters={filters} options={options} />}
        empty={empty}
        deadline={{ today, reminderDays }}
        viewer={{ id: user.id, isAdmin: user.role === 'io_admin' }}
      />
    </div>
  );
}
