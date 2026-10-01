'use client';
/** Wizard frame: stepper (Design §3.3) + autosave indicator; steps render as children. */
import { Stepper } from '@/components/ui/stepper';
import { stepHref } from '@/components/realisasi/activity/labels';
import { SaveIndicator, SaveStatusProvider } from '@/components/realisasi/wizard/save-status';

export const WIZARD_STEPS = ['Detail', 'Peserta', 'Berkas', 'Tinjau & Ajukan'] as const;

export function WizardShell({
  draftId,
  step,
  savedAt,
  invalidSteps = [],
  children,
}: {
  draftId: string | null;
  step: number;
  savedAt?: string | null;
  invalidSteps?: number[];
  children: React.ReactNode;
}) {
  return (
    <SaveStatusProvider savedAt={savedAt}>
      <div className="space-y-6">
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-lg border bg-card px-4 py-3">
          <Stepper
            current={step}
            steps={WIZARD_STEPS.map((label, i) => ({
              label,
              href: draftId ? stepHref(draftId, i + 1) : undefined,
              disabled: !draftId,
              invalid: invalidSteps.includes(i + 1),
            }))}
          />
          {draftId ? <SaveIndicator /> : <p className="text-xs text-muted-foreground">Draf dibuat setelah langkah Detail disimpan.</p>}
        </div>
        {children}
      </div>
    </SaveStatusProvider>
  );
}
