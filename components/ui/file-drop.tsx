'use client';

/**
 * Drop zone (Design §3.3 Berkas / transcripts). Keyboard: the zone is a real <button> that opens the
 * file picker; drag & drop is an enhancement. Rejections are reported through `onReject` and an
 * aria-live message. Size/type are pre-checked here; the server re-validates (R-13).
 */
import * as React from 'react';
import { UploadCloud } from 'lucide-react';
import { cn } from '@/lib/utils';
import { formatBytes } from '@/lib/realisasi/format';

export interface FileDropProps {
  /** e.g. 'application/pdf' or 'application/pdf,image/jpeg,image/png' */
  accept: string;
  maxBytes: number;
  onFiles: (files: File[]) => void;
  onReject?: (rejections: Array<{ file: File; reason: 'size' | 'type' }>) => void;
  multiple?: boolean;
  disabled?: boolean;
  label?: string;
  hint?: string;
  id?: string;
  className?: string;
  'aria-invalid'?: boolean;
  'aria-describedby'?: string;
}

function matchesAccept(file: File, accept: string): boolean {
  const rules = accept.split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
  if (rules.length === 0) return true;
  const type = file.type.toLowerCase();
  const name = file.name.toLowerCase();
  return rules.some((r) => (r.startsWith('.') ? name.endsWith(r) : r.endsWith('/*') ? type.startsWith(r.slice(0, -1)) : type === r));
}

export function FileDrop({
  accept,
  maxBytes,
  onFiles,
  onReject,
  multiple = false,
  disabled,
  label = 'Seret berkas ke sini atau klik untuk memilih',
  hint,
  id,
  className,
  ...aria
}: FileDropProps) {
  const inputRef = React.useRef<HTMLInputElement>(null);
  const [dragging, setDragging] = React.useState(false);
  const [message, setMessage] = React.useState('');
  const hintId = React.useId();

  const handle = (list: FileList | null) => {
    if (!list || disabled) return;
    const files = Array.from(list).slice(0, multiple ? undefined : 1);
    const ok: File[] = [];
    const rejected: Array<{ file: File; reason: 'size' | 'type' }> = [];
    for (const f of files) {
      if (!matchesAccept(f, accept)) rejected.push({ file: f, reason: 'type' });
      else if (f.size > maxBytes) rejected.push({ file: f, reason: 'size' });
      else ok.push(f);
    }
    if (rejected.length > 0) {
      setMessage(
        rejected
          .map((r) => (r.reason === 'size' ? `${r.file.name}: melebihi ${formatBytes(maxBytes)}` : `${r.file.name}: format tidak diizinkan`))
          .join('; '),
      );
      onReject?.(rejected);
    } else {
      setMessage(ok.length > 0 ? `${ok.length} berkas dipilih` : '');
    }
    if (ok.length > 0) onFiles(ok);
    if (inputRef.current) inputRef.current.value = '';
  };

  const describedBy = [hint ? hintId : null, aria['aria-describedby']].filter(Boolean).join(' ') || undefined;

  return (
    <div className={className}>
      <button
        type="button"
        id={id}
        disabled={disabled}
        data-invalid={aria['aria-invalid'] ? 'true' : undefined}
        aria-describedby={describedBy}
        onClick={() => inputRef.current?.click()}
        onDragOver={(e) => {
          e.preventDefault();
          if (!disabled) setDragging(true);
        }}
        onDragLeave={() => setDragging(false)}
        onDrop={(e) => {
          e.preventDefault();
          setDragging(false);
          handle(e.dataTransfer.files);
        }}
        className={cn(
          'flex w-full flex-col items-center justify-center gap-1.5 rounded-lg border-2 border-dashed border-input bg-background px-4 py-6 text-center text-sm transition-colors hover:bg-muted/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-50 data-[invalid=true]:border-destructive',
          dragging && 'border-primary bg-primary/5',
        )}
      >
        <UploadCloud className="size-6 text-muted-foreground" aria-hidden="true" />
        <span className="font-medium">{label}</span>
        {hint ? (
          <span id={hintId} className="text-xs text-muted-foreground">
            {hint}
          </span>
        ) : null}
      </button>
      <input
        ref={inputRef}
        type="file"
        className="sr-only"
        tabIndex={-1}
        aria-hidden="true"
        accept={accept}
        multiple={multiple}
        disabled={disabled}
        onChange={(e) => handle(e.target.files)}
      />
      <p className="mt-1 text-xs text-muted-foreground" aria-live="polite">
        {message}
      </p>
    </div>
  );
}
