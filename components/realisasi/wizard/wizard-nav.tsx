'use client';
/** Footer navigation for wizard steps 2–4 (Kembali · Simpan Draf · Lanjut). */
import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { toast } from '@/components/ui/toaster';
import { stepHref } from '@/components/realisasi/activity/labels';
import { useGuardedNavigation } from '@/components/realisasi/wizard/save-status';

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
  const go = useGuardedNavigation();
  const [busy, setBusy] = useState(false);
  // Each button first waits for pending (debounced / in-flight) saves (M-1).
  const nav = async (href: string, onDone?: () => void) => {
    setBusy(true);
    try {
      if (await go(href)) onDone?.();
    } finally {
      setBusy(false);
    }
  };
  return (
    <div className="flex flex-wrap items-center justify-between gap-3 border-t pt-4">
      <Button type="button" variant="ghost" disabled={busy} onClick={() => void nav(stepHref(draftId, step - 1))}>
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
          loading={busy && !saveDisabled}
          data-testid="wizard-save-draft"
          onClick={() =>
            void nav(`/realisasi/kegiatan/${draftId}`, () => toast.success('Draf tersimpan. Anda dapat melanjutkan kapan saja.'))
          }
        >
          Simpan Draf
        </Button>
        {step < 4 && (
          <Button
            type="button"
            disabled={nextDisabled || busy}
            aria-describedby={nextHint ? 'wizard-next-hint' : undefined}
            data-testid="wizard-next"
            onClick={() => void nav(stepHref(draftId, step + 1))}
          >
            Lanjut
          </Button>
        )}
      </div>
    </div>
  );
}
