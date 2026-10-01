import { FileSpreadsheet } from 'lucide-react';
import { buttonVariants } from '@/components/ui/button';
import { cn, toQueryString } from '@/lib/utils';
import type { ExportKind } from '@/lib/realisasi/types';

/** `<a data-testid="export-excel" href="/api/export/{kind}?{params}" download>Unduh Excel</a>` (CONTRACTS §6.9). */
export function ExportButton({
  kind,
  params,
  label = 'Unduh Excel',
  className,
  variant = 'outline',
  size = 'sm',
}: {
  kind: ExportKind;
  params?: URLSearchParams | Record<string, string>;
  label?: string;
  className?: string;
  variant?: 'outline' | 'default' | 'ghost' | 'secondary';
  size?: 'sm' | 'default';
}) {
  return (
    <a
      data-testid="export-excel"
      href={`/api/export/${kind}${toQueryString(params)}`}
      download
      className={cn(buttonVariants({ variant, size }), className)}
    >
      <FileSpreadsheet aria-hidden="true" />
      {label}
    </a>
  );
}
