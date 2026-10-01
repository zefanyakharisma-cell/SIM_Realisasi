'use client';

import { useId, useState, useTransition } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { BellRing, Check } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { toast } from '@/components/ui/toaster';
import { ActionDialog, NoteField } from '@/components/realisasi/verify/action-dialog';
import { dismissKnownActivity, matchKnownActivity, nudgeKnownActivity, unmatchKnownActivity } from '@/lib/realisasi/actions/known';
import { ACTIVITY_STATUS_LABEL } from '@/lib/realisasi/status';
import { formatDate, formatDateTime, formatPct } from '@/lib/realisasi/format';
import type { KnownActivityRow, KnownSuggestion } from '@/lib/realisasi/types';

/** Suggested SIM matches (score) with "Cocokkan" (R-52: always confirmed by a person). */
export function KnownSuggestions({ row, suggestions, canManage }: { row: KnownActivityRow; suggestions: KnownSuggestion[]; canManage: boolean }) {
  if (suggestions.length === 0) return <p className="text-xs text-muted-foreground">Belum ada saran kecocokan.</p>;
  return (
    <ul className="space-y-1.5" aria-label={`Saran kecocokan untuk ${row.title}`}>
      {suggestions.map((s) => (
        <li key={s.activity_id} className="flex flex-wrap items-center gap-2 text-xs" data-testid="known-suggestion">
          <span className="rounded-full border border-blue-500 px-1.5 py-0.5 font-semibold text-blue-800 dark:text-blue-300">
            {formatPct(s.score * 100)}
          </span>
          <Link href={`/realisasi/kegiatan/${s.activity_id}`} className="font-mono underline underline-offset-4">
            {s.code}
          </Link>
          <span className="min-w-0 max-w-[220px] truncate" title={`${s.name} · ${s.unit_names.join(', ')} · ${formatDate(s.start_date)} · ${ACTIVITY_STATUS_LABEL[s.status]}`}>
            {s.name}
          </span>
          {canManage ? (
            <ActionDialog
              triggerVariant="outline"
              triggerTestId="known-match"
              triggerLabel={
                <>
                  Cocokkan<span className="sr-only"> dengan {s.code}</span>
                </>
              }
              title="Cocokkan dengan kegiatan SIM?"
              description={`"${row.title}" (${formatDate(row.activity_date)}) akan ditandai Cocok dengan ${s.code} — ${s.name} (${s.unit_names.join(', ')}, ${formatDate(s.start_date)}).`}
              confirmLabel="Cocokkan"
              action={() => matchKnownActivity(row.id, s.activity_id)}
              successMessage={`Entri dicocokkan dengan ${s.code}.`}
            />
          ) : null}
        </li>
      ))}
    </ul>
  );
}

/** Ingatkan unit / Abaikan / Batalkan cocok for one register row. */
export function KnownRowActions({ row, resendDays }: { row: KnownActivityRow; resendDays: number }) {
  const uid = useId();
  const router = useRouter();
  const [note, setNote] = useState('');
  const [pending, startTransition] = useTransition();

  function nudge() {
    startTransition(async () => {
      const res = await nudgeKnownActivity(row.id);
      if (res.ok) {
        toast.success(`Pengingat dikirim ke ${row.unit_name ?? 'unit'}.`);
        router.refresh();
      } else toast.error(res.message);
    });
  }

  function unmatch() {
    startTransition(async () => {
      const res = await unmatchKnownActivity(row.id);
      if (res.ok) {
        toast.success('Kecocokan dibatalkan.');
        router.refresh();
      } else toast.error(res.message);
    });
  }

  if (row.status === 'matched') {
    return (
      <Button type="button" variant="ghost" size="sm" onClick={unmatch} loading={pending}>
        Batalkan cocok
      </Button>
    );
  }
  if (row.status !== 'unmatched') return null;

  const resendAt = row.nudged_at ? new Date(new Date(row.nudged_at).getTime() + resendDays * 86_400_000).toISOString() : null;
  const nudgeHintId = `${uid}-nudge-hint`;
  const nudgeHint = !row.unit_id
    ? 'Unit belum ditentukan.'
    : row.nudged_at
      ? `Diingatkan ${formatDateTime(row.nudged_at)}${row.can_nudge ? '' : ` · kirim ulang mulai ${formatDate(resendAt)}`}`
      : null;

  return (
    <div className="flex flex-col items-start gap-1">
      <div className="flex flex-wrap gap-1.5">
        <Button
          type="button"
          variant="outline"
          size="sm"
          onClick={nudge}
          loading={pending}
          disabled={!row.can_nudge}
          aria-describedby={nudgeHint ? nudgeHintId : undefined}
          data-testid="known-nudge"
        >
          {pending ? null : <BellRing aria-hidden="true" />}
          Ingatkan unit
        </Button>
        <ActionDialog
          triggerVariant="ghost"
          triggerTestId="known-dismiss"
          triggerLabel="Abaikan"
          title="Abaikan entri ini?"
          description="Entri yang diabaikan tidak dihitung sebagai kesenjangan KPI 1.19.S8 (R-50)."
          confirmLabel="Abaikan"
          onOpenChange={(o) => o && setNote('')}
          validate={() => (note.trim() ? {} : { note: 'Catatan wajib diisi.' })}
          action={() => dismissKnownActivity(row.id, note.trim())}
          successMessage="Entri diabaikan."
        >
          {({ errors, pending: p }) => (
            <NoteField id={`${uid}-dismiss`} label="Alasan" required value={note} onChange={setNote} error={errors.note} disabled={p} />
          )}
        </ActionDialog>
      </div>
      {nudgeHint ? (
        <p id={nudgeHintId} className="text-xs text-muted-foreground">
          {row.nudged_at ? <Check className="mr-0.5 inline h-3 w-3" aria-hidden="true" /> : null}
          {nudgeHint}
        </p>
      ) : null}
    </div>
  );
}
