'use client';

/**
 * Coach-mark tour engine (Mode Demo): dims the page, spotlights one element per step and shows a
 * pop-up next to it (Radix Popover with a virtual anchor, so placement and collision flipping come
 * from floating-ui). Steps without a target, or whose target is missing/hidden for this role or
 * screen size, are centered or skipped. Keyboard: ←/→ navigate, Esc skips, Tab stays in the pop-up;
 * focus returns to where it was when the tour closes.
 */
import * as React from 'react';
import { Lightbulb, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Popover, PopoverAnchor, PopoverContent } from '@/components/ui/popover';
import { cn } from '@/lib/utils';
import type { Tour, TourStep } from '@/lib/realisasi/guide/tours';

const PAD = 8;
const GAP = PAD + 6;
/** Sticky top bar height: content scrolled under it is hidden. */
const HEADER = 56;
/** Fallback pop-up height before the first one has been measured. */
const CARD_EST = 300;
/** Below this width, left/right pop-ups have no room and open above/below instead. */
const NARROW = 640;

function query(selector: string): HTMLElement | null {
  try {
    return document.querySelector<HTMLElement>(selector);
  } catch {
    return null;
  }
}

/** The step's target if it exists and is rendered (display:none, hidden or zero-size → null). */
export function findTarget(selector: string): HTMLElement | null {
  const el = query(selector);
  if (!el) return null;
  const r = el.getBoundingClientRect();
  if (r.width === 0 && r.height === 0) return null;
  if (getComputedStyle(el).visibility === 'hidden') return null;
  return el;
}

function isAvailable(step: TourStep): boolean {
  if (step.unless && findTarget(step.unless)) return false;
  return !step.target || findTarget(step.target) !== null;
}

function prefersReducedMotion(): boolean {
  return typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches === true;
}

/** A target that can't sit on screen together with the pop-up: the pop-up is anchored to its top strip instead. */
function isTall(el: HTMLElement, cardHeight: number): boolean {
  return el.getBoundingClientRect().height + cardHeight + GAP + 2 * PAD > window.innerHeight - HEADER;
}

function sideFor(step: TourStep): NonNullable<TourStep['side']> {
  const side = step.side ?? 'bottom';
  return window.innerWidth < NARROW && (side === 'left' || side === 'right') ? 'bottom' : side;
}

/**
 * Scrolls so the target and its pop-up fit on screen together: pop-up below/above → the pair is
 * centered vertically; left/right → the target is centered; tall targets → their top is shown.
 */
function bringIntoView(el: HTMLElement, side: NonNullable<TourStep['side']>, cardHeight: number): void {
  const r = el.getBoundingClientRect();
  const avail = window.innerHeight - HEADER;
  let top: number;
  if (isTall(el, cardHeight)) top = HEADER + PAD * 2;
  else if (side === 'left' || side === 'right') top = HEADER + (avail - r.height) / 2;
  else {
    const pair = r.height + GAP + cardHeight;
    top = HEADER + (avail - pair) / 2 + (side === 'top' ? cardHeight + GAP : 0);
  }
  // Horizontal scrollers (wide tables) first, then the page itself.
  el.scrollIntoView({ block: 'nearest', inline: 'nearest' });
  const delta = el.getBoundingClientRect().top - top;
  if (Math.abs(delta) > 2) window.scrollBy({ top: delta, behavior: prefersReducedMotion() ? 'auto' : 'smooth' });
}

/** Waits briefly for the page to render its targets, then drops the steps that don't apply. */
export function CoachTour({ tour, onClose }: { tour: Tour; onClose: (completed: boolean) => void }) {
  const [steps, setSteps] = React.useState<TourStep[] | null>(null);
  const onCloseRef = React.useRef(onClose);
  onCloseRef.current = onClose;

  React.useEffect(() => {
    let cancelled = false;
    let tries = 0;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const targeted = tour.steps.filter((s) => s.target);
    const resolve = () => {
      if (cancelled) return;
      const ready = targeted.length === 0 || targeted.some((s) => findTarget(s.target!));
      if (!ready && tries++ < 15) {
        timer = setTimeout(resolve, 100);
        return;
      }
      const list = tour.steps.filter(isAvailable);
      if (list.length === 0) onCloseRef.current(false);
      else setSteps(list);
    };
    resolve();
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [tour]);

  if (!steps) return null;
  return <TourRunner key={tour.id} title={tour.title} steps={steps} onClose={(done) => onCloseRef.current(done)} />;
}

interface Box {
  top: number;
  left: number;
  width: number;
  height: number;
}

function TourRunner({ title, steps, onClose }: { title: string; steps: TourStep[]; onClose: (completed: boolean) => void }) {
  const [index, setIndex] = React.useState(0);
  const [target, setTarget] = React.useState<HTMLElement | null>(null);
  const [box, setBox] = React.useState<Box | null>(null);
  const cardRef = React.useRef<HTMLDivElement>(null);
  const headingRef = React.useRef<HTMLHeadingElement>(null);
  const titleId = React.useId();
  const bodyId = React.useId();
  // Natural pop-up height: estimated before the step renders, then measured (state re-renders the placement).
  const cardHeight = React.useRef(CARD_EST);
  const [, setMeasured] = React.useState(CARD_EST);
  const step = steps[index]!;
  const last = index === steps.length - 1;
  const tall = target !== null && box !== null && isTall(target, cardHeight.current);
  const side = target ? (tall ? 'bottom' : sideFor(step)) : 'bottom';

  const finish = React.useCallback((completed: boolean) => onClose(completed), [onClose]);

  // Moves in a direction, skipping steps whose target disappeared since the tour started.
  const go = React.useCallback(
    (dir: 1 | -1) => {
      let i = index + dir;
      while (i >= 0 && i < steps.length && !isAvailable(steps[i]!)) i += dir;
      if (i >= steps.length) finish(true);
      else if (i >= 0) setIndex(i);
    },
    [index, steps, finish],
  );

  // Restore focus to wherever it was before the tour opened.
  React.useEffect(() => {
    const previous = document.activeElement as HTMLElement | null;
    return () => {
      if (previous?.isConnected) previous.focus({ preventScroll: true });
    };
  }, []);

  // Resolve the current target and bring it into view.
  React.useLayoutEffect(() => {
    const el = step.target ? findTarget(step.target) : null;
    if (step.target && !el) {
      go(1);
      return;
    }
    setTarget(el);
    if (el) {
      bringIntoView(el, sideFor(step), cardHeight.current);
    } else {
      setBox(null);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- re-run per step only
  }, [index]);

  // Track the target's box through scrolling, resizing and layout changes.
  React.useEffect(() => {
    if (!target) return;
    let frame = 0;
    const update = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => {
        const r = target.getBoundingClientRect();
        const top = Math.max(r.top - PAD, 0);
        const left = Math.max(r.left - PAD, 0);
        const bottom = Math.min(r.bottom + PAD, window.innerHeight);
        const right = Math.min(r.right + PAD, window.innerWidth);
        setBox({ top, left, width: Math.max(right - left, 0), height: Math.max(bottom - top, 0) });
      });
    };
    update();
    window.addEventListener('scroll', update, true);
    window.addEventListener('resize', update);
    const ro = new ResizeObserver(update);
    ro.observe(target);
    return () => {
      cancelAnimationFrame(frame);
      window.removeEventListener('scroll', update, true);
      window.removeEventListener('resize', update);
      ro.disconnect();
    };
  }, [target]);

  // Focus the pop-up heading on every step so screen readers announce it; measure the pop-up and, if the
  // estimate was off, re-place the target so both fit on screen.
  React.useEffect(() => {
    const t = setTimeout(() => {
      headingRef.current?.focus({ preventScroll: true });
      if (!cardRef.current) return;
      // + the pop-up's own padding/border (the inner block is never height-capped).
      const h = cardRef.current.offsetHeight + 34;
      if (Math.abs(h - cardHeight.current) <= 4) return;
      cardHeight.current = h;
      setMeasured(h);
      if (target) bringIntoView(target, sideFor(step), h);
    }, 30);
    return () => clearTimeout(t);
  }, [step, target]);

  // Keyboard: ←/→ navigate, Esc skips.
  React.useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        finish(false);
      } else if (e.key === 'ArrowRight') {
        e.preventDefault();
        go(1);
      } else if (e.key === 'ArrowLeft') {
        e.preventDefault();
        go(-1);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [go, finish]);

  // Keep Tab inside the pop-up (the page behind is inert for the duration of the tour).
  const trapTab = (e: React.KeyboardEvent) => {
    if (e.key !== 'Tab' || !cardRef.current) return;
    const focusable = Array.from(cardRef.current.querySelectorAll<HTMLElement>('button:not([disabled]), [tabindex="0"]'));
    if (focusable.length === 0) return;
    const first = focusable[0]!;
    const lastEl = focusable[focusable.length - 1]!;
    const active = document.activeElement;
    if (e.shiftKey && (active === first || !cardRef.current.contains(active))) {
      e.preventDefault();
      lastEl.focus();
    } else if (!e.shiftKey && (active === lastEl || !cardRef.current.contains(active))) {
      e.preventDefault();
      first.focus();
    }
  };

  // Anchor for the pop-up: the whole target, or its top strip when the target is taller than the screen.
  const anchorRef = React.useMemo(() => {
    if (!target) return null;
    return {
      current: {
        contextElement: target,
        getBoundingClientRect: () => {
          const r = target.getBoundingClientRect();
          if (!isTall(target, cardHeight.current)) return r;
          const top = Math.max(r.top, 0);
          return new DOMRect(r.left, top, r.width, Math.min(56, Math.max(r.bottom - top, 0)));
        },
      },
    };
  }, [target]);

  const card = (
    <div ref={cardRef} onKeyDown={trapTab} className="space-y-3" data-testid="tour-card">
      <div className="flex items-start justify-between gap-3">
        <p className="text-xs font-medium text-muted-foreground" data-testid="tour-progress">
          {title} · {index + 1} / {steps.length}
        </p>
        <button
          type="button"
          onClick={() => finish(false)}
          className="-mr-1 -mt-1 rounded-sm p-1 text-muted-foreground hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          aria-label="Tutup tur"
        >
          <X className="size-4" aria-hidden="true" />
        </button>
      </div>
      <h2 id={titleId} ref={headingRef} tabIndex={-1} className="text-base font-semibold leading-snug focus:outline-none" data-testid="tour-title">
        {step.title}
      </h2>
      <p id={bodyId} className="text-sm text-muted-foreground">
        {step.body}
      </p>
      {step.tip ? (
        <p className="flex gap-2 rounded-md bg-primary/5 p-2 text-xs text-foreground">
          <Lightbulb className="mt-0.5 size-3.5 shrink-0 text-primary" aria-hidden="true" />
          <span>{step.tip}</span>
        </p>
      ) : null}
      <div className="flex gap-1" aria-hidden="true">
        {steps.map((_, i) => (
          <span key={i} className={cn('h-1 flex-1 rounded-full', i <= index ? 'bg-primary' : 'bg-muted')} />
        ))}
      </div>
      <div className="flex items-center justify-between gap-2 pt-1">
        <Button type="button" variant="ghost" size="sm" className="px-2 text-muted-foreground" onClick={() => finish(false)} data-testid="tour-skip">
          Lewati tur
        </Button>
        <div className="flex gap-2">
          {index > 0 ? (
            <Button type="button" variant="outline" size="sm" onClick={() => go(-1)} data-testid="tour-prev">
              Sebelumnya
            </Button>
          ) : null}
          <Button type="button" size="sm" onClick={() => go(1)} data-testid="tour-next">
            {last ? 'Selesai' : 'Berikutnya'}
          </Button>
        </div>
      </div>
    </div>
  );

  const dialogProps = { 'aria-modal': true, 'aria-labelledby': titleId, 'aria-describedby': bodyId } as const;

  return (
    <>
      {/* Click shield: the page is inert while the tour runs. Dimmed directly for centered steps. */}
      <div className={cn('fixed inset-0 z-[60]', !target && 'bg-black/60')} aria-hidden="true" data-testid="tour-overlay" />
      {target && box ? (
        <div
          aria-hidden="true"
          data-testid="tour-spotlight"
          className="pointer-events-none fixed z-[61] rounded-lg ring-2 ring-primary motion-safe:transition-all motion-safe:duration-200"
          style={{ ...box, boxShadow: '0 0 0 9999px rgb(0 0 0 / 0.6)' }}
        />
      ) : null}
      {target && anchorRef ? (
        <Popover open modal={false}>
          <PopoverAnchor virtualRef={anchorRef} />
          <PopoverContent
            {...dialogProps}
            side={side}
            align="start"
            sideOffset={GAP}
            collisionPadding={{ top: HEADER + 4, right: 12, bottom: 12, left: 12 }}
            className="z-[62] max-h-[var(--radix-popover-content-available-height)] w-80 max-w-[calc(100vw-1.5rem)] overflow-y-auto p-4 shadow-xl"
            onOpenAutoFocus={(e) => e.preventDefault()}
            onCloseAutoFocus={(e) => e.preventDefault()}
            onEscapeKeyDown={(e) => e.preventDefault()}
            onInteractOutside={(e) => e.preventDefault()}
          >
            {card}
          </PopoverContent>
        </Popover>
      ) : !target ? (
        <div className="fixed inset-0 z-[62] flex items-center justify-center p-4">
          <div role="dialog" {...dialogProps} className="w-full max-w-md rounded-lg border bg-background p-5 shadow-xl">
            {card}
          </div>
        </div>
      ) : null}
    </>
  );
}
