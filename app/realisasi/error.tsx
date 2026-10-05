'use client';

import * as React from 'react';
import { AlertTriangle } from 'lucide-react';
import { Button } from '@/components/ui/button';

export default function RealisasiError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  const headingRef = React.useRef<HTMLHeadingElement>(null);
  React.useEffect(() => {
    console.error(error);
    headingRef.current?.focus();
  }, [error]);

  return (
    <div role="alert" className="mx-auto flex max-w-lg flex-col items-center gap-3 rounded-lg border bg-background px-6 py-12 text-center">
      <AlertTriangle className="size-10 text-danger-fg" aria-hidden="true" />
      <h1 ref={headingRef} tabIndex={-1} className="text-xl font-semibold focus:outline-none">
        Terjadi kesalahan
      </h1>
      <p className="text-sm text-muted-foreground">Halaman ini tidak dapat dimuat. Coba lagi; jika masalah berlanjut, hubungi Admin IO.</p>
      {error.digest ? <p className="text-xs text-muted-foreground">Kode: {error.digest}</p> : null}
      <Button onClick={reset}>Coba lagi</Button>
    </div>
  );
}
