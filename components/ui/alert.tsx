import * as React from 'react';
import { cva, type VariantProps } from 'class-variance-authority';
import { cn } from '@/lib/utils';

const alertVariants = cva(
  'relative w-full rounded-lg border px-4 py-3 text-sm [&>svg+div]:translate-y-[-3px] [&>svg]:absolute [&>svg]:left-4 [&>svg]:top-3.5 [&>svg]:size-4 [&>svg~*]:pl-7',
  {
    variants: {
      variant: {
        default: 'bg-background text-foreground',
        // Tinted ground + hairline in the tone; text stays text-primary, the icon carries the tone ink.
        info: 'border-info-line bg-info-subtle text-foreground [&>svg]:text-info-fg',
        warning: 'border-warning-line bg-warning-subtle text-foreground [&>svg]:text-warning-fg',
        /** status-pending: a revision is requested (Perlu Revisi). */
        pending: 'border-pending-line bg-pending-subtle text-foreground [&>svg]:text-pending-fg',
        success: 'border-success-line bg-success-subtle text-foreground [&>svg]:text-success-fg',
        destructive: 'border-danger-line bg-danger-subtle text-foreground [&>svg]:text-danger-fg',
      },
    },
    defaultVariants: { variant: 'default' },
  },
);

/** Use role="alert" only for messages that appear in response to an action; static notices get role="status" or none. */
export const Alert = React.forwardRef<HTMLDivElement, React.HTMLAttributes<HTMLDivElement> & VariantProps<typeof alertVariants>>(
  ({ className, variant, ...props }, ref) => <div ref={ref} className={cn(alertVariants({ variant }), className)} {...props} />,
);
Alert.displayName = 'Alert';

export const AlertTitle = React.forwardRef<HTMLHeadingElement, React.HTMLAttributes<HTMLHeadingElement>>(({ className, ...props }, ref) => (
  <h5 ref={ref} className={cn('mb-1 font-semibold leading-none tracking-tight', className)} {...props} />
));
AlertTitle.displayName = 'AlertTitle';

export const AlertDescription = React.forwardRef<HTMLDivElement, React.HTMLAttributes<HTMLDivElement>>(({ className, ...props }, ref) => (
  <div ref={ref} className={cn('text-sm [&_p]:leading-relaxed', className)} {...props} />
));
AlertDescription.displayName = 'AlertDescription';
