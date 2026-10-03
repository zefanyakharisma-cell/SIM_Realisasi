'use client';

/**
 * In-app half of "Mode Demo": while it is on, a floating "Panduan" button opens a side sheet with
 * tips for the current page and the full step-by-step guide. Renders nothing while it is off.
 */
import * as React from 'react';
import { usePathname } from 'next/navigation';
import { GraduationCap, MapPin } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Separator } from '@/components/ui/separator';
import { Sheet, SheetContent, SheetDescription, SheetTitle, SheetTrigger } from '@/components/ui/sheet';
import { Switch } from '@/components/ui/switch';
import { GuideStepper } from '@/components/realisasi/guide/guide-stepper';
import { useDemoGuide } from '@/components/realisasi/guide/use-demo-guide';
import { pageGuideFor } from '@/lib/realisasi/guide/content';

export function AppDemoGuide() {
  const { enabled, setEnabled, stepId, setStepId } = useDemoGuide();
  const pathname = usePathname() ?? '';
  const [open, setOpen] = React.useState(false);
  const page = pageGuideFor(pathname);

  if (!enabled) return null;

  return (
    <Sheet open={open} onOpenChange={setOpen}>
      <SheetTrigger asChild>
        <Button className="fixed bottom-5 right-5 z-40 rounded-full shadow-lg print:hidden" data-testid="demo-guide-open">
          <GraduationCap aria-hidden="true" />
          Panduan
        </Button>
      </SheetTrigger>
      <SheetContent side="right" data-testid="demo-guide-sheet">
        <div className="space-y-1 pr-6">
          <SheetTitle className="flex items-center gap-2 text-lg">
            <GraduationCap className="size-5 text-primary" aria-hidden="true" />
            Panduan Mode Demo
          </SheetTitle>
          <SheetDescription>Tips untuk halaman ini dan panduan lengkap langkah demi langkah.</SheetDescription>
        </div>

        {page ? (
          <section aria-labelledby="page-guide-title" className="rounded-lg border bg-muted/40 p-4" data-testid="page-guide">
            <h3 id="page-guide-title" className="mb-2 flex items-center gap-2 text-sm font-semibold">
              <MapPin className="size-4 text-primary" aria-hidden="true" />
              Di halaman ini: {page.title}
            </h3>
            <ul className="list-disc space-y-1 pl-5 text-sm">
              {page.tips.map((t, i) => (
                <li key={i}>{t}</li>
              ))}
            </ul>
            {stepId !== page.stepId ? (
              <Button type="button" variant="link" size="sm" className="mt-1 h-auto px-0" onClick={() => setStepId(page.stepId)}>
                Buka bab panduan terkait
              </Button>
            ) : null}
          </section>
        ) : null}

        <GuideStepper stepId={stepId} onStepChange={setStepId} compact />

        <Separator />
        <div className="flex items-center justify-between gap-3">
          <Label htmlFor="demo-mode-switch-app" className="text-sm">
            Mode Demo aktif
          </Label>
          <Switch
            id="demo-mode-switch-app"
            checked={enabled}
            onCheckedChange={(on) => {
              setEnabled(on);
              if (!on) setOpen(false);
            }}
            data-testid="demo-mode-toggle-app"
          />
        </div>
      </SheetContent>
    </Sheet>
  );
}
