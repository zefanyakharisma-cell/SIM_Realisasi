'use client';
/**
 * Duplicate-student conflicts (Revisi V.1 rule 2.1): one NRP claimed by two units' kegiatan with
 * overlapping dates. Mobility compares both kegiatan (incl. their mobility PDF) and keeps the student on
 * one of them; the other kegiatan stops counting that student. The same unit claiming a student in two
 * kegiatan is never a conflict (rule 2.2).
 */
import { useId, useState } from 'react';
import Link from 'next/link';
import { Check, FileText } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { ActionDialog, NoteField } from '@/components/realisasi/verify/action-dialog';
import { resolveConflict } from '@/lib/realisasi/actions/verification';
import { formatDate, formatDateTime } from '@/lib/realisasi/format';
import { CONFLICT_STATUS_LABEL, CONFLICT_STATUS_TONE, DIRECTION_LABEL } from '@/lib/realisasi/status';
import type { ConflictRow, ConflictSide } from '@/lib/realisasi/types';
import { cn } from '@/lib/utils';

export interface ConflictListProps {
  conflicts: ConflictRow[];
  canResolve: boolean;
  /** Highlights the side belonging to this activity (activity detail page). */
  currentActivityId?: string;
}

function SideCard({
  conflict,
  side,
  canResolve,
  current,
}: {
  conflict: ConflictRow;
  side: ConflictSide;
  canResolve: boolean;
  current: boolean;
}) {
  const uid = useId();
  const [note, setNote] = useState('');
  const kept = conflict.kept_activity_id === side.id;
  const lost = conflict.status === 'resolved' && !kept;
  return (
    <div
      className={cn(
        'flex min-w-0 flex-col gap-2 rounded-md border p-3 text-sm',
        kept && 'border-success bg-success-subtle',
        lost && 'opacity-70',
        current && 'ring-2 ring-primary/40',
      )}
      data-testid="conflict-side"
    >
      <div className="flex flex-wrap items-center gap-2">
        <Link href={`/realisasi/kegiatan/${side.id}`} className="font-mono text-xs font-medium text-primary underline underline-offset-4">
          {side.code}
        </Link>
        {current ? <Badge variant="outline">Kegiatan ini</Badge> : null}
        {kept ? (
          <Badge variant="green">
            <Check className="h-3 w-3" aria-hidden /> Dihitung di sini
          </Badge>
        ) : lost ? (
          <Badge variant="neutral">Tidak dihitung</Badge>
        ) : null}
      </div>
      <p className="font-medium">{side.name}</p>
      <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-0.5 text-xs">
        <dt className="text-muted-foreground">Unit</dt>
        <dd>{side.unit_name}</dd>
        <dt className="text-muted-foreground">Jenis</dt>
        <dd>
          {side.agenda_name ?? '–'} · {DIRECTION_LABEL[side.direction]}
        </dd>
        <dt className="text-muted-foreground">Tanggal</dt>
        <dd>
          {formatDate(side.start_date)} – {formatDate(side.end_date)}
        </dd>
      </dl>
      <div className="mt-auto flex flex-wrap items-center gap-2 pt-1">
        {side.bundle ? (
          <a
            href={side.bundle.href}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-1 text-xs font-medium text-primary underline underline-offset-4"
          >
            <FileText className="h-3.5 w-3.5" aria-hidden /> PDF transkrip &amp; dokumentasi
          </a>
        ) : (
          <span className="text-xs text-muted-foreground">PDF mobilitas belum diunggah</span>
        )}
        {canResolve && !kept ? (
          <ActionDialog
            triggerLabel={conflict.status === 'open' ? 'Pilih kegiatan ini' : 'Ubah: pilih kegiatan ini'}
            triggerVariant={conflict.status === 'open' ? 'default' : 'outline'}
            triggerTestId="conflict-keep"
            triggerClassName="ml-auto"
            title={`Hitung ${conflict.student_name} di ${side.code}?`}
            description={`Mahasiswa ${conflict.nrp} hanya dihitung pada ${side.code} (${side.unit_name}). Kegiatan lainnya tetap tercatat, tetapi tidak menghitung mahasiswa ini.`}
            confirmLabel="Pilih kegiatan ini"
            onOpenChange={(o) => o && setNote('')}
            action={() => resolveConflict(conflict.id, side.id, note.trim() || null)}
            successMessage={(r) =>
              `${conflict.nrp} dihitung pada ${side.code}.${r.open_remaining > 0 ? ` ${r.open_remaining} duplikat lain masih terbuka.` : ''}`
            }
          >
            {({ pending }) => <NoteField id={`${uid}-note`} label="Catatan" value={note} onChange={setNote} disabled={pending} />}
          </ActionDialog>
        ) : null}
      </div>
    </div>
  );
}

export function ConflictList({ conflicts, canResolve, currentActivityId }: ConflictListProps) {
  if (conflicts.length === 0) return <p className="text-sm text-muted-foreground">Tidak ada duplikat mahasiswa.</p>;
  return (
    <ul className="space-y-3" data-testid="conflict-list">
      {conflicts.map((c) => (
        <li key={c.id} className="rounded-lg border p-3" data-testid="conflict-row">
          <div className="mb-3 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm">
            <span className="font-mono text-xs">{c.nrp}</span>
            <span className="font-medium">{c.student_name}</span>
            {c.prodi_name ? <span className="text-muted-foreground">{c.prodi_name}</span> : null}
            <Badge variant={CONFLICT_STATUS_TONE[c.status]}>{CONFLICT_STATUS_LABEL[c.status]}</Badge>
            {c.status === 'resolved' && c.resolved_at ? (
              <span className="text-xs text-muted-foreground">
                oleh {c.resolved_by_name ?? '–'} · {formatDateTime(c.resolved_at)}
                {c.note ? ` · “${c.note}”` : ''}
              </span>
            ) : null}
          </div>
          <div className="grid gap-3 md:grid-cols-2">
            <SideCard conflict={c} side={c.a} canResolve={canResolve} current={c.a.id === currentActivityId} />
            <SideCard conflict={c} side={c.b} canResolve={canResolve} current={c.b.id === currentActivityId} />
          </div>
        </li>
      ))}
    </ul>
  );
}
