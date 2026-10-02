/**
 * Activity files grouped by kind with optional version history (CONTRACTS §6.8).
 * No hooks/handlers → usable from server and client components (VERIFY queue imports it).
 */
import { FileText, History, Image as ImageIcon, Link2 } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { formatBytes, formatDateTime } from '@/lib/realisasi/format';
import { FILE_KIND_LABEL } from '@/lib/realisasi/status';
import type { ActivityFile, FileKind } from '@/lib/realisasi/types';

const KINDS: FileKind[] = ['ia', 'ir', 'mobility_bundle', 'evidence'];

function FileIcon({ file }: { file: ActivityFile }) {
  const cls = 'h-4 w-4 shrink-0 text-muted-foreground';
  if (file.url && !file.storage_path) return <Link2 className={cls} aria-hidden />;
  if (file.mime?.startsWith('image/')) return <ImageIcon className={cls} aria-hidden />;
  return <FileText className={cls} aria-hidden />;
}

function FileRow({ file, muted }: { file: ActivityFile; muted?: boolean }) {
  const isLink = Boolean(file.url && !file.storage_path);
  const name = file.filename ?? file.url ?? 'Berkas';
  return (
    <li className="flex flex-wrap items-center gap-x-3 gap-y-1 py-2 text-sm" data-testid={`file-${file.kind}`}>
      <FileIcon file={file} />
      <a
        href={file.href}
        target="_blank"
        rel="noopener noreferrer"
        className={muted ? 'text-muted-foreground underline-offset-2 hover:underline' : 'font-medium text-primary underline-offset-2 hover:underline'}
      >
        {name}
        <span className="sr-only"> (buka di tab baru)</span>
      </a>
      {file.kind !== 'evidence' && <Badge variant="outline">v{file.version}</Badge>}
      {!file.is_current && <Badge variant="neutral">Versi lama</Badge>}
      <span className="text-xs text-muted-foreground">
        {isLink ? 'Tautan' : file.size_bytes !== null ? formatBytes(file.size_bytes) : ''}
        {' · '}
        {file.uploaded_by_name ?? '–'}, {formatDateTime(file.uploaded_at)}
      </span>
    </li>
  );
}

/** `isMobility`: always show the mobility PDF slot (Revisi V.1); otherwise it shows only when a file exists. */
export function FileList({ files, showHistory = false, isMobility = false }: { files: ActivityFile[]; showHistory?: boolean; isMobility?: boolean }) {
  return (
    <div className="space-y-4" data-testid="file-list">
      {KINDS.map((kind) => {
        const ofKind = files.filter((f) => f.kind === kind);
        if (kind === 'mobility_bundle' && !isMobility && ofKind.length === 0) return null;
        const current = ofKind.filter((f) => f.is_current).sort((a, b) => b.version - a.version || b.id - a.id);
        const history = ofKind.filter((f) => !f.is_current).sort((a, b) => b.version - a.version || b.id - a.id);
        const headingId = `files-${kind}`;
        return (
          <section key={kind} aria-labelledby={headingId}>
            <h4 id={headingId} className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
              {FILE_KIND_LABEL[kind]}
              {(kind === 'ia' || kind === 'ir') && ' (PDF)'}
            </h4>
            {current.length === 0 ? (
              <p className="py-2 text-sm text-muted-foreground">
                {kind === 'evidence' ? 'Tidak ada bukti.' : 'Belum diunggah.'}
              </p>
            ) : (
              <ul className="divide-y">
                {current.map((f) => (
                  <FileRow key={f.id} file={f} />
                ))}
              </ul>
            )}
            {showHistory && history.length > 0 && (
              <details className="mt-1 rounded-md border bg-muted/30 px-3 py-1">
                <summary className="flex cursor-pointer items-center gap-1.5 py-1 text-xs font-medium text-muted-foreground">
                  <History className="h-3.5 w-3.5" aria-hidden />
                  Riwayat versi ({history.length})
                </summary>
                <ul className="divide-y">
                  {history.map((f) => (
                    <FileRow key={f.id} file={f} muted />
                  ))}
                </ul>
              </details>
            )}
          </section>
        );
      })}
    </div>
  );
}
