import { describe, expect, it } from 'vitest';
import { createDraftSaver, type SaveOutcome } from './save-queue';

/** A save whose completion the test controls. */
function controllable() {
  const calls: Array<{ payload: string; resolve: (ok: boolean) => void }> = [];
  const run = (payload: string) =>
    new Promise<{ ok: boolean; payload: string }>((resolve) => {
      calls.push({ payload, resolve: (ok) => resolve({ ok, payload }) });
    });
  return { calls, run };
}

const tick = () => new Promise((r) => setTimeout(r, 0));

describe('createDraftSaver', () => {
  it('H-1: an edit made while a save is in flight is not reported as saved, and is saved next', async () => {
    const { calls, run } = controllable();
    const results: Array<SaveOutcome<{ ok: boolean; payload: string }>> = [];
    const saver = createDraftSaver({ run, isOk: (r) => r.ok, onResult: (o) => results.push(o) });
    let state = 'A';

    saver.markEdited();
    const a = saver.save(() => state);
    await tick();
    expect(calls.map((c) => c.payload)).toEqual(['A']);

    // User edits while A is in flight; the debounce fires and requests another save.
    state = 'AB';
    saver.markEdited();
    const b = saver.save(() => state);
    await tick();
    expect(calls).toHaveLength(1); // serialized: B waits, it is not dropped

    calls[0]!.resolve(true);
    const outA = await a;
    expect(outA?.upToDate).toBe(false); // must NOT show "Tersimpan"
    expect(saver.dirty).toBe(true);
    await tick();
    expect(calls.map((c) => c.payload)).toEqual(['A', 'AB']); // latest state is saved

    calls[1]!.resolve(true);
    const outB = await b;
    expect(outB?.upToDate).toBe(true);
    expect(saver.dirty).toBe(false);
    expect(results.map((r) => r.upToDate)).toEqual([false, true]);
  });

  it('coalesces queued requests and reads the payload when the save starts', async () => {
    const { calls, run } = controllable();
    const saver = createDraftSaver({ run, isOk: (r) => r.ok });
    let state = '1';
    saver.markEdited();
    const first = saver.save(() => state);
    await tick();
    state = '2';
    saver.markEdited();
    const second = saver.save(() => `stale:${state}`);
    state = '3';
    saver.markEdited();
    const third = saver.save(() => state); // replaces the queued getter
    calls[0]!.resolve(true);
    await first;
    await tick();
    expect(calls.map((c) => c.payload)).toEqual(['1', '3']);
    calls[1]!.resolve(true);
    const [o2, o3] = await Promise.all([second, third]);
    expect(o2).toBe(o3); // both waiters get the single coalesced run
    expect(o3?.upToDate).toBe(true);
  });

  it('a manual save requested during an autosave runs after it instead of being ignored', async () => {
    const { calls, run } = controllable();
    const saver = createDraftSaver({ run, isOk: (r) => r.ok });
    saver.markEdited();
    void saver.save(() => 'auto');
    await tick();
    const manual = saver.save(() => 'manual');
    calls[0]!.resolve(true);
    await tick();
    expect(calls.map((c) => c.payload)).toEqual(['auto', 'manual']);
    calls[1]!.resolve(true);
    expect((await manual)?.result.payload).toBe('manual');
  });

  it('a failed save keeps the editor dirty; null payloads skip the run', async () => {
    const { calls, run } = controllable();
    const saver = createDraftSaver({ run, isOk: (r) => r.ok });
    saver.markEdited();
    const p = saver.save(() => 'x');
    await tick();
    calls[0]!.resolve(false);
    expect((await p)?.upToDate).toBe(false);
    expect(saver.dirty).toBe(true);
    expect(await saver.save(() => null)).toBeNull();
    expect(calls).toHaveLength(1);
  });

  it('idle() waits for running and queued saves; busy reflects the queue', async () => {
    const { calls, run } = controllable();
    const saver = createDraftSaver({ run, isOk: (r) => r.ok });
    saver.markEdited();
    void saver.save(() => 'a');
    expect(saver.busy).toBe(true);
    await tick(); // 'a' is running now
    void saver.save(() => 'b');
    let idle = false;
    void saver.idle().then(() => (idle = true));
    await tick();
    calls[0]!.resolve(true);
    await tick();
    expect(idle).toBe(false);
    calls[1]!.resolve(true);
    await tick();
    await tick();
    expect(idle).toBe(true);
    expect(saver.busy).toBe(false);
    expect(saver.dirty).toBe(false);
  });

  it('rejects waiters when the save throws and keeps working afterwards', async () => {
    let n = 0;
    const saver = createDraftSaver<string, boolean>({
      run: async () => {
        n++;
        if (n === 1) throw new Error('network');
        return true;
      },
      isOk: (r) => r,
    });
    saver.markEdited();
    await expect(saver.save(() => 'a')).rejects.toThrow('network');
    expect(saver.busy).toBe(false);
    expect((await saver.save(() => 'b'))?.upToDate).toBe(true);
  });
});
