import * as React from 'react';
import Link from 'next/link';
import { Check } from 'lucide-react';
import { cn } from '@/lib/utils';

export interface StepperStep {
  label: string;
  /** When set, the step renders as a link (e.g. `?draft=<id>&step=2`). */
  href?: string;
  disabled?: boolean;
  /** Shows an error marker (e.g. a step with blocking validation errors). */
  invalid?: boolean;
}

export interface StepperProps {
  steps: StepperStep[];
  /** 1-based index of the current step. */
  current: number;
  className?: string;
  'aria-label'?: string;
  /** Intercepts step-link clicks (e.g. to save pending edits before navigating). */
  onStepClick?: (event: React.MouseEvent<HTMLAnchorElement>, href: string) => void;
}

/** Wizard progress (Design §3.3): ordered list, current step has aria-current="step". */
export function Stepper({ steps, current, className, 'aria-label': ariaLabel = 'Langkah pengisian', onStepClick }: StepperProps) {
  return (
    <nav aria-label={ariaLabel} className={className}>
      <ol className="flex flex-wrap items-center gap-2 text-sm">
        {steps.map((step, i) => {
          const n = i + 1;
          const state = n < current ? 'done' : n === current ? 'current' : 'todo';
          const marker = (
            <span
              className={cn(
                'flex size-6 shrink-0 items-center justify-center rounded-full border text-xs font-semibold',
                state === 'done' && 'border-primary bg-primary text-primary-foreground',
                state === 'current' && 'border-primary text-primary ring-2 ring-primary/30',
                state === 'todo' && 'border-input text-muted-foreground',
                step.invalid && 'border-danger bg-danger-subtle text-danger-fg',
              )}
              aria-hidden="true"
            >
              {state === 'done' && !step.invalid ? <Check className="size-3.5" /> : n}
            </span>
          );
          const text = (
            <>
              {marker}
              <span className={cn('font-medium', state === 'todo' && 'text-muted-foreground')}>{step.label}</span>
              <span className="sr-only">
                {state === 'done' ? ' (selesai)' : state === 'current' ? ' (langkah saat ini)' : ''}
                {step.invalid ? ' (perlu diperbaiki)' : ''}
              </span>
            </>
          );
          return (
            <li key={step.label} className="flex items-center gap-2">
              {step.href && !step.disabled && state !== 'current' ? (
                <Link
                  href={step.href}
                  className="flex items-center gap-2 rounded-md px-1 py-0.5 hover:bg-accent"
                  onClick={onStepClick ? (e) => onStepClick(e, step.href!) : undefined}
                >
                  {text}
                </Link>
              ) : (
                <span className="flex items-center gap-2 px-1 py-0.5" aria-current={state === 'current' ? 'step' : undefined}>
                  {text}
                </span>
              )}
              {n < steps.length ? <span className="h-px w-6 bg-border" aria-hidden="true" /> : null}
            </li>
          );
        })}
      </ol>
    </nav>
  );
}
