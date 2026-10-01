'use client';
/** Footer navigation for wizard steps 2–4 (Kembali · Simpan Draf · Lanjut). */
import { useRouter } from 'next/navigation';
import { Button } from '@/components/ui/button';
import { toast } from '@/components/ui/toaster';
import { stepHref } from '@/components/realisasi/activity/labels';

export function WizardNav({
  draftId,
  step,
  nextDisabled,
  nextHint,
  saveDisabled,
}: {
  draftId: string;
  step: number;
  nextDisabled?: boolean;
  nextHint?: string;
  saveDisabled?: boolean;
}) {
  const router = useRouter();
  return (
    <div className="flex flex-wrap items-center justify-between gap-3 border-t pt-4">
      <Button type="button" variant="ghost" onClick={() => router.push(stepHref(draftId, step - 1))}>
        Kembali
      </Button>
      <div className="flex flex-wrap items-center gap-3">
        {nextHint && (
          <p id="wizard-next-hint" className="text-sm text-muted-foreground">
            {nextHint}
          </p>
        )}
        <Button
          type="button"
          variant="outline"
          disabled={saveDisabled}
          data-testid="wizard-save-draft"
          onClick={() => {
            toast.success('Draf tersimpan. Anda dapat melanjutkan kapan saja.');
            router.push(`/realisasi/kegiatan/${draftId}`);
          }}
        >
          Simpan Draf
        </Button>
        {step < 4 && (
          <Button
            type="button"
            disabled={nextDisabled}
            aria-describedby={nextHint ? 'wizard-next-hint' : undefined}
            data-testid="wizard-next"
            onClick={() => router.push(stepHref(draftId, step + 1))}
          >
            Lanjut
          </Button>
        )}
      </div>
    </div>
  );
}
