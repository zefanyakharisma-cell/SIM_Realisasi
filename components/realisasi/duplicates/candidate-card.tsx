import Link from 'next/link';
import { StatusBadge } from '@/components/realisasi/status-badge';
import { DateRange } from '@/components/realisasi/list/activity-table';
import { CandidateActions } from '@/components/realisasi/duplicates/candidate-actions';
import { DUP_STATUS_LABEL } from '@/lib/realisasi/status';
import { formatDateTime, formatPct } from '@/lib/realisasi/format';
import { cn } from '@/lib/utils';
import type { DuplicateCandidateRow } from '@/lib/realisasi/types';

type SideKey = 'a' | 'b';

function SidePanel({ c, s, label }: { c: DuplicateCandidateRow; s: SideKey; label: string }) {
  const v = (k: string) => (c as unknown as Record<string, unknown>)[`${s}_${k}`];
  const id = v('id') as string;
  const docs = (v('documents') as string[] | null) ?? [];
  return (
    <section aria-label={label} className="min-w-0 space-y-2 rounded-md border bg-background p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <Link href={`/realisasi/kegiatan/${id}`} className="font-mono text-xs underline underline-offset-4">
          {v('code') as string}
        </Link>
        <StatusBadge status={v('status') as DuplicateCandidateRow['a_status']} />
      </div>
      <h3 className="font-medium leading-snug">{v('name') as string}</h3>
      <dl className="grid grid-cols-[auto,1fr] gap-x-3 gap-y-1 text-sm">
        <dt className="text-muted-foreground">Unit</dt>
        <dd>{v('unit_name') as string}</dd>
        <dt className="text-muted-foreground">Tanggal</dt>
        <dd>
          <DateRange start={v('start_date') as string} end={v('end_date') as string} />
        </dd>
        <dt className="text-muted-foreground">Kerja sama</dt>
        <dd className="break-words">{docs.length ? docs.join(', ') : '–'}</dd>
        <dt className="text-muted-foreground">Peserta</dt>
        <dd>{v('participants') as number} orang</dd>
      </dl>
    </section>
  );
}

/** Design §3.6: two activities side by side + similarity score + actions. */
export function CandidateCard({ c, canManage, canUnlink }: { c: DuplicateCandidateRow; canManage: boolean; canUnlink: boolean }) {
  const scorePct = Math.round(c.score * 100);
  return (
    <article className="space-y-3 rounded-lg border bg-card p-4" data-testid="dup-card" aria-label={`Kandidat duplikat ${c.a_code} dan ${c.b_code}`}>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-sm">
          <span
            className={cn(
              'mr-2 inline-flex items-center rounded-full border px-2 py-0.5 text-xs font-semibold',
              scorePct >= 80 ? 'border-purple-600 text-purple-800 dark:text-purple-300' : 'border-purple-400 text-purple-700 dark:text-purple-300',
            )}
          >
            Kemiripan nama {formatPct(c.score * 100)}
          </span>
          <span className="text-muted-foreground">Status: {DUP_STATUS_LABEL[c.status]}</span>
        </p>
        {c.resolved_at ? (
          <p className="text-xs text-muted-foreground">
            Diselesaikan {c.resolved_by_name ? `oleh ${c.resolved_by_name} ` : ''}pada {formatDateTime(c.resolved_at)}
          </p>
        ) : null}
      </div>
      <div className="grid gap-3 md:grid-cols-2">
        <SidePanel c={c} s="a" label={`Kegiatan A ${c.a_code}`} />
        <SidePanel c={c} s="b" label={`Kegiatan B ${c.b_code}`} />
      </div>
      <CandidateActions
        candidateId={c.id}
        status={c.status}
        a={{ id: c.a_id, code: c.a_code }}
        b={{ id: c.b_id, code: c.b_code }}
        canManage={canManage}
        canUnlink={canUnlink}
      />
    </article>
  );
}
