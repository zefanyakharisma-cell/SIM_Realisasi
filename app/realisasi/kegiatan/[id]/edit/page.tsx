import Link from 'next/link';
import { Button } from '@/components/ui/button';
import { EmptyState } from '@/components/realisasi/empty-state';
import { Forbidden } from '@/components/realisasi/forbidden';
import { PageHeader } from '@/components/realisasi/page-header';
import { detailDocumentsAsOptions, detailToPayload } from '@/components/realisasi/activity/convert';
import { DetailForm } from '@/components/realisasi/wizard/detail-form';
import { FilesEditor } from '@/components/realisasi/wizard/files-editor';
import { withUser } from '@/lib/db';
import { getToday, requireUser } from '@/lib/session';
import { getActivityDetail } from '@/lib/realisasi/queries/activity';
import { getFormOptions } from '@/lib/realisasi/queries/lookups';

export const metadata = { title: 'Edit Kegiatan Terverifikasi · SIM Realisasi' };

/** IO Partnership post-verification Detail/Berkas edit (R-29..R-31; `can_edit_verified_detail`). */
export default async function EditVerifiedPage(props: { params: Promise<{ id: string }> }) {
  const user = await requireUser();
  const { id } = await props.params;
  const today = await getToday();
  const data = await withUser(user.id, async (tx) => {
    const detail = await getActivityDetail(tx, id);
    if (!detail) return null;
    return { detail, options: await getFormOptions(tx) };
  });
  if (!data) return <EmptyState title="Kegiatan tidak ditemukan" />;
  const { detail, options } = data;
  if (!detail.permissions.can_edit_verified_detail) return <Forbidden />;

  return (
    <div className="mx-auto max-w-5xl space-y-8">
      <PageHeader
        title={`Edit ${detail.code}`}
        description={`${detail.name} — perubahan pasca-verifikasi dicatat di Riwayat dengan selisih nilai.`}
        actions={
          <Button asChild variant="outline" size="sm">
            <Link href={`/realisasi/kegiatan/${detail.id}`}>Batal</Link>
          </Button>
        }
      />
      {detail.flags.late_addition && (
        <p className="rounded-md bg-blue-50 p-3 text-sm text-blue-900">Kegiatan ini merupakan tambahan susulan pada periode yang sudah dibekukan.</p>
      )}
      <DetailForm
        mode="verified"
        activityId={detail.id}
        initial={detailToPayload(detail)}
        initialDocuments={detailDocumentsAsOptions(detail)}
        options={options}
        lockedUnitId={detail.submitter_unit.id}
        today={today}
      />
      <section aria-labelledby="edit-files" className="space-y-4">
        <h2 id="edit-files" className="text-lg font-semibold">
          Berkas
        </h2>
        <p className="text-sm text-muted-foreground">Unggahan baru langsung tersimpan sebagai versi baru dan dicatat di Riwayat.</p>
        <FilesEditor activityId={detail.id} files={detail.files} />
      </section>
    </div>
  );
}
