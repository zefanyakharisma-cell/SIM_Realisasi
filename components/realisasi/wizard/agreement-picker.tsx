'use client';
/**
 * Kerja sama picker (Design §3.3, R-03..R-06): multi combobox fed by `documents_valid_between`
 * through GET /api/lookup/documents. Disabled until both dates are valid. Selected agreements render
 * as cards with read-only Mitra + Negara and the out-of-scope warning (R-05, warn only).
 */
import { useEffect, useMemo, useState } from 'react';
import { AlertTriangle, Archive, Loader2, X } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Combobox, type ComboboxOption } from '@/components/ui/combobox';
import { CountryFlag } from '@/components/realisasi/country-flag';
import { formatDate } from '@/lib/realisasi/format';
import type { DocumentOption } from '@/lib/realisasi/types';

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

type LoadState = { kind: 'idle' } | { kind: 'loading' } | { kind: 'ok'; docs: DocumentOption[] } | { kind: 'error'; message: string };

export interface AgreementPickerProps {
  id: string;
  labelId: string;
  start: string;
  end: string;
  unitId: number | null;
  value: number[];
  onChange: (ids: number[]) => void;
  /** Already-linked documents (from activity_detail) so cards render before the lookup returns. */
  known: DocumentOption[];
  error?: string;
  errorId?: string;
  disabled?: boolean;
}

function validity(d: DocumentOption): string {
  if (d.auto_renewed) return 'diperpanjang otomatis';
  return `berlaku s.d. ${formatDate(d.end_date)}`;
}

export function AgreementPicker({ id, labelId, start, end, unitId, value, onChange, known, error, errorId, disabled }: AgreementPickerProps) {
  const datesReady = DATE_RE.test(start) && DATE_RE.test(end) && end >= start;
  const [fetched, setState] = useState<LoadState>({ kind: 'idle' });
  const [retry, setRetry] = useState(0);
  const state: LoadState = useMemo(() => (datesReady ? fetched : { kind: 'idle' }), [datesReady, fetched]);

  useEffect(() => {
    if (!datesReady) return;
    const ctrl = new AbortController();
    const timer = setTimeout(async () => {
      setState({ kind: 'loading' });
      try {
        const qs = new URLSearchParams({ start, end, ...(unitId ? { unit_id: String(unitId) } : {}) });
        const res = await fetch(`/api/lookup/documents?${qs.toString()}`, { signal: ctrl.signal });
        const body = (await res.json()) as { documents?: DocumentOption[]; message?: string };
        if (!res.ok) throw new Error(body.message ?? 'Daftar kerja sama tidak dapat dimuat.');
        setState({ kind: 'ok', docs: body.documents ?? [] });
      } catch (e) {
        if (ctrl.signal.aborted) return;
        setState({ kind: 'error', message: e instanceof Error ? e.message : 'Daftar kerja sama tidak dapat dimuat.' });
      }
    }, 300);
    return () => {
      ctrl.abort();
      clearTimeout(timer);
    };
  }, [datesReady, start, end, unitId, retry]);

  const available = useMemo(() => (state.kind === 'ok' ? state.docs : []), [state]);
  const byId = useMemo(() => {
    const m = new Map<number, DocumentOption>();
    for (const d of known) m.set(d.document_id, d);
    for (const d of available) m.set(d.document_id, d);
    return m;
  }, [known, available]);
  const validIds = useMemo(() => new Set(available.map((d) => d.document_id)), [available]);

  const options: ComboboxOption[] = available.map((d) => {
    const partners = d.partners.map((p) => p.name).join(', ');
    return {
      value: String(d.document_id),
      label: `${d.doc_number} · ${d.kind}`,
      keywords: [d.title, partners, ...d.partners.map((p) => p.country_name)],
      content: (
        <span className="block text-sm">
          <span className="font-medium">{d.doc_number}</span> · {d.kind} · {partners}{' '}
          {d.partners.map((p) => (
            <CountryFlag key={p.partner_id} code={p.country_code} />
          ))}{' '}
          · <span className="text-muted-foreground">{validity(d)}</span>
          {d.is_archived && (
            <Badge variant="neutral" className="ml-2">
              Arsip (diperbarui)
            </Badge>
          )}
          <span className="block truncate text-xs text-muted-foreground">{d.title}</span>
        </span>
      ),
    };
  });

  const describedBy = [errorId && error ? errorId : null, `${id}-hint`].filter(Boolean).join(' ');

  return (
    <div className="space-y-3">
      <Combobox
        id={id}
        aria-labelledby={labelId}
        aria-invalid={Boolean(error) || undefined}
        aria-describedby={describedBy}
        options={options}
        value={value.map(String)}
        onChange={(v) => onChange(v.map(Number))}
        disabled={disabled || state.kind !== 'ok'}
        placeholder={datesReady ? 'Pilih kerja sama…' : 'Isi tanggal mulai dan selesai terlebih dahulu'}
        searchPlaceholder="Cari nomor dokumen, mitra, atau negara…"
        emptyText="Tidak ada kerja sama yang berlaku pada tanggal kegiatan."
        hideChips
      />
      <p id={`${id}-hint`} className="flex items-center gap-1.5 text-xs text-muted-foreground" aria-live="polite">
        {state.kind === 'loading' && (
          <>
            <Loader2 className="h-3.5 w-3.5 animate-spin" aria-hidden /> Memuat kerja sama yang berlaku…
          </>
        )}
        {state.kind === 'ok' && `${available.length} kerja sama berlaku pada tanggal kegiatan (termasuk yang sudah diarsipkan).`}
        {state.kind === 'idle' && 'Daftar kerja sama mengikuti tanggal kegiatan.'}
        {state.kind === 'error' && (
          <span className="flex items-center gap-2 text-red-700">
            {state.message}
            <Button type="button" variant="link" size="sm" className="h-auto p-0" onClick={() => setRetry((n) => n + 1)}>
              Coba lagi
            </Button>
          </span>
        )}
      </p>

      {value.length > 0 && (
        <ul className="grid gap-3 md:grid-cols-2" aria-label="Kerja sama terpilih">
          {value.map((docId) => {
            const d = byId.get(docId);
            const notValid = state.kind === 'ok' && !validIds.has(docId);
            return (
              <li key={docId} className="relative rounded-md border p-3 text-sm" data-testid="agreement-card">
                <Button
                  type="button"
                  variant="ghost"
                  size="icon"
                  className="absolute right-1 top-1 h-7 w-7"
                  onClick={() => onChange(value.filter((x) => x !== docId))}
                  aria-label={`Hapus kerja sama ${d?.doc_number ?? docId}`}
                  disabled={disabled}
                >
                  <X aria-hidden />
                </Button>
                {d ? (
                  <>
                    <p className="pr-8">
                      <span className="font-medium">{d.doc_number}</span> <Badge variant="outline">{d.kind}</Badge>
                      {d.is_archived && (
                        <Badge variant="neutral" className="ml-1">
                          <Archive className="h-3 w-3" aria-hidden /> Arsip (diperbarui)
                        </Badge>
                      )}
                    </p>
                    <p className="mt-1 text-muted-foreground">{d.title}</p>
                    {d.current_doc_number !== d.doc_number && (
                      <p className="mt-1 text-xs text-muted-foreground">Dokumen saat ini: {d.current_doc_number}</p>
                    )}
                    <dl className="mt-2 grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-xs">
                      {d.partners.map((p) => (
                        <div key={p.partner_id} className="contents">
                          <dt className="text-muted-foreground">Mitra</dt>
                          <dd>
                            {p.name} · <CountryFlag code={p.country_code} name={p.country_name} />
                          </dd>
                        </div>
                      ))}
                      <dt className="text-muted-foreground">Masa berlaku</dt>
                      <dd>
                        {formatDate(d.start_date)} – {d.auto_renewed ? 'diperpanjang otomatis' : formatDate(d.end_date)}
                      </dd>
                    </dl>
                    {!d.in_scope && (
                      <p className="mt-2 flex items-start gap-1.5 rounded bg-amber-50 p-2 text-xs text-amber-900" data-testid="out-of-scope-warning">
                        <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" aria-hidden />
                        Unit pengaju tidak termasuk dalam Lingkup Kerja Sama dokumen ini. Pengajuan tetap dapat dilanjutkan.
                      </p>
                    )}
                  </>
                ) : (
                  <p className="pr-8 text-muted-foreground">Dokumen #{docId}</p>
                )}
                {notValid && (
                  <p className="mt-2 flex items-start gap-1.5 rounded bg-red-50 p-2 text-xs text-red-900" role="status">
                    <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" aria-hidden />
                    Kerja sama ini tidak berlaku pada tanggal kegiatan. Hapus atau ubah tanggal.
                  </p>
                )}
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
