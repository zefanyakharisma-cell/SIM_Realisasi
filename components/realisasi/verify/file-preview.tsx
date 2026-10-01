'use client';

import { useState } from 'react';
import { ExternalLink } from 'lucide-react';
import { FILE_KIND_LABEL } from '@/lib/realisasi/status';
import { cn } from '@/lib/utils';
import type { ActivityFile } from '@/lib/realisasi/types';

/** IA / IR side-by-side preview for the queue's expanded row (Design §3.5). */
export function IaIrPreview({ files, code }: { files: ActivityFile[]; code: string }) {
  const current = (['ia', 'ir'] as const).map((k) => ({ kind: k, file: files.find((f) => f.kind === k && f.is_current) ?? null }));
  const [active, setActive] = useState<'ia' | 'ir'>('ia');
  const shown = current.find((c) => c.kind === active)?.file ?? null;

  return (
    <div className="flex h-full flex-col gap-2">
      <div role="tablist" aria-label={`Pratinjau berkas ${code}`} className="flex gap-1">
        {current.map((c) => (
          <button
            key={c.kind}
            type="button"
            role="tab"
            id={`tab-${code}-${c.kind}`}
            aria-selected={active === c.kind}
            aria-controls={`tabpanel-${code}`}
            tabIndex={active === c.kind ? 0 : -1}
            onClick={() => setActive(c.kind)}
            onKeyDown={(e) => {
              // ARIA tabs pattern (L-2): roving tabindex with Arrow keys / Home / End.
              const kinds = current.map((x) => x.kind);
              const i = kinds.indexOf(c.kind);
              let next: number | null = null;
              if (e.key === 'ArrowRight') next = (i + 1) % kinds.length;
              else if (e.key === 'ArrowLeft') next = (i - 1 + kinds.length) % kinds.length;
              else if (e.key === 'Home') next = 0;
              else if (e.key === 'End') next = kinds.length - 1;
              if (next === null) return;
              e.preventDefault();
              const k = kinds[next]!;
              setActive(k);
              document.getElementById(`tab-${code}-${k}`)?.focus();
            }}
            className={cn(
              'rounded-md border px-3 py-1.5 text-xs font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
              active === c.kind ? 'border-primary bg-primary text-primary-foreground' : 'bg-background hover:bg-muted',
            )}
          >
            {c.kind.toUpperCase()} · {FILE_KIND_LABEL[c.kind]}
            {c.file ? ` v${c.file.version}` : ' (belum ada)'}
          </button>
        ))}
      </div>
      <div id={`tabpanel-${code}`} role="tabpanel" aria-labelledby={`tab-${code}-${active}`} className="flex flex-1 flex-col gap-1">
        {shown ? (
          <>
            <iframe src={shown.href} title={`${FILE_KIND_LABEL[active]} ${code}`} className="min-h-[420px] w-full flex-1 rounded-md border bg-white" />
            <a href={shown.href} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1 text-xs font-medium text-primary underline underline-offset-4">
              <ExternalLink className="h-3.5 w-3.5" aria-hidden="true" />
              Buka {shown.filename ?? FILE_KIND_LABEL[active]} di tab baru
            </a>
          </>
        ) : (
          <p className="rounded-md border border-dashed p-6 text-center text-sm text-muted-foreground">
            {FILE_KIND_LABEL[active]} belum diunggah.
          </p>
        )}
      </div>
    </div>
  );
}
