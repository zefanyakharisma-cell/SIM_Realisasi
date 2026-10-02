import Link from 'next/link';
import { Button } from '@/components/ui/button';
import { EmptyState } from '@/components/realisasi/empty-state';
import { Forbidden } from '@/components/realisasi/forbidden';
import { PageHeader } from '@/components/realisasi/page-header';
import { detailDocumentsAsOptions, detailToPayload } from '@/components/realisasi/activity/convert';
import { participantRequirements } from '@/components/realisasi/activity/labels';
import { ParticipantTable } from '@/components/realisasi/activity/participant-table';
import { RevisionBanner } from '@/components/realisasi/activity/revision-banner';
import { DetailForm } from '@/components/realisasi/wizard/detail-form';
import { FilesEditor } from '@/components/realisasi/wizard/files-editor';
import { RevisionWorkspace } from '@/components/realisasi/wizard/revision-workspace';
import { SaveStatusProvider } from '@/components/realisasi/wizard/save-status';
import { withUser } from '@/lib/db';
import { getToday, requireUser } from '@/lib/session';
import { getActivityDetail, getParticipantVersion } from '@/lib/realisasi/queries/activity';
import { getFormOptions } from '@/lib/realisasi/queries/lookups';
import type { ParticipantVersion } from '@/lib/realisasi/types';

export const metadata = { title: 'Revisi Kegiatan · SIM Realisasi' };

/** Unit revision view (Revisi V.1): the Mobility team asked for changes; Detail, Berkas and Peserta are editable. */
export default async function RevisionPage(props: { params: Promise<{ id: string }> }) {
  const user = await requireUser();
  const { id } = await props.params;
  const today = await getToday();

  const data = await withUser(user.id, async (tx) => {
    const detail = await getActivityDetail(tx, id);
    if (!detail) return null;
    const options = await getFormOptions(tx);
    let latest: ParticipantVersion | null = null;
    let reviewed: ParticipantVersion | null = null;
    if (detail.permissions.can_edit_participants) {
      latest = await getParticipantVersion(tx, id);
      const rev = detail.participants.versions
        .filter((v) => v.status === 'revision_requested')
        .sort((a, b) => b.version - a.version)[0];
      if (rev) reviewed = rev.version === latest?.version ? latest : await getParticipantVersion(tx, id, rev.version);
    }
    return { detail, options, latest, reviewed };
  });

  if (!data) {
    return <EmptyState title="Kegiatan tidak ditemukan" description="Kegiatan mungkin sudah dihapus atau Anda tidak memiliki akses." />;
  }
  const { detail, options, latest, reviewed } = data;
  const p = detail.permissions;
  if (detail.status === 'draft') {
    return (
      <EmptyState
        title="Kegiatan masih berupa draf"
        action={
          <Button asChild>
            <Link href={`/realisasi/kegiatan/baru?draft=${detail.id}`}>Lanjutkan pengisian</Link>
          </Button>
        }
      />
    );
  }
  if (!p.can_submit) {
    if (detail.status !== 'revision_requested') {
      return (
        <EmptyState
          title="Tidak ada revisi yang perlu dikerjakan"
          description="Kegiatan ini tidak sedang menunggu revisi dari unit."
          action={
            <Button asChild variant="outline">
              <Link href={`/realisasi/kegiatan/${detail.id}`}>Lihat kegiatan</Link>
            </Button>
          }
        />
      );
    }
    return <Forbidden />;
  }

  const required = participantRequirements({ is_mobility: detail.agenda.is_mobility, direction: detail.direction });

  // SaveStatusProvider links the editors to "Ajukan ulang": unsaved Detail edits block it and
  // pending participant edits are flushed before submitting (frontend review M-1).
  return (
    <SaveStatusProvider>
      <div className="mx-auto max-w-5xl space-y-8">
        <PageHeader
          title={`Revisi ${detail.code}`}
          description={detail.name}
          actions={
            <Button asChild variant="outline" size="sm">
              <Link href={`/realisasi/kegiatan/${detail.id}`}>Lihat detail kegiatan</Link>
            </Button>
          }
        />
        <RevisionBanner detail={detail} showAction={false} />

        {p.can_edit_detail && (
          <>
            <section aria-labelledby="rev-detail" className="space-y-4">
              <h2 id="rev-detail" className="text-lg font-semibold">
                Detail
              </h2>
              <p className="text-sm text-muted-foreground">
                Setiap penyimpanan dicatat di Riwayat. Bila Jenis diubah menjadi kegiatan non-mobilitas, kegiatan langsung tercatat saat
                diajukan ulang.
              </p>
              <DetailForm
                mode="revision"
                activityId={detail.id}
                initial={detailToPayload(detail)}
                initialDocuments={detailDocumentsAsOptions(detail)}
                options={options}
                lockedUnitId={detail.submitter_unit.id}
                today={today}
              />
            </section>
            <section aria-labelledby="rev-files" className="space-y-4">
              <h2 id="rev-files" className="text-lg font-semibold">
                Berkas
              </h2>
              <FilesEditor activityId={detail.id} files={detail.files} isMobility={detail.agenda.is_mobility} />
            </section>
          </>
        )}

        {reviewed && (
          <details className="rounded-lg border p-4">
            <summary className="cursor-pointer text-sm font-medium">
              Versi v{reviewed.version} yang diminta revisi (hanya baca)
            </summary>
            <div className="mt-4">
              <ParticipantTable version={reviewed} />
            </div>
          </details>
        )}

        <RevisionWorkspace
          activityId={detail.id}
          participants={p.can_edit_participants ? { version: latest, countries: options.countries, required } : null}
          checklist={detail.checklist}
        />
      </div>
    </SaveStatusProvider>
  );
}
