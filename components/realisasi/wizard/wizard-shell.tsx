'use client';
/**
 * Frame of the single-page Kegiatan Baru form (Revisi V.1: no steps): autosave indicator on top, all
 * sections (Detail → Kerja sama → Peserta → Berkas → Ajukan) below as children.
 */
import { SaveIndicator, SaveStatusProvider } from '@/components/realisasi/wizard/save-status';

export const FORM_SECTIONS = [
  { id: 'bagian-detail', label: 'Detail & Kerja sama' },
  { id: 'bagian-peserta', label: 'Peserta' },
  { id: 'bagian-berkas', label: 'Berkas' },
  { id: 'bagian-ajukan', label: 'Ajukan' },
] as const;

export function WizardShell({
  draftId,
  savedAt,
  children,
}: {
  draftId: string | null;
  savedAt?: string | null;
  children: React.ReactNode;
}) {
  return (
    <SaveStatusProvider savedAt={savedAt}>
      <div className="space-y-6">
        <div className="sticky top-0 z-10 flex flex-wrap items-center justify-between gap-3 rounded-lg border bg-card px-4 py-3">
          <nav aria-label="Bagian formulir" className="flex flex-wrap gap-x-4 gap-y-1 text-sm">
            {FORM_SECTIONS.map((s, i) => (
              <a
                key={s.id}
                href={`#${s.id}`}
                className={draftId || i === 0 ? 'text-primary hover:underline' : 'pointer-events-none text-muted-foreground'}
                aria-disabled={!draftId && i > 0}
              >
                {i + 1}. {s.label}
              </a>
            ))}
          </nav>
          {draftId ? <SaveIndicator /> : <p className="text-xs text-muted-foreground">Draf dibuat setelah Detail disimpan.</p>}
        </div>
        {children}
      </div>
    </SaveStatusProvider>
  );
}
