'use client';
/**
 * Unit revision: participant editing (new version, R-21) + checklist + "Ajukan ulang".
 * Shares the "red rows" state between the editor and the submit button.
 */
import { useCallback, useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { CopyPlus } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { toast } from '@/components/ui/toaster';
import { ParticipantsEditor } from '@/components/realisasi/wizard/participants-editor';
import { SubmitPanel } from '@/components/realisasi/wizard/submit-panel';
import { ensureParticipantDraft } from '@/lib/realisasi/actions/submission';
import type { CountryOption } from '@/lib/realisasi/queries/lookups';
import type { ChecklistItem, ParticipantVersion } from '@/lib/realisasi/types';

export function RevisionWorkspace({
  activityId,
  participants,
  checklist,
}: {
  activityId: string;
  participants: {
    version: ParticipantVersion | null;
    countries: CountryOption[];
    required: { any: boolean; internal: boolean; inbound: boolean };
  } | null;
  checklist: ChecklistItem[] | null;
}) {
  const router = useRouter();
  const [blocking, setBlocking] = useState(false);
  const [pending, startTransition] = useTransition();
  const onSaved = useCallback(() => router.refresh(), [router]);
  const hasDraft = participants?.version?.status === 'draft';
  const nextVersion = (participants?.version?.version ?? 0) + (hasDraft ? 0 : 1);

  function createVersion() {
    startTransition(async () => {
      const res = await ensureParticipantDraft(activityId);
      if (!res.ok) {
        toast.error(res.message);
        return;
      }
      toast.success(`Versi peserta v${res.data.version} dibuat.`);
      router.refresh();
    });
  }

  return (
    <div className="space-y-8">
      {participants && (
        <section aria-labelledby="rev-participants" className="space-y-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <h2 id="rev-participants" className="text-lg font-semibold">
              Peserta
            </h2>
            {!hasDraft && (
              <Button type="button" variant="outline" size="sm" onClick={createVersion} loading={pending} data-testid="create-version">
                <CopyPlus aria-hidden /> Buat versi baru v{nextVersion} tanpa perubahan
              </Button>
            )}
          </div>
          <ParticipantsEditor
            activityId={activityId}
            initialVersion={participants.version}
            countries={participants.countries}
            required={participants.required}
            onBlockingChange={setBlocking}
            onSaved={onSaved}
            versionNote={
              hasDraft
                ? `Anda sedang mengubah versi baru v${nextVersion}. Versi sebelumnya tetap tersimpan (hanya baca).`
                : `Perubahan akan disimpan sebagai versi baru v${nextVersion}; versi sebelumnya tetap tersimpan (hanya baca).`
            }
          />
        </section>
      )}
      <div className="rounded-lg border p-4">
        <SubmitPanel
          activityId={activityId}
          checklist={checklist}
          resubmit
          blockedReason={blocking ? 'Masih ada baris peserta bertanda ✗ yang belum disimpan.' : null}
        />
      </div>
    </div>
  );
}
