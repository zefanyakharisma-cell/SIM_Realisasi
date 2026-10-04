import * as React from 'react';
import { cn } from '@/lib/utils';

/** Page title block; the title is the page's single <h1>. */
export function PageHeader({
  title,
  description,
  actions,
  className,
}: {
  title: React.ReactNode;
  description?: React.ReactNode;
  actions?: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={cn('mb-6 flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between', className)}>
      <div className="min-w-0 space-y-1" data-tour="page-header">
        <h1 className="text-2xl font-semibold tracking-tight">{title}</h1>
        {description ? <div className="text-sm text-muted-foreground">{description}</div> : null}
      </div>
      {actions ? (
        <div className="flex flex-wrap items-center gap-2" data-tour="page-actions">
          {actions}
        </div>
      ) : null}
    </div>
  );
}
