import Link from 'next/link';
import { Pencil, Users } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { EmptyState } from '@/components/realisasi/empty-state';
import { PsetBadge } from '@/components/realisasi/status-badge';
import { ActivityHeader } from '@/components/realisasi/activity/activity-header';
import { ActivityTabs, type ActivityTab } from '@/components/realisasi/activity/activity-tabs';
import { DeleteDraftButton } from '@/components/realisasi/activity/delete-draft-button';
import { ActivityDetailSummary } from '@/components/realisasi/activity/detail-summary';
import { FileList } from '@/components/realisasi/activity/file-list';
import { LogList } from '@/components/realisasi/activity/log-list';
import { ParticipantTable } from '@/components/realisasi/activity/participant-table';
import { RevisionBanner } from '@/components/realisasi/activity/revision-banner';
import { VersionSelector } from '@/components/realisasi/activity/version-selector';
import { DuplicateActions } from '@/components/realisasi/verify/duplicate-actions';
import { MobilityActions } from '@/components/realisasi/verify/mobility-actions';
import { PartnershipActions } from '@/components/realisasi/verify/partnership-actions';
import { withUser } from '@/lib/db';
import { requireUser } from '@/lib/session';
import { formatDateTime } from '@/lib/realisasi/format';
import { getActivityDetail, getParticipantVersion } from '@/lib/realisasi/queries/activity';
import type { ParticipantVersion } from '@/lib/realisasi/types';

export const metadata = { title: 'Detail Kegiatan · SIM Realisasi' };

type SP = Record<string, string | string[] | undefined>;
const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v);
const TABS: ActivityTab[] = ['detail', 'peserta', 'berkas', 'riwayat'];

/** Activity detail `/realisasi/kegiatan/[id]?tab=&v=` (Design §3.4, CONTRACTS §7). */
export default async function ActivityPage(props: { params: Promise<{ id: string }>; searchParams: Promise<SP> }) {
  const user = await requireUser();
  const { id } = await props.params;
  const sp = await props.searchParams;
  const tabParam = one(sp.tab) as ActivityTab | undefined;
  const requestedVersion = Number(one(sp.v)) || undefined;

  const data = await withUser(user.id, async (tx) => {
    const detail = await getActivityDetail(tx, id);
    if (!detail) return null;
    const p = detail.permissions;
    let shown: ParticipantVersion | null = null;
    let review: ParticipantVersion | null = null;
    let previous: ParticipantVersion | null = null;
    if (p.can_view_participants && detail.participants.versions.length > 0) {
      const nonDraft = detail.participants.versions.filter((v) => v.status !== 'draft').sort((a, b) => b.version - a.version);
      const pending = nonDraft.find((v) => v.status === 'pending');
      const defaultVersion =
        detail.participants.versions.find((v) => v.status === 'approved')?.version ?? nonDraft[0]?.version ?? detail.participants.versions[0]?.version;
      shown = await getParticipantVersion(tx, id, requestedVersion ?? defaultVersion);
      if (p.can_mobility_verify) {
        const target = pending ?? nonDraft[0];
        if (target) {
          review = target.version === shown?.version ? shown : await getParticipantVersion(tx, id, target.version);
          const prev = nonDraft.find((v) => v.version < target.version);
          previous = prev ? await getParticipantVersion(tx, id, prev.version) : null;
        }
      }
    }
    return { detail, shown, review, previous };
  });

  if (!data) {
    return (
      <EmptyState
        title="Kegiatan tidak ditemukan"
        description="Kegiatan mungkin sudah dihapus atau Anda tidak memiliki akses."
        action={
          <Button asChild variant="outline">
            <Link href="/realisasi/kegiatan">Kembali ke daftar kegiatan</Link>
          </Button>
        }
      />
    );
  }

  const { detail, shown, review, previous } = data;
  const p = detail.permissions;
  const showPeserta = p.can_view_participants || detail.participants.counts !== null || detail.participants.versions.length > 0;
  const tabs = [
    { id: 'detail' as const, label: 'Detail' },
    ...(showPeserta ? [{ id: 'peserta' as const, label: 'Peserta' }] : []),
    { id: 'berkas' as const, label: 'Berkas' },
    ...(p.can_view_log ? [{ id: 'riwayat' as const, label: 'Riwayat' }] : []),
  ];
  const tab: ActivityTab = tabParam && TABS.includes(tabParam) && tabs.some((t) => t.id === tabParam) ? tabParam : 'detail';
  const isUnitDraft = detail.status === 'draft' && p.can_edit_draft;
  const inRevision = detail.status === 'revision_requested' && p.can_submit;

  const actions = (
    <>
      {isUnitDraft && (
        <Button asChild size="sm">
          <Link href={`/realisasi/kegiatan/baru?draft=${detail.id}&step=1`} data-testid="continue-draft">
            <Pencil aria-hidden /> Lanjutkan pengisian
          </Link>
        </Button>
      )}
      {p.can_delete_draft && <DeleteDraftButton activityId={detail.id} code={detail.code} />}
      <PartnershipActions activityId={detail.id} code={detail.code} permissions={p} />
      <MobilityActions activityId={detail.id} code={detail.code} version={review} previous={previous} permissions={p} />
      <DuplicateActions activityId={detail.id} permissions={p} duplicates={detail.duplicates} />
      {p.can_edit_verified_detail && (
        <Button asChild size="sm" variant="outline">
          <Link href={`/realisasi/kegiatan/${detail.id}/edit`} data-testid="edit-verified-detail">
            <Pencil aria-hidden /> Edit Detail/Berkas
          </Link>
        </Button>
      )}
      {p.can_edit_verified_participants && (
        <Button asChild size="sm" variant="outline">
          <Link href={`/realisasi/kegiatan/${detail.id}/peserta-edit`} data-testid="edit-verified-participants">
            <Users aria-hidden /> Edit Peserta
          </Link>
        </Button>
      )}
    </>
  );

  return (
    <div className="space-y-6">
      <ActivityHeader detail={detail} actions={actions} />
      {(inRevision || (detail.status === 'revision_requested' && user.role === 'submitter')) && <RevisionBanner detail={detail} />}

      <ActivityTabs activityId={detail.id} current={tab} tabs={tabs} />

      <div role="region" aria-label={tabs.find((t) => t.id === tab)?.label}>
        {tab === 'detail' && <ActivityDetailSummary detail={detail} />}

        {tab === 'peserta' && (
          <div className="space-y-4">
            {p.can_view_participants && shown ? (
              <>
                <VersionSelector activityId={detail.id} versions={detail.participants.versions} current={shown.version} />
                <div className="flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
                  <span className="font-medium text-foreground">Versi v{shown.version}</span>
                  <PsetBadge status={shown.status} />
                  {shown.submitted_at && <span>diajukan {formatDateTime(shown.submitted_at)}{shown.submitted_by_name ? ` oleh ${shown.submitted_by_name}` : ''}</span>}
                  {shown.reviewed_at && <span>· ditinjau {formatDateTime(shown.reviewed_at)}{shown.reviewed_by_name ? ` oleh ${shown.reviewed_by_name}` : ''}</span>}
                  {shown.status !== 'draft' && shown.status !== 'pending' && <span>· hanya baca</span>}
                </div>
                {shown.review_note && <p className="rounded-md bg-amber-50 p-3 text-sm text-amber-900">Catatan IO: {shown.review_note}</p>}
                <ParticipantTable version={shown} />
              </>
            ) : detail.participants.counts ? (
              <dl className="grid max-w-sm grid-cols-[1fr_auto] gap-1 rounded-md border p-4 text-sm" data-testid="participant-counts">
                <dt>Versi</dt>
                <dd>v{detail.participants.counts.version}</dd>
                <dt>Mahasiswa PETRA</dt>
                <dd className="font-medium">{detail.participants.counts.internal_students}</dd>
                <dt>Mahasiswa inbound</dt>
                <dd className="font-medium">{detail.participants.counts.inbound_students}</dd>
                <dt>Pegawai PETRA</dt>
                <dd className="font-medium">{detail.participants.counts.staff}</dd>
                <dd className="col-span-2 mt-2 text-xs text-muted-foreground">Nama peserta hanya dapat dilihat oleh unit, tim Mobilitas, dan Admin IO.</dd>
              </dl>
            ) : (
              <p className="text-sm text-muted-foreground">Belum ada data peserta.</p>
            )}
          </div>
        )}

        {tab === 'berkas' && <FileList files={detail.files} showHistory />}

        {tab === 'riwayat' && p.can_view_log && <LogList log={detail.log} />}
      </div>
    </div>
  );
}
