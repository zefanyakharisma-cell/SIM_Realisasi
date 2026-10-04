'use client';

/**
 * In-app half of "Mode Demo": the first time each page is opened, its pop-up tour starts by itself
 * (after the one-off tour of the app frame). The floating "Panduan" menu replays tours or switches
 * the mode off. Renders nothing while Mode Demo is off.
 */
import * as React from 'react';
import { usePathname, useSearchParams } from 'next/navigation';
import { Compass, GraduationCap, PlayCircle, PowerOff } from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { CoachTour } from '@/components/realisasi/guide/coach-tour';
import { useDemoGuide } from '@/components/realisasi/guide/use-demo-guide';
import { SHELL_TOUR, tourFor, type Tour } from '@/lib/realisasi/guide/tours';

/** Lets the page paint (and client widgets hydrate) before the first target is measured. */
const SETTLE_MS = 400;

export function AppDemoGuide() {
  const { enabled, setEnabled, seen, markSeen } = useDemoGuide();
  const pathname = usePathname() ?? '';
  const tab = useSearchParams()?.get('tab') ?? null;
  const pageTour = tourFor(pathname, tab);
  const [active, setActive] = React.useState<Tour | null>(null);

  // Leaving the page closes its tour without marking it seen.
  const routeKey = `${pathname}?${tab ?? ''}`;
  const lastRoute = React.useRef(routeKey);
  React.useEffect(() => {
    if (lastRoute.current === routeKey) return;
    lastRoute.current = routeKey;
    setActive(null);
  }, [routeKey]);

  // Auto-start: the app-frame tour once, then each page's tour on its first visit.
  React.useEffect(() => {
    if (!enabled || active) return;
    const next = !seen.has(SHELL_TOUR.id) ? SHELL_TOUR : pageTour && !seen.has(pageTour.id) ? pageTour : null;
    if (!next) return;
    const t = setTimeout(() => setActive(next), SETTLE_MS);
    return () => clearTimeout(t);
  }, [enabled, active, seen, pageTour]);

  // Menu items start tours after the dropdown has closed and returned focus.
  const start = (t: Tour) => setTimeout(() => setActive(t), 50);

  if (!enabled) return null;

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button className="fixed bottom-5 right-5 z-40 rounded-full shadow-lg print:hidden" data-testid="demo-guide-open">
            <GraduationCap aria-hidden="true" />
            Panduan
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" side="top" className="w-64">
          <DropdownMenuLabel>Mode Demo</DropdownMenuLabel>
          <DropdownMenuItem disabled={!pageTour} onSelect={() => pageTour && start(pageTour)} data-testid="demo-replay-page">
            <PlayCircle aria-hidden="true" />
            {pageTour ? `Ulangi tur: ${pageTour.title}` : 'Tidak ada tur untuk halaman ini'}
          </DropdownMenuItem>
          <DropdownMenuItem onSelect={() => start(SHELL_TOUR)} data-testid="demo-replay-shell">
            <Compass aria-hidden="true" />
            Tur dasar aplikasi
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem onSelect={() => setEnabled(false)} data-testid="demo-mode-off">
            <PowerOff aria-hidden="true" />
            Matikan Mode Demo
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
      {active ? (
        <CoachTour
          key={active.id}
          tour={active}
          onClose={() => {
            markSeen(active.id);
            setActive(null);
          }}
        />
      ) : null}
    </>
  );
}
