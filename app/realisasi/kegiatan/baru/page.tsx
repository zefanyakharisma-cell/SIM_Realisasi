import Link from 'next/link';
import { redirect } from 'next/navigation';
import { Button } from '@/components/ui/button';
import { EmptyState } from '@/components/realisasi/empty-state';
import { Forbidden } from '@/components/realisasi/forbidden';
import { PageHeader } from '@/components/realisasi/page-header';
import { ActivityDetailSummary } from '@/components/realisasi/activity/detail-summary';
import { FileList } from '@/components/realisasi/activity/file-list';
import { detailDocumentsAsOptions, detailToPayload, latestVersionSummary } from '@/components/realisasi/activity/convert';
import { participantRequirements } from '@/components/realisasi/activity/labels';
import { DetailForm } from '@/components/realisasi/wizard/detail-form';
import { FilesEditor } from '@/components/realisasi/wizard/files-editor';
import { ParticipantsStep } from '@/components/realisasi/wizard/participants-step';
import { SubmitPanel } from '@/components/realisasi/wizard/submit-panel';
import { WizardNav } from '@/components/realisasi/wizard/wizard-nav';
import { WizardShell } from '@/components/realisasi/wizard/wizard-shell';
import { withUser } from '@/lib/db';
import { can, getToday, requireUser } from '@/lib/session';
import { getActivityDetail, getParticipantVersion, isUuid } from '@/lib/realisasi/queries/activity';
import { getFormOptions } from '@/lib/realisasi/queries/lookups';

export const metadata = { title: 'Kegiatan Baru · SIM Realisasi' };

type SP = Record<string, string | string[] | undefined>;

function one(v: string | string[] | undefined): string | undefined {
  return Array.isArray(v) ? v[0] : v;
}

/** Submission wizard `/realisasi/kegiatan/baru?draft=<id>&step=1..4` (CONTRACTS §7, Design §3.3). */
export default async function NewActivityPage(props: { searchParams: Promise<SP> }) {
  const user = await requireUser();
  if (!can(user, 'activity.create')) return <Forbidden />;

  const sp = await props.searchParams;
  const draftParam = one(sp.draft);
  const draftId = draftParam && isUuid(draftParam) ? draftParam : null;
  const requestedStep = Math.min(4, Math.max(1, Number(one(sp.step)) || 1));
  const step = draftId ? requestedStep : 1;
  const today = await getToday();

  const { options, detail, version, savedAt } = await withUser(user.id, async (tx) => {
    const options = await getFormOptions(tx);
    if (!draftId) return { options, detail: null, version: null, savedAt: null };
    const detail = await getActivityDetail(tx, draftId);
    const version = detail && step === 2 ? await getParticipantVersion(tx, draftId) : null;
    // L-3: show "Tersimpan sebagai draf · HH:MM" for an existing draft right away.
    const [row] = detail
      ? await tx<{ updated_at: string | null }[]>`select updated_at from realisasi.v_activities where id = ${draftId}::uuid`
      : [];
    return { options, detail, version, savedAt: row?.updated_at ?? null };
  });

  if (draftId && !detail) {
    return (
      <EmptyState
        title="Draf tidak ditemukan"
        description="Draf mungkin sudah dihapus atau Anda tidak memiliki akses."
        action={
          <Button asChild>
            <Link href="/realisasi/kegiatan/baru">Buat kegiatan baru</Link>
          </Button>
        }
      />
    );
  }
  if (detail && detail.status !== 'draft') {
    redirect(detail.permissions.can_submit ? `/realisasi/kegiatan/${detail.id}/revisi` : `/realisasi/kegiatan/${detail.id}`);
  }
  if (detail && !detail.permissions.can_edit_draft) return <Forbidden />;

  const required = participantRequirements(detail?.type);
  const latest = detail ? latestVersionSummary(detail) : null;
  const failing = (detail?.checklist ?? []).filter((c) => !c.ok).map((c) => c.code);
  const invalidSteps = detail
    ? [
        ...(failing.some((c) => ['R07_REQUIRED_FIELD', 'R07_AGREEMENT_REQUIRED', 'R04_AGREEMENT_NOT_VALID', 'R08_END_AFTER_TODAY', 'R09_NO_ACADEMIC_YEAR'].includes(c)) ? [1] : []),
        ...(failing.some((c) => c.startsWith('R11') || c.startsWith('R12') || c.startsWith('R16') || c.startsWith('R17') || c.startsWith('R19')) ? [2] : []),
        ...(failing.some((c) => c === 'R07_IA_REQUIRED' || c === 'R07_IR_REQUIRED') ? [3] : []),
      ].filter((n) => n < step)
    : [];

  return (
    <div className="mx-auto max-w-5xl">
      <PageHeader
        title={detail ? `Draf ${detail.code}` : 'Laporkan Kegiatan Baru'}
        description={detail ? detail.name : 'Laporkan realisasi kegiatan kerja sama unit Anda. Draf tersimpan otomatis setelah langkah Detail.'}
      />
      <WizardShell draftId={detail?.id ?? null} step={step} savedAt={savedAt} invalidSteps={invalidSteps}>
        {step === 1 && (
          <DetailForm
            key={detail?.id ?? 'new'}
            mode="wizard"
            activityId={detail?.id ?? null}
            initial={detail ? detailToPayload(detail) : null}
            initialDocuments={detail ? detailDocumentsAsOptions(detail) : []}
            options={options}
            lockedUnitId={user.role === 'submitter' ? user.unitId : detail ? detail.submitter_unit.id : null}
            today={today}
          />
        )}

        {step === 2 && detail && (
          <section aria-labelledby="step2-title" className="space-y-4">
            <h2 id="step2-title" className="text-lg font-semibold">
              Peserta
            </h2>
            <p className="text-sm text-muted-foreground">
              Jenis <span className="font-medium text-foreground">{detail.type.name}</span>:{' '}
              {required.internal
                ? 'wajib minimal satu mahasiswa PETRA.'
                : required.inbound
                  ? 'wajib minimal satu mahasiswa inbound (dengan institusi asal dan transkrip).'
                  : required.any
                    ? 'wajib mengisi data peserta.'
                    : 'data peserta opsional; bila diisi, kegiatan juga diverifikasi tim Mobilitas.'}
            </p>
            <ParticipantsStep
              activityId={detail.id}
              initialVersion={version}
              countries={options.countries}
              required={required}
            />
          </section>
        )}

        {step === 3 && detail && (
          <section aria-labelledby="step3-title" className="space-y-4">
            <h2 id="step3-title" className="text-lg font-semibold">
              Berkas
            </h2>
            <FilesEditor activityId={detail.id} files={detail.files} />
            <WizardNav draftId={detail.id} step={3} />
          </section>
        )}

        {step === 4 && detail && (
          <section aria-labelledby="step4-title" className="space-y-8">
            <h2 id="step4-title" className="text-lg font-semibold">
              Tinjau &amp; Ajukan
            </h2>
            <div className="rounded-lg border p-4">
              <ActivityDetailSummary detail={detail} />
            </div>
            <div className="grid gap-4 md:grid-cols-2">
              <div className="rounded-lg border p-4">
                <h3 className="mb-2 text-sm font-semibold">Peserta</h3>
                {latest ? (
                  <dl className="grid grid-cols-[1fr_auto] gap-1 text-sm" data-testid="review-counts">
                    <dt>Mahasiswa PETRA</dt>
                    <dd className="font-medium">{latest.internal_students}</dd>
                    <dt>Mahasiswa inbound</dt>
                    <dd className="font-medium">{latest.inbound_students}</dd>
                    <dt>Pegawai PETRA</dt>
                    <dd className="font-medium">{latest.staff}</dd>
                  </dl>
                ) : (
                  <p className="text-sm text-muted-foreground">Belum ada data peserta.</p>
                )}
              </div>
              <div className="rounded-lg border p-4">
                <h3 className="mb-2 text-sm font-semibold">Berkas</h3>
                <FileList files={detail.files} />
              </div>
            </div>
            <div className="rounded-lg border p-4">
              <SubmitPanel activityId={detail.id} checklist={detail.checklist} />
            </div>
            <WizardNav draftId={detail.id} step={4} />
          </section>
        )}
      </WizardShell>
    </div>
  );
}
