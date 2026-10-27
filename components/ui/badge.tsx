import * as React from 'react';
import { cva, type VariantProps } from 'class-variance-authority';
import { cn } from '@/lib/utils';

/**
 * Variants = `Tone` (lib/realisasi/status.ts) + `outline`; PCU StatusPill: a tone-coloured border (and the caller's
 * ToneDot) with the label in text-primary, so colour only reinforces the words. `appearance="outline"` is the flag
 * style (Design §2): tone border and text-safe tone ink.
 * Tone → design-system token: neutral = status-draft · blue = status-progress · amber = status-pending ·
 * green = status-active · red = action-danger · purple = renewal-request · yellow = sla-yellow.
 */
export const badgeVariants = cva(
  'inline-flex items-center gap-1.5 whitespace-nowrap rounded-full border bg-background px-2.5 py-0.5 text-xs font-medium text-foreground transition-colors',
  {
    variants: {
      variant: {
        neutral: 'border-neutral',
        blue: 'border-info',
        amber: 'border-pending',
        green: 'border-success',
        red: 'border-danger',
        purple: 'border-renewal',
        yellow: 'border-warning',
        outline: 'border-border bg-transparent',
      },
      appearance: {
        solid: '',
        outline: 'bg-transparent',
      },
    },
    compoundVariants: [
      { appearance: 'outline', variant: 'neutral', className: 'text-neutral-fg' },
      { appearance: 'outline', variant: 'blue', className: 'text-info-fg' },
      { appearance: 'outline', variant: 'amber', className: 'text-pending-fg' },
      { appearance: 'outline', variant: 'green', className: 'text-success-fg' },
      { appearance: 'outline', variant: 'red', className: 'text-danger-fg' },
      { appearance: 'outline', variant: 'purple', className: 'text-renewal-fg' },
      { appearance: 'outline', variant: 'yellow', className: 'text-warning-fg' },
    ],
    defaultVariants: { variant: 'neutral', appearance: 'solid' },
  },
);

export type BadgeVariant = NonNullable<VariantProps<typeof badgeVariants>['variant']>;

export interface BadgeProps extends React.HTMLAttributes<HTMLSpanElement>, VariantProps<typeof badgeVariants> {}

export function Badge({ className, variant, appearance, ...props }: BadgeProps) {
  return <span className={cn(badgeVariants({ variant, appearance }), className)} {...props} />;
}
