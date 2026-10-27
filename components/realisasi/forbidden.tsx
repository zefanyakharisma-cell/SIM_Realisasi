import Link from 'next/link';
import { ShieldAlert } from 'lucide-react';
import { buttonVariants } from '@/components/ui/button';

/** Rendered (HTTP 200) when a role opens a page it may not see; no data is fetched (CONTRACTS §7). */
export function Forbidden() {
  return (
    <div role="alert" className="mx-auto flex max-w-lg flex-col items-center gap-3 rounded-lg border bg-background px-6 py-12 text-center" data-testid="forbidden">
      <ShieldAlert className="size-10 text-warning-fg" aria-hidden="true" />
      <h1 className="text-xl font-semibold">Akses ditolak</h1>
      <p className="text-sm text-muted-foreground">Anda tidak memiliki akses ke halaman ini.</p>
      <Link href="/realisasi" className={buttonVariants({ variant: 'outline' })}>
        Kembali ke Dashboard
      </Link>
    </div>
  );
}
