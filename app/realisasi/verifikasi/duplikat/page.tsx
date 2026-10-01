import Link from 'next/link';
import { EmptyState } from '@/components/realisasi/empty-state';
import { ExportButton } from '@/components/realisasi/export-button';
import { Forbidden } from '@/components/realisasi/forbidden';
import { PageHeader } from '@/components/realisasi/page-header';
import { CandidateCard } from '@/components/realisasi/duplicates/candidate-card';
import { withUser } from '@/lib/db';
import { can, requireUser } from '@/lib/session';
import { DUP_STATUSES, countDuplicateCandidates, listDuplicateCandidates, parseDupStatus } from '@/lib/realisasi/queries/duplicates';
import { DUP_STATUS_LABEL } from '@/lib/realisasi/status';
import { cn } from '@/lib/utils';

export const metadata = { title: 'Duplikat · SIM Realisasi' };

const EMPTY_TEXT = {
  open: 'Tidak ada kandidat duplikat yang perlu ditinjau.',
  linked: 'Belum ada kegiatan yang ditautkan.',
  dismissed: 'Belum ada kandidat yang ditandai bukan duplikat.',
} as const;

export default async function DuplikatPage(props: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const user = await requireUser();
  if (!can(user, 'duplicates.view')) return <Forbidden />;
  const status = parseDupStatus((await props.searchParams).status);

  const { rows, counts } = await withUser(user.id, async (tx) => ({
    rows: await listDuplicateCandidates(tx, { status }),
    counts: await countDuplicateCandidates(tx),
  }));
  const canManage = can(user, 'duplicates.manage');
  const canUnlink = user.role === 'io_admin';

  return (
    <div className="space-y-4">
      <PageHeader
        title="Duplikat"
        description="Kandidat kegiatan yang sama dilaporkan lebih dari sekali (kerja sama sama, tanggal berdekatan, nama mirip)."
        actions={<ExportButton kind="duplicates" params={{ status }} />}
      />
      <nav aria-label="Status kandidat" className="flex flex-wrap gap-2">
        {DUP_STATUSES.map((s) => (
          <Link
            key={s}
            href={s === 'open' ? '/realisasi/verifikasi/duplikat' : `/realisasi/verifikasi/duplikat?status=${s}`}
            aria-current={s === status ? 'page' : undefined}
            className={cn(
              'inline-flex min-h-8 items-center rounded-full border px-3 text-xs font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
              s === status ? 'border-primary bg-primary text-primary-foreground' : 'bg-background hover:bg-muted',
            )}
          >
            {DUP_STATUS_LABEL[s]} ({counts[s]})
          </Link>
        ))}
      </nav>
      <p className="text-sm text-muted-foreground">
        <span data-testid="list-total" className="font-semibold text-foreground">
          {rows.length}
        </span>{' '}
        kandidat
      </p>
      {rows.length === 0 ? (
        <EmptyState title={EMPTY_TEXT[status]} />
      ) : (
        <div className="space-y-4">
          {rows.map((c) => (
            <CandidateCard key={c.id} c={c} canManage={canManage} canUnlink={canUnlink} />
          ))}
        </div>
      )}
    </div>
  );
}
