import * as React from 'react';
import { cva, type VariantProps } from 'class-variance-authority';
import { cn } from '@/lib/utils';

/**
 * Variants = `Tone` (lib/realisasi/status.ts) + `outline`. `appearance="outline"` turns any tone into
 * an outlined pill (flags in Design §2). Colours chosen for ≥ 4.5:1 text contrast.
 */
export const badgeVariants = cva(
  'inline-flex items-center gap-1 whitespace-nowrap rounded-full border px-2 py-0.5 text-xs font-medium transition-colors',
  {
    variants: {
      variant: {
        neutral: 'border-slate-200 bg-slate-100 text-slate-700',
        blue: 'border-blue-200 bg-blue-50 text-blue-800',
        amber: 'border-amber-200 bg-amber-50 text-amber-900',
        green: 'border-green-200 bg-green-50 text-green-800',
        red: 'border-red-200 bg-red-50 text-red-800',
        purple: 'border-purple-200 bg-purple-50 text-purple-800',
        yellow: 'border-yellow-300 bg-yellow-100 text-yellow-900',
        outline: 'border-border bg-transparent text-foreground',
      },
      appearance: {
        solid: '',
        outline: 'bg-transparent',
      },
    },
    compoundVariants: [
      { appearance: 'outline', variant: 'neutral', className: 'border-slate-400 text-slate-700' },
      { appearance: 'outline', variant: 'blue', className: 'border-blue-500 text-blue-800' },
      { appearance: 'outline', variant: 'amber', className: 'border-amber-500 text-amber-900' },
      { appearance: 'outline', variant: 'green', className: 'border-green-600 text-green-800' },
      { appearance: 'outline', variant: 'red', className: 'border-red-500 text-red-800' },
      { appearance: 'outline', variant: 'purple', className: 'border-purple-500 text-purple-800' },
      { appearance: 'outline', variant: 'yellow', className: 'border-yellow-500 text-yellow-900' },
    ],
    defaultVariants: { variant: 'neutral', appearance: 'solid' },
  },
);

export type BadgeVariant = NonNullable<VariantProps<typeof badgeVariants>['variant']>;

export interface BadgeProps extends React.HTMLAttributes<HTMLSpanElement>, VariantProps<typeof badgeVariants> {}

export function Badge({ className, variant, appearance, ...props }: BadgeProps) {
  return <span className={cn(badgeVariants({ variant, appearance }), className)} {...props} />;
}
