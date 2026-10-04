'use client';

/** "Mode Demo" switch on /login: switching it on starts the pop-up tour of the login page. */
import * as React from 'react';
import { GraduationCap, PlayCircle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { CoachTour } from '@/components/realisasi/guide/coach-tour';
import { useDemoGuide } from '@/components/realisasi/guide/use-demo-guide';
import { LOGIN_TOUR } from '@/lib/realisasi/guide/tours';

export function LoginDemoGuide() {
  const { enabled, setEnabled, seen, markSeen } = useDemoGuide();
  const [running, setRunning] = React.useState(false);

  // Runs once per Mode Demo session (switching it on clears the seen list).
  React.useEffect(() => {
    if (enabled && !seen.has(LOGIN_TOUR.id)) setRunning(true);
    if (!enabled) setRunning(false);
  }, [enabled, seen]);

  return (
    <Card data-testid="demo-mode-card" className="flex flex-wrap items-center gap-3 p-4">
      <GraduationCap className="size-6 shrink-0 text-primary" aria-hidden="true" />
      <div className="min-w-0 flex-1">
        <Label htmlFor="demo-mode-switch" className="text-base font-semibold">
          Mode Demo
        </Label>
        <p id="demo-mode-desc" className="text-sm text-muted-foreground">
          Tur interaktif: setiap halaman, tombol, dan fitur dijelaskan langkah demi langkah sebelum Anda memakainya.
        </p>
      </div>
      {enabled ? (
        <Button type="button" variant="outline" size="sm" onClick={() => setRunning(true)} data-testid="demo-tour-restart">
          <PlayCircle aria-hidden="true" />
          Mulai ulang tur
        </Button>
      ) : null}
      <Switch
        id="demo-mode-switch"
        checked={enabled}
        onCheckedChange={setEnabled}
        aria-describedby="demo-mode-desc"
        data-testid="demo-mode-toggle"
      />
      {running ? (
        <CoachTour
          tour={LOGIN_TOUR}
          onClose={() => {
            markSeen(LOGIN_TOUR.id);
            setRunning(false);
          }}
        />
      ) : null}
    </Card>
  );
}
