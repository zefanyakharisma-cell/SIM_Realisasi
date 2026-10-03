'use client';

/** "Mode Demo" switch on /login: when on, shows the step-by-step guide above the account list. */
import * as React from 'react';
import { GraduationCap, LogIn } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/components/ui/card';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { GuideStepper } from '@/components/realisasi/guide/guide-stepper';
import { useDemoGuide } from '@/components/realisasi/guide/use-demo-guide';
import { loginAs } from '@/lib/realisasi/actions/session';
import type { Role } from '@/lib/session';
import type { GuideStep } from '@/lib/realisasi/guide/content';

export interface GuideAccount {
  id: string;
  displayName: string;
  role: Role;
  roleLabel: string;
  unitName: string | null;
}

export function LoginDemoGuide({ accounts }: { accounts: GuideAccount[] }) {
  const { enabled, setEnabled, stepId, setStepId } = useDemoGuide();

  const renderAccounts = (step: GuideStep) => {
    const roles = step.roles;
    if (!roles) return null;
    const matching = accounts.filter((a) => roles.includes(a.role));
    if (matching.length === 0) return null;
    return (
      <div className="space-y-2" data-testid="guide-accounts">
        <h4 className="text-sm font-semibold">Masuk dengan akun yang cocok</h4>
        <ul className="flex flex-wrap gap-2">
          {matching.map((a) => (
            <li key={a.id}>
              <form action={loginAs.bind(null, a.id)}>
                <button
                  type="submit"
                  className="inline-flex items-center gap-1.5 rounded-full border bg-background px-3 py-1 text-xs transition-colors hover:border-primary hover:bg-accent/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                  aria-label={`Masuk sebagai ${a.displayName}, ${a.roleLabel}${a.unitName ? `, ${a.unitName}` : ''}`}
                >
                  <LogIn className="size-3.5 text-primary" aria-hidden="true" />
                  <span className="font-medium">{a.displayName}</span>
                  <span className="text-muted-foreground">· {a.roleLabel}</span>
                </button>
              </form>
            </li>
          ))}
        </ul>
      </div>
    );
  };

  return (
    <Card data-testid="demo-mode-card" className={enabled ? 'border-primary/40' : undefined}>
      <CardHeader className="flex-row items-center gap-3 space-y-0">
        <GraduationCap className="size-6 shrink-0 text-primary" aria-hidden="true" />
        <div className="min-w-0 flex-1">
          <Label htmlFor="demo-mode-switch" className="text-base font-semibold">
            Mode Demo
          </Label>
          <p id="demo-mode-desc" className="text-sm text-muted-foreground">
            Tampilkan panduan langkah demi langkah: cara memakai aplikasi, penjelasan fitur, dan skenario demo.
          </p>
        </div>
        <Switch
          id="demo-mode-switch"
          checked={enabled}
          onCheckedChange={setEnabled}
          aria-describedby="demo-mode-desc"
          data-testid="demo-mode-toggle"
        />
      </CardHeader>
      {enabled ? (
        <CardContent>
          <GuideStepper stepId={stepId} onStepChange={setStepId} renderExtra={renderAccounts} />
        </CardContent>
      ) : null}
    </Card>
  );
}
