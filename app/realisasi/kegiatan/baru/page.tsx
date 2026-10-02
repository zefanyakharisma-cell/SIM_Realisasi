import Link from 'next/link';
import { redirect } from 'next/navigation';
import { Info } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { EmptyState } from '@/components/realisasi/empty-state';
import { Forbidden } from '@/components/realisasi/forbidden';
import { PageHeader } from '@/components/realisasi/page-header';
import { detailDocumentsAsOptions, detailToPayload } from '@/components/realisasi/activity/convert';
import { participantRequirements } from '@/components/realisasi/activity/labels';
import { DetailForm } from '@/components/realisasi/wizard/detail-form';
import { FilesEditor } from '@/components/realisasi/wizard/files-editor';
import { ParticipantsEditor } from '@/components/realisasi/wizard/participants-editor';
import { ParticipantsStep } from '@/components/realisasi/wizard/participants-step';
import { SubmitPanel } from '@/components/realisasi/wizard/submit-panel';
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

const PREVIEW_NOTE = 'Pratinjau: bagian ini dapat diisi setelah Detail disimpan sebagai draf.';

/** Before the draft exists the later sections are shown in full but read-only (native `fieldset disabled`). */
function Preview({ children }: { children: React.ReactNode }) {
  return (
    <div className="space-y-3" data-testid="section-preview">
      <p className="flex items-center gap-2 rounded-lg border border-dashed p-3 text-sm text-muted-foreground">
        <Info className="h-4 w-4 shrink-0" aria-hidden />
        {PREVIEW_NOTE}
      </p>
      <fieldset disabled className="min-w-0 opacity-75">
        {children}
      </fieldset>
    </div>
  );
}

/** Requirements shown in the Ajukan preview (the real checklist comes from `submission_checklist()`). */
const PREVIEW_CHECKLIST = [
  'R07_REQUIRED_FIELD',
  'R07_AGREEMENT_REQUIRED',
  'R08_END_AFTER_TODAY',
  'R07_IA_REQUIRED',
  'R07_IR_REQUIRED',
  'R13_MOBILITY_BUNDLE_REQUIRED',
  'R11_PARTICIPANTS_REQUIRED',
].map((code) => ({ code, ok: false, message: '' }));

/**
 * Kegiatan Baru `/realisasi/kegiatan/baru?draft=<id>` — Revisi V.1: one page, no steps. Every section is
 * visible from the start; Peserta (mobility kegiatan only), Berkas and Ajukan are read-only previews until
 * the draft exists (first "Simpan Draf"), then become editable on the same page. Edits autosave.
 */
export default async function NewActivityPage(props: { searchParams: Promise<SP> }) {
  const user = await requireUser();
  if (!can(user, 'activity.create')) return <Forbidden />;

  const sp = await props.searchParams;
  const draftParam = one(sp.draft);
  const draftId = draftParam && isUuid(draftParam) ? draftParam : null;
  const today = await getToday();

  const { options, detail, version, savedAt } = await withUser(user.id, async (tx) => {
    const options = await getFormOptions(tx);
    if (!draftId) return { options, detail: null, version: null, savedAt: null };
    const detail = await getActivityDetail(tx, draftId);
    const version = detail ? await getParticipantVersion(tx, draftId) : null;
    // L-3: show "Tersimpan sebagai draf · HH:MM" for an existing draft right away.
    const [row] = detail
      ? await tx<{ updated_at: string | null }[]>`select updated_at from realisasi.v_activity_list where id = ${draftId}::uuid`
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

  const isMobility = detail?.agenda.is_mobility ?? false;
  const required = participantRequirements(detail ? { is_mobility: isMobility, direction: detail.direction } : null);

  return (
    <div className="mx-auto max-w-5xl">
      <PageHeader
        title={detail ? `Draf ${detail.code}` : 'Laporkan Kegiatan Baru'}
        description={
          detail ? detail.name : 'Isi semua bagian di halaman ini. Draf tersimpan otomatis setelah Detail disimpan pertama kali.'
        }
      />
      <WizardShell draftId={detail?.id ?? null} savedAt={savedAt}>
        <section id="bagian-detail" aria-labelledby="bagian-detail-title" className="scroll-mt-24 space-y-4">
          <h2 id="bagian-detail-title" className="text-lg font-semibold">
            1. Detail &amp; Kerja sama
          </h2>
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
        </section>

        <section id="bagian-peserta" aria-labelledby="bagian-peserta-title" className="scroll-mt-24 space-y-4 border-t pt-8">
          <h2 id="bagian-peserta-title" className="text-lg font-semibold">
            2. Peserta
          </h2>
          {!detail ? (
            <Preview>
              <p className="mb-4 text-sm text-muted-foreground">
                Data peserta hanya diperlukan untuk kegiatan mobilitas (outbound: mahasiswa PETRA; inbound: mahasiswa inbound dengan
                institusi asal).
              </p>
              <ParticipantsEditor
                activityId=""
                initialVersion={null}
                countries={options.countries}
                required={{ any: false, internal: false, inbound: false }}
              />
            </Preview>
          ) : !isMobility ? (
            <p className="text-sm text-muted-foreground" data-testid="participants-not-needed">
              Jenis <span className="font-medium text-foreground">{detail.agenda.name}</span> bukan kegiatan mobilitas: data peserta tidak
              diperlukan dan kegiatan langsung tercatat setelah diajukan.
            </p>
          ) : (
            <>
              <p className="text-sm text-muted-foreground">
                Kegiatan mobilitas <span className="font-medium text-foreground">{detail.direction === 'inbound' ? 'inbound' : 'outbound'}</span>:{' '}
                {required.internal ? 'wajib minimal satu mahasiswa PETRA.' : 'wajib minimal satu mahasiswa inbound (dengan institusi asal).'}
              </p>
              <ParticipantsStep activityId={detail.id} initialVersion={version} countries={options.countries} required={required} />
            </>
          )}
        </section>

        <section id="bagian-berkas" aria-labelledby="bagian-berkas-title" className="scroll-mt-24 space-y-4 border-t pt-8">
          <h2 id="bagian-berkas-title" className="text-lg font-semibold">
            3. Berkas
          </h2>
          {detail ? (
            <FilesEditor activityId={detail.id} files={detail.files} isMobility={isMobility} />
          ) : (
            <Preview>
              <FilesEditor activityId="" files={[]} isMobility disabled />
            </Preview>
          )}
        </section>

        <section id="bagian-ajukan" aria-labelledby="bagian-ajukan-title" className="scroll-mt-24 space-y-4 border-t pt-8">
          <h2 id="bagian-ajukan-title" className="text-lg font-semibold">
            4. Ajukan
          </h2>
          {detail ? (
            <div className="rounded-lg border p-4">
              <SubmitPanel activityId={detail.id} checklist={detail.checklist} />
            </div>
          ) : (
            <Preview>
              <div className="rounded-lg border p-4">
                <SubmitPanel activityId="" checklist={PREVIEW_CHECKLIST} blockedReason="Simpan Detail sebagai draf terlebih dahulu." />
              </div>
            </Preview>
          )}
        </section>
      </WizardShell>
    </div>
  );
}
