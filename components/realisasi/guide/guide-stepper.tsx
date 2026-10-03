'use client';

/** Step-by-step demo guide (chapter list + one step at a time), used on /login and in the app's Panduan sheet. */
import * as React from 'react';
import {
  BarChart3,
  BookOpen,
  ChevronLeft,
  ChevronRight,
  ClipboardCheck,
  FileSpreadsheet,
  FileText,
  Lightbulb,
  PlayCircle,
  PlusCircle,
  RotateCcw,
  Settings,
  Sparkles,
  Users,
  type LucideIcon,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { NativeSelect } from '@/components/ui/native-select';
import { cn } from '@/lib/utils';
import { GUIDE_STEPS, guideStepIndex, type GuideIcon, type GuideStep } from '@/lib/realisasi/guide/content';

const ICONS: Record<GuideIcon, LucideIcon> = {
  welcome: Sparkles,
  concepts: BookOpen,
  roles: Users,
  submit: PlusCircle,
  revision: RotateCcw,
  verify: ClipboardCheck,
  dashboard: BarChart3,
  reports: FileSpreadsheet,
  settings: Settings,
  agreements: FileText,
  scenarios: PlayCircle,
  tips: Lightbulb,
};

export function GuideStepper({
  stepId,
  onStepChange,
  renderExtra,
  compact = false,
}: {
  stepId: string;
  onStepChange: (id: string) => void;
  /** Extra content under a step (e.g. the matching demo accounts on /login). */
  renderExtra?: (step: GuideStep) => React.ReactNode;
  /** Single column (narrow containers such as the side sheet). */
  compact?: boolean;
}) {
  const found = guideStepIndex(stepId);
  const index = found < 0 ? 0 : found;
  const step = GUIDE_STEPS[index]!;
  const total = GUIDE_STEPS.length;
  const headingRef = React.useRef<HTMLHeadingElement>(null);
  const moved = React.useRef(false);

  // Move focus to the new step's heading after Back/Next or a chapter click (not on first render).
  React.useEffect(() => {
    if (moved.current) headingRef.current?.focus();
  }, [index]);

  const go = (i: number) => {
    const next = GUIDE_STEPS[Math.min(Math.max(i, 0), total - 1)]!;
    moved.current = true;
    onStepChange(next.id);
  };

  const Icon = ICONS[step.icon];
  const extra = renderExtra?.(step);

  return (
    <div className={cn('grid gap-6', !compact && 'md:grid-cols-[14rem_1fr]')} data-testid="demo-guide">
      {compact ? null : (
        <nav aria-label="Bab panduan">
          <ol className="space-y-0.5 text-sm">
            {GUIDE_STEPS.map((s, i) => (
              <li key={s.id}>
                <button
                  type="button"
                  onClick={() => go(i)}
                  aria-current={i === index ? 'step' : undefined}
                  data-testid={`guide-chapter-${s.id}`}
                  className={cn(
                    'flex w-full items-start gap-2 rounded-md px-2 py-1.5 text-left transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                    i === index ? 'bg-accent font-medium text-foreground' : 'text-muted-foreground',
                  )}
                >
                  <span
                    aria-hidden="true"
                    className={cn(
                      'mt-0.5 flex size-5 shrink-0 items-center justify-center rounded-full border text-[11px] tabular-nums',
                      i < index && 'border-primary bg-primary text-primary-foreground',
                      i === index && 'border-primary text-primary',
                    )}
                  >
                    {i + 1}
                  </span>
                  <span>{s.title}</span>
                </button>
              </li>
            ))}
          </ol>
        </nav>
      )}

      <section aria-labelledby="guide-step-title" className="min-w-0 space-y-4">
        {compact ? (
          <NativeSelect
            aria-label="Pilih bab panduan"
            value={step.id}
            onChange={(e) => go(guideStepIndex(e.target.value))}
            data-testid="guide-chapter-select"
          >
            {GUIDE_STEPS.map((s, i) => (
              <option key={s.id} value={s.id}>
                {i + 1}. {s.title}
              </option>
            ))}
          </NativeSelect>
        ) : null}
        <div className="space-y-2">
          <p className="text-xs font-medium uppercase tracking-wider text-muted-foreground" data-testid="guide-progress">
            Langkah {index + 1} dari {total}
          </p>
          <div className="h-1.5 overflow-hidden rounded-full bg-muted" aria-hidden="true">
            <div className="h-full rounded-full bg-primary transition-all" style={{ width: `${((index + 1) / total) * 100}%` }} />
          </div>
          <h3
            id="guide-step-title"
            ref={headingRef}
            tabIndex={-1}
            className="flex items-center gap-2 pt-1 text-lg font-semibold focus:outline-none"
            data-testid="guide-step-title"
          >
            <Icon className="size-5 shrink-0 text-primary" aria-hidden="true" />
            {step.title}
          </h3>
          <p className="text-sm text-muted-foreground">{step.intro}</p>
        </div>

        <ul className="space-y-2 text-sm">
          {step.points.map((p, i) => (
            <li key={i} className="flex gap-2">
              <span className="mt-2 size-1.5 shrink-0 rounded-full bg-primary/70" aria-hidden="true" />
              <span>
                {p.term ? <strong className="font-semibold">{p.term}: </strong> : null}
                {p.text}
              </span>
            </li>
          ))}
        </ul>

        {step.tryIt && step.tryIt.length > 0 ? (
          <div className="rounded-lg border border-primary/30 bg-primary/5 p-4">
            <h4 className="mb-2 text-sm font-semibold">Coba sendiri</h4>
            <ol className="list-decimal space-y-1 pl-5 text-sm">
              {step.tryIt.map((t, i) => (
                <li key={i}>{t}</li>
              ))}
            </ol>
          </div>
        ) : null}

        {extra}

        <div className="flex items-center justify-between gap-2 border-t pt-4">
          <Button type="button" variant="outline" size="sm" onClick={() => go(index - 1)} disabled={index === 0} data-testid="guide-prev">
            <ChevronLeft aria-hidden="true" />
            Sebelumnya
          </Button>
          {index < total - 1 ? (
            <Button type="button" size="sm" onClick={() => go(index + 1)} data-testid="guide-next">
              Berikutnya
              <ChevronRight aria-hidden="true" />
            </Button>
          ) : (
            <Button type="button" variant="outline" size="sm" onClick={() => go(0)} data-testid="guide-restart">
              <RotateCcw aria-hidden="true" />
              Ulangi dari awal
            </Button>
          )}
        </div>
      </section>
    </div>
  );
}
