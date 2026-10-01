'use client';
/**
 * Autosave indicator shared by the wizard steps ("Tersimpan sebagai draf · 10:42", Design §3.3).
 * Steps report through `useSaveStatus()`; the header renders `<SaveIndicator />`.
 *
 * Also the flush/guard hub (frontend review M-1):
 * - editors `registerFlush()` a function that persists pending (debounced/queued) edits;
 *   navigation, submit and commit `await flush()` first and stay put when it reports `false`;
 * - editors without autosave (revision Detail) `setBlocker(id, reason)` while they hold unsaved
 *   edits, which disables "Ajukan ulang";
 * - a `beforeunload` prompt is armed while anything is unsaved.
 */
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import { AlertCircle, CheckCircle2, Loader2 } from 'lucide-react';
import { useRouter } from 'next/navigation';
import { formatTime } from '@/lib/realisasi/format';

type State =
  | { kind: 'idle' }
  | { kind: 'dirty' }
  | { kind: 'saving' }
  | { kind: 'saved'; at: string }
  | { kind: 'error'; message: string };

/** Persists pending edits; resolves `true` when nothing unsaved remains. */
export type Flusher = () => Promise<boolean>;

/** Stable callbacks (identity never changes) — safe in effect dependency lists. */
export interface SaveActions {
  setDirty: () => void;
  setSaving: () => void;
  setSaved: (at?: string) => void;
  setError: (message: string) => void;
  registerFlush: (fn: Flusher) => () => void;
  flush: () => Promise<boolean>;
  setBlocker: (id: string, reason: string | null) => void;
}

interface Ctx extends SaveActions {
  state: State;
  /** First unsaved-edit reason that cannot be flushed automatically, or null. */
  blocker: string | null;
}

const SaveStatusContext = createContext<Ctx | null>(null);
const SaveActionsContext = createContext<SaveActions | null>(null);

export function SaveStatusProvider({ children, savedAt }: { children: React.ReactNode; savedAt?: string | null }) {
  const [state, setState] = useState<State>(savedAt ? { kind: 'saved', at: savedAt } : { kind: 'idle' });
  const [blockers, setBlockers] = useState<Record<string, string>>({});
  const flushers = useRef(new Set<Flusher>());
  const setDirty = useCallback(() => setState({ kind: 'dirty' }), []);
  const setSaving = useCallback(() => setState({ kind: 'saving' }), []);
  const setSaved = useCallback((at?: string) => setState({ kind: 'saved', at: at ?? new Date().toISOString() }), []);
  const setError = useCallback((message: string) => setState({ kind: 'error', message }), []);
  const registerFlush = useCallback((fn: Flusher) => {
    flushers.current.add(fn);
    return () => {
      flushers.current.delete(fn);
    };
  }, []);
  const flush = useCallback(async () => {
    const results = await Promise.all([...flushers.current].map((fn) => fn().catch(() => false)));
    return results.every(Boolean);
  }, []);
  const setBlocker = useCallback((id: string, reason: string | null) => {
    setBlockers((b) => {
      if (reason === null) {
        if (!(id in b)) return b;
        const { [id]: _drop, ...rest } = b;
        return rest;
      }
      return b[id] === reason ? b : { ...b, [id]: reason };
    });
  }, []);
  const blocker = Object.values(blockers)[0] ?? null;

  const unsaved = state.kind === 'dirty' || state.kind === 'saving' || blocker !== null;
  useEffect(() => {
    if (!unsaved) return;
    const onBeforeUnload = (e: BeforeUnloadEvent) => {
      e.preventDefault();
      e.returnValue = '';
    };
    window.addEventListener('beforeunload', onBeforeUnload);
    return () => window.removeEventListener('beforeunload', onBeforeUnload);
  }, [unsaved]);

  const actions = useMemo<SaveActions>(
    () => ({ setDirty, setSaving, setSaved, setError, registerFlush, flush, setBlocker }),
    [setDirty, setSaving, setSaved, setError, registerFlush, flush, setBlocker],
  );
  const value = useMemo(() => ({ ...actions, state, blocker }), [actions, state, blocker]);
  return (
    <SaveActionsContext.Provider value={actions}>
      <SaveStatusContext.Provider value={value}>{children}</SaveStatusContext.Provider>
    </SaveActionsContext.Provider>
  );
}

const NOOP_ACTIONS: SaveActions = {
  setDirty: () => {},
  setSaving: () => {},
  setSaved: () => {},
  setError: () => {},
  registerFlush: () => () => {},
  flush: async () => true,
  setBlocker: () => {},
};
const NOOP: Ctx = { ...NOOP_ACTIONS, state: { kind: 'idle' }, blocker: null };

/** Works outside a provider too — calls become no-ops and `flush()` resolves `true`. */
export function useSaveStatus(): Ctx {
  return useContext(SaveStatusContext) ?? NOOP;
}

/** Only the stable callbacks (editors): does not re-render on every status change. */
export function useSaveActions(): SaveActions {
  return useContext(SaveActionsContext) ?? NOOP_ACTIONS;
}

/**
 * Client navigation that first persists pending edits (M-1). When something could not be saved
 * (e.g. an invalid field), the user is asked before leaving.
 */
export function useGuardedNavigation() {
  const router = useRouter();
  const { flush } = useSaveActions();
  return useCallback(
    async (href: string): Promise<boolean> => {
      const ok = await flush();
      if (!ok && !window.confirm('Perubahan terakhir belum tersimpan (periksa isian yang ditandai). Tetap tinggalkan halaman ini?')) {
        return false;
      }
      router.push(href);
      return true;
    },
    [flush, router],
  );
}

/** onClick for plain left-clicks on links; modified clicks (new tab) keep the browser default. */
export function guardLinkClick(e: React.MouseEvent<HTMLAnchorElement>, href: string, go: (href: string) => Promise<boolean>) {
  if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
  e.preventDefault();
  void go(href);
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
