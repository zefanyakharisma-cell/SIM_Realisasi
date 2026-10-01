'use client';
/**
 * Autosave indicator shared by the wizard steps ("Tersimpan sebagai draf · 10:42", Design §3.3).
 * Steps report through `useSaveStatus()`; the header renders `<SaveIndicator />`.
 */
import { createContext, useCallback, useContext, useMemo, useState } from 'react';
import { AlertCircle, CheckCircle2, Loader2 } from 'lucide-react';
import { formatTime } from '@/lib/realisasi/format';

type State =
  | { kind: 'idle' }
  | { kind: 'dirty' }
  | { kind: 'saving' }
  | { kind: 'saved'; at: string }
  | { kind: 'error'; message: string };

interface Ctx {
  state: State;
  setDirty: () => void;
  setSaving: () => void;
  setSaved: (at?: string) => void;
  setError: (message: string) => void;
}

const SaveStatusContext = createContext<Ctx | null>(null);

export function SaveStatusProvider({ children, savedAt }: { children: React.ReactNode; savedAt?: string | null }) {
  const [state, setState] = useState<State>(savedAt ? { kind: 'saved', at: savedAt } : { kind: 'idle' });
  const setDirty = useCallback(() => setState({ kind: 'dirty' }), []);
  const setSaving = useCallback(() => setState({ kind: 'saving' }), []);
  const setSaved = useCallback((at?: string) => setState({ kind: 'saved', at: at ?? new Date().toISOString() }), []);
  const setError = useCallback((message: string) => setState({ kind: 'error', message }), []);
  const value = useMemo(() => ({ state, setDirty, setSaving, setSaved, setError }), [state, setDirty, setSaving, setSaved, setError]);
  return <SaveStatusContext.Provider value={value}>{children}</SaveStatusContext.Provider>;
}

const NOOP: Ctx = {
  state: { kind: 'idle' },
  setDirty: () => {},
  setSaving: () => {},
  setSaved: () => {},
  setError: () => {},
};

/** Works outside a provider too (revision / IO edit pages) — calls become no-ops. */
export function useSaveStatus(): Ctx {
  return useContext(SaveStatusContext) ?? NOOP;
}

export function SaveIndicator() {
  const { state } = useSaveStatus();
  return (
    <p className="flex min-h-5 items-center gap-1.5 text-xs text-muted-foreground" role="status" aria-live="polite" data-testid="autosave-status">
      {state.kind === 'saving' && (
        <>
          <Loader2 className="h-3.5 w-3.5 animate-spin" aria-hidden />
          Menyimpan…
        </>
      )}
      {state.kind === 'saved' && (
        <>
          <CheckCircle2 className="h-3.5 w-3.5 text-green-700" aria-hidden />
          Tersimpan sebagai draf · {formatTime(state.at)}
        </>
      )}
      {state.kind === 'dirty' && 'Perubahan belum tersimpan'}
      {state.kind === 'error' && (
        <span className="flex items-center gap-1.5 text-red-700">
          <AlertCircle className="h-3.5 w-3.5" aria-hidden />
          Gagal menyimpan: {state.message}
        </span>
      )}
    </p>
  );
}
