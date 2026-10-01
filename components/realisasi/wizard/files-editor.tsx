'use client';
/**
 * Step 3 — Berkas (Design §3.3; R-07, R-13): IA + IR drop zones (PDF, new upload = new version),
 * optional evidence files (PDF/JPG/PNG) and links. Uploads go through POST /api/upload; the page is
 * refreshed afterwards so versions/history and the checklist come from the DB.
 */
import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { AlertCircle, Eye, Link2, Trash2 } from 'lucide-react';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { FileDrop } from '@/components/ui/file-drop';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { toast } from '@/components/ui/toaster';
import { FileList } from '@/components/realisasi/activity/file-list';
import { useSaveStatus } from '@/components/realisasi/wizard/save-status';
import { addEvidenceLink, removeActivityFile } from '@/lib/realisasi/actions/submission';
import { formatBytes, formatDateTime } from '@/lib/realisasi/format';
import { FILE_KIND_LABEL } from '@/lib/realisasi/status';
import { MAX_FILE_BYTES } from '@/lib/storage';
import type { ActivityFile } from '@/lib/realisasi/types';

type Target = 'ia' | 'ir' | 'evidence';

export function FilesEditor({ activityId, files, disabled }: { activityId: string; files: ActivityFile[]; disabled?: boolean }) {
  const router = useRouter();
  const save = useSaveStatus();
  const [busy, setBusy] = useState<Target | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [linkUrl, setLinkUrl] = useState('');
  const [linkLabel, setLinkLabel] = useState('');
  const [linkError, setLinkError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  async function upload(target: Target, list: File[]) {
    setError(null);
    setBusy(target);
    save.setSaving();
    try {
      for (const file of list) {
        const fd = new FormData();
        fd.set('activity_id', activityId);
        fd.set('target', target);
        fd.set('file', file);
        const res = await fetch('/api/upload', { method: 'POST', body: fd });
        const body = (await res.json().catch(() => ({}))) as { message?: string; version?: number };
        if (!res.ok) throw new Error(body.message ?? 'Berkas gagal diunggah.');
        toast.success(`${file.name} diunggah${target !== 'evidence' && body.version ? ` (v${body.version})` : ''}.`);
      }
      save.setSaved();
      router.refresh();
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'Berkas gagal diunggah.';
      setError(msg);
      save.setError(msg);
    } finally {
      setBusy(null);
    }
  }

  function addLink() {
    setLinkError(null);
    startTransition(async () => {
      const res = await addEvidenceLink(activityId, linkUrl, linkLabel);
      if (!res.ok) {
        setLinkError(res.message);
        return;
      }
      setLinkUrl('');
      setLinkLabel('');
      toast.success('Tautan bukti ditambahkan.');
      router.refresh();
    });
  }

  function remove(f: ActivityFile) {
    startTransition(async () => {
      const res = await removeActivityFile(f.id);
      if (!res.ok) {
        setError(res.message);
        return;
      }
      toast.success('Bukti dihapus.');
      router.refresh();
    });
  }

  const current = (kind: 'ia' | 'ir') =>
    files.filter((f) => f.kind === kind && f.is_current).sort((a, b) => b.version - a.version)[0] ?? null;
  const evidence = files.filter((f) => f.kind === 'evidence' && f.is_current);
  const hasHistory = files.some((f) => !f.is_current);

  return (
    <div className="space-y-8" data-testid="files-editor">
      {error && (
        <Alert variant="destructive" role="alert">
          <AlertCircle aria-hidden />
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}

      <div className="grid gap-6 md:grid-cols-2">
        {(['ia', 'ir'] as const).map((kind) => {
          const f = current(kind);
          const headingId = `drop-${kind}-title`;
          return (
            <section key={kind} aria-labelledby={headingId} className="space-y-3 rounded-lg border p-4" data-testid={`drop-${kind}`}>
              <h3 id={headingId} className="flex items-center gap-2 font-medium">
                {FILE_KIND_LABEL[kind]} (PDF) <Badge variant="red">Wajib</Badge>
              </h3>
              {f ? (
                <div className="flex flex-wrap items-center gap-2 text-sm" data-testid={`current-${kind}`}>
                  <span className="font-medium">{f.filename}</span>
                  <Badge variant="outline">v{f.version}</Badge>
                  <span className="text-muted-foreground">
                    {f.size_bytes !== null ? formatBytes(f.size_bytes) : ''} · {formatDateTime(f.uploaded_at)}
                  </span>
                  <Button asChild variant="link" size="sm" className="h-auto p-0">
                    <a href={f.href} target="_blank" rel="noopener noreferrer">
                      <Eye aria-hidden /> Pratinjau<span className="sr-only"> {FILE_KIND_LABEL[kind]} (tab baru)</span>
                    </a>
                  </Button>
                </div>
              ) : (
                <p className="text-sm text-red-700">Belum diunggah.</p>
              )}
              <FileDrop
                id={`upload-${kind}`}
                accept="application/pdf"
                maxBytes={MAX_FILE_BYTES}
                disabled={disabled || busy !== null}
                label={busy === kind ? 'Mengunggah…' : f ? 'Unggah versi baru' : 'Seret PDF ke sini atau klik untuk memilih'}
                hint="PDF, maks. 10 MB"
                aria-describedby={headingId}
                onFiles={(list) => void upload(kind, list)}
              />
            </section>
          );
        })}
      </div>

      <section aria-labelledby="evidence-title" className="space-y-4 rounded-lg border p-4">
        <h3 id="evidence-title" className="font-medium">
          Bukti (opsional)
        </h3>
        {evidence.length > 0 && (
          <ul className="divide-y text-sm">
            {evidence.map((f) => (
              <li key={f.id} className="flex flex-wrap items-center gap-2 py-2">
                {f.url && !f.storage_path ? <Link2 className="h-4 w-4 text-muted-foreground" aria-hidden /> : null}
                <a href={f.href} target="_blank" rel="noopener noreferrer" className="text-primary hover:underline">
                  {f.filename ?? f.url}
                  <span className="sr-only"> (tab baru)</span>
                </a>
                {f.size_bytes !== null && <span className="text-muted-foreground">{formatBytes(f.size_bytes)}</span>}
                <Button
                  type="button"
                  variant="ghost"
                  size="icon"
                  className="ml-auto"
                  disabled={disabled || pending}
                  onClick={() => remove(f)}
                  aria-label={`Hapus bukti ${f.filename ?? f.url ?? ''}`}
                >
                  <Trash2 aria-hidden />
                </Button>
              </li>
            ))}
          </ul>
        )}
        <FileDrop
          id="upload-evidence"
          accept="application/pdf,image/jpeg,image/png"
          maxBytes={MAX_FILE_BYTES}
          multiple
          disabled={disabled || busy !== null}
          label={busy === 'evidence' ? 'Mengunggah…' : 'Seret berkas bukti ke sini atau klik untuk memilih'}
          hint="PDF, JPG, PNG — maks. 10 MB per berkas"
          onFiles={(list) => void upload('evidence', list)}
        />
        <fieldset className="grid gap-3 md:grid-cols-[1fr_1fr_auto]">
          <legend className="mb-2 text-sm font-medium">Tambah tautan</legend>
          <div className="space-y-1">
            <Label htmlFor="ev-url">URL</Label>
            <Input
              id="ev-url"
              type="url"
              placeholder="https://"
              value={linkUrl}
              onChange={(e) => setLinkUrl(e.target.value)}
              aria-invalid={Boolean(linkError) || undefined}
              aria-describedby={linkError ? 'ev-error' : undefined}
            />
          </div>
          <div className="space-y-1">
            <Label htmlFor="ev-label">Label</Label>
            <Input id="ev-label" value={linkLabel} onChange={(e) => setLinkLabel(e.target.value)} placeholder="mis. Berita di situs mitra" />
          </div>
          <div className="flex items-end">
            <Button type="button" variant="outline" onClick={addLink} loading={pending} disabled={disabled || !linkUrl || !linkLabel}>
              Tambah tautan
            </Button>
          </div>
          {linkError && (
            <p id="ev-error" className="text-xs text-destructive md:col-span-3" role="alert">
              {linkError}
            </p>
          )}
        </fieldset>
      </section>

      {hasHistory && (
        <section aria-labelledby="history-title" className="space-y-2">
          <h3 id="history-title" className="font-medium">
            Riwayat berkas
          </h3>
          <FileList files={files} showHistory />
        </section>
      )}
    </div>
  );
}
