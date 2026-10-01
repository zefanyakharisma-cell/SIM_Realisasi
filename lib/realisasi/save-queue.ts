/**
 * Serialized, coalescing draft saver used by the wizard editors (frontend review H-1/H-2).
 * Pure (no React) so the concurrency rules are unit-tested in `save-queue.test.ts`.
 *
 * Guarantees:
 * - **One save at a time.** A save requested while another is in flight is queued, never dropped.
 * - **Coalescing.** While a save is queued (not yet started), further requests replace its payload
 *   getter; every waiter receives the result of the single run that actually happens.
 * - **Latest state.** The payload getter runs when the save *starts*, so it reads the newest state
 *   (via refs), not the state captured when the save was requested.
 * - **Edit sequence.** Every edit bumps `editSeq`; a save only counts as "up to date" (clean, show
 *   "Tersimpan") when no edit happened between the snapshot and the response.
 */

export interface SaveOutcome<R> {
  result: R;
  /** The snapshot was taken at this edit sequence number. */
  seq: number;
  /** True when the save succeeded and no edit happened after its snapshot. */
  upToDate: boolean;
}

export interface DraftSaverOptions<P, R> {
  /** Performs the save (e.g. a server action). */
  run: (payload: P) => Promise<R>;
  /** Whether `run`'s result is a success. */
  isOk: (result: R) => boolean;
  /**
   * Called once per completed run (before the waiters resolve), after `busy` has been updated, so
   * `busy === false` here means no further save is queued.
   */
  onResult?: (outcome: SaveOutcome<R>) => void;
}

export interface DraftSaver<P, R> {
  /** Records a user edit. */
  markEdited(): void;
  /** Edits not yet covered by a successful save. */
  readonly dirty: boolean;
  /** A save is running or queued. */
  readonly busy: boolean;
  readonly editSeq: number;
  /**
   * Queues a save. `getPayload` runs when the save starts (latest state). Returning `null` skips
   * the run (e.g. invalid or blocked state) and resolves with `null`.
   */
  save(getPayload: () => P | null): Promise<SaveOutcome<R> | null>;
  /** Resolves once nothing is running or queued. */
  idle(): Promise<void>;
}

interface Waiter<R> {
  resolve: (v: SaveOutcome<R> | null) => void;
  reject: (e: unknown) => void;
}

interface Slot<P, R> {
  get: () => P | null;
  waiters: Waiter<R>[];
}

export function createDraftSaver<P, R>(opts: DraftSaverOptions<P, R>): DraftSaver<P, R> {
  let editSeq = 0;
  let savedSeq = 0;
  let tail: Promise<void> = Promise.resolve();
  let queued: Slot<P, R> | null = null;
  let active = 0;

  async function execute(slot: Slot<P, R>): Promise<void> {
    if (queued === slot) queued = null;
    active++;
    let outcome: SaveOutcome<R> | null = null;
    let failed = false;
    let error: unknown = null;
    try {
      const seq = editSeq;
      const payload = slot.get();
      if (payload !== null) {
        const result = await opts.run(payload);
        const ok = opts.isOk(result);
        if (ok && seq > savedSeq) savedSeq = seq;
        outcome = { result, seq, upToDate: ok && seq === editSeq };
      }
    } catch (e) {
      failed = true;
      error = e;
    } finally {
      active--;
    }
    if (failed) {
      for (const w of slot.waiters) w.reject(error);
      return;
    }
    if (outcome) opts.onResult?.(outcome);
    for (const w of slot.waiters) w.resolve(outcome);
  }

  return {
    markEdited() {
      editSeq++;
    },
    get dirty() {
      return savedSeq !== editSeq;
    },
    get busy() {
      return active > 0 || queued !== null;
    },
    get editSeq() {
      return editSeq;
    },
    save(getPayload) {
      return new Promise<SaveOutcome<R> | null>((resolve, reject) => {
        if (queued) {
          queued.get = getPayload;
          queued.waiters.push({ resolve, reject });
          return;
        }
        const slot: Slot<P, R> = { get: getPayload, waiters: [{ resolve, reject }] };
        queued = slot;
        tail = tail.then(() => execute(slot));
      });
    },
    async idle() {
      for (;;) {
        const t = tail;
        await t;
        if (t === tail && !queued) return;
      }
    },
  };
}
