import * as React from 'react';
import { cn } from '@/lib/utils';

/** Decorative placeholder; wrap groups in an element with aria-busy / an sr-only "Memuat…" label. */
export function Skeleton({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return <div aria-hidden="true" className={cn('animate-pulse rounded-md bg-border', className)} {...props} />;
}
