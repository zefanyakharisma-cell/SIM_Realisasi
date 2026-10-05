'use client';
/**
 * Riwayat tab: merged activity log with a kind filter; update/revision entries show field diffs
 * (Design §3.4, R-30/R-31).
 */
import { useMemo, useState } from 'react';
import { Snowflake } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { diffFieldLabel } from '@/components/realisasi/activity/labels';
import { formatDateTime } from '@/lib/realisasi/format';
import { LOG_KIND_LABEL, TRACK_LABEL, logActionLabel } from '@/lib/realisasi/status';
import type { ActivityLogEntry, LogKind } from '@/lib/realisasi/types';

const KINDS: LogKind[] = ['verification', 'revision', 'update', 'system'];
const KIND_TONE: Record<LogKind, 'blue' | 'amber' | 'purple' | 'neutral'> = {
  verification: 'blue',
  revision: 'amber',
  update: 'purple',
  system: 'neutral',
};

function show(v: unknown): string {
  if (v === null || v === undefined || v === '') return '–';
  if (Array.isArray(v)) {
    if (v.length === 0) return '–';
    return v.map((x) => (typeof x === 'object' && x !== null ? summarizeObject(x as Record<string, unknown>) : String(x))).join(', ');
  }
  if (typeof v === 'object') return summarizeObject(v as Record<string, unknown>);
  if (typeof v === 'boolean') return v ? 'Ya' : 'Tidak';
  return String(v);
}

function summarizeObject(o: Record<string, unknown>): string {
  if (typeof o.full_name === 'string') return `${o.full_name}${o.institution ? ` (${String(o.institution)})` : ''}`;
  return Object.entries(o)
    .map(([k, v]) => `${diffFieldLabel(k)}: ${show(v)}`)
    .join('; ');
}

function isAddedRemoved(v: unknown): v is { added?: unknown; removed?: unknown } {
  return typeof v === 'object' && v !== null && !Array.isArray(v) && ('added' in v || 'removed' in v);
}

/**
 * `added`/`removed` are id lists — or plain counts when the caller may not see participant
 * identifiers (WP-DB amendment 26: `{"students":{"added":n,"removed":m}}`).
 */
function rowChange(v: unknown): { text: string; any: boolean } {
  if (typeof v === 'number') return { text: `${v} baris`, any: v > 0 };
  if (Array.isArray(v)) return { text: v.map(String).join(', '), any: v.length > 0 };
  return { text: '', any: false };
}

export function DiffView({ diff }: { diff: Record<string, unknown> }) {
  const entries = Object.entries(diff);
  if (entries.length === 0) return null;
  return (
    <dl className="mt-2 space-y-1 rounded-md bg-muted/40 p-2 text-xs">
      {entries.map(([field, value]) => (
        <div key={field} className="grid gap-1 sm:grid-cols-[10rem_1fr]">
          <dt className="font-medium text-muted-foreground">{diffFieldLabel(field)}</dt>
          <dd className="break-words">
            {Array.isArray(value) && value.length === 2 ? (
              <>
                <del className="text-danger-fg">{show(value[0])}</del>
                <span aria-hidden> → </span>
                <span className="sr-only"> diubah menjadi </span>
                <ins className="text-success-fg no-underline">{show(value[1])}</ins>
              </>
            ) : isAddedRemoved(value) ? (
              (() => {
                const added = rowChange(value.added);
                const removed = rowChange(value.removed);
                return (
                  <>
                    {added.any && <span className="text-success-fg">Ditambah: {added.text}. </span>}
                    {removed.any && <span className="text-danger-fg">Dihapus: {removed.text}.</span>}
                    {!added.any && !removed.any && <span className="text-muted-foreground">Tidak ada perubahan baris.</span>}
                  </>
                );
              })()
            ) : field === 'row_notes' && typeof value === 'number' ? (
              `${value} catatan baris`
            ) : (
              show(value)
            )}
          </dd>
        </div>
      ))}
    </dl>
  );
}

export function LogList({ log }: { log: ActivityLogEntry[] }) {
  const [kind, setKind] = useState<LogKind | 'all'>('all');
  const counts = useMemo(() => {
    const c: Record<string, number> = {};
    for (const e of log) c[e.kind] = (c[e.kind] ?? 0) + 1;
    return c;
  }, [log]);
  const rows = useMemo(
    () => [...log].filter((e) => kind === 'all' || e.kind === kind).sort((a, b) => b.created_at.localeCompare(a.created_at)),
    [log, kind],
  );

  return (
    <div className="space-y-4" data-testid="activity-log">
      <fieldset>
        <legend className="sr-only">Filter jenis riwayat</legend>
        <div className="flex flex-wrap gap-2">
          {(['all', ...KINDS] as const).map((k) => (
            <button
              key={k}
              type="button"
              aria-pressed={kind === k}
              onClick={() => setKind(k)}
              className="rounded-full border px-3 py-1 text-xs font-medium transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring aria-pressed:border-primary aria-pressed:bg-primary aria-pressed:text-primary-foreground"
            >
              {k === 'all' ? 'Semua' : LOG_KIND_LABEL[k]} ({k === 'all' ? log.length : counts[k] ?? 0})
            </button>
          ))}
        </div>
      </fieldset>

      {rows.length === 0 ? (
        <p className="text-sm text-muted-foreground">Belum ada riwayat untuk filter ini.</p>
      ) : (
        <ol className="relative space-y-4 border-l pl-5">
          {rows.map((e) => (
            <li key={e.id} className="relative">
              <span className="absolute -left-[1.4rem] top-1.5 h-2.5 w-2.5 rounded-full border-2 border-background bg-muted-foreground" aria-hidden />
              <div className="flex flex-wrap items-center gap-2 text-sm">
                <Badge variant={KIND_TONE[e.kind]}>{LOG_KIND_LABEL[e.kind]}</Badge>
                {e.track && <Badge appearance="outline" variant="neutral">{TRACK_LABEL[e.track]}</Badge>}
                <span className="font-medium">{logActionLabel(e.action)}</span>
                <span className="text-muted-foreground">
                  oleh {e.actor_name ?? 'Sistem'} · <time dateTime={e.created_at}>{formatDateTime(e.created_at)}</time>
                </span>
                {e.in_frozen_period && (
                  <Badge variant="blue" title="Perubahan pada periode yang sudah dibekukan (Perubahan Pasca-Beku)">
                    <Snowflake className="h-3 w-3" aria-hidden />
                    Pasca-beku
                  </Badge>
                )}
              </div>
              {e.note && <p className="mt-1 whitespace-pre-line text-sm">“{e.note}”</p>}
              {e.diff && <DiffView diff={e.diff} />}
            </li>
          ))}
        </ol>
      )}
    </div>
  );
}
