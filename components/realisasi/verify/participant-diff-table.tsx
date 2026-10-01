'use client';

import { useMemo, useState } from 'react';
import { FileText, Minus, Pencil, Plus } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import { cn } from '@/lib/utils';
import { diffParticipantVersions, summarizeDiff, type DiffEntry, type RowChange } from '@/lib/realisasi/participant-diff';
import { PSET_STATUS_LABEL, SECTION_LABEL } from '@/lib/realisasi/status';
import type { ParticipantStaffRow, ParticipantStudentRow, ParticipantVersion } from '@/lib/realisasi/types';

const CHANGE_LABEL: Record<RowChange, string> = {
  added: 'Ditambahkan',
  removed: 'Dihapus',
  changed: 'Diubah',
  same: 'Tetap',
};

const ROW_CLASS: Record<RowChange, string> = {
  added: 'bg-green-50 dark:bg-green-950/40',
  removed: 'bg-red-50 text-red-900 line-through decoration-red-600 dark:bg-red-950/40 dark:text-red-200',
  changed: '',
  same: '',
};

const CELL_CHANGED = 'bg-amber-100 font-medium dark:bg-amber-900/50';

function ChangeMarker({ change }: { change: RowChange }) {
  if (change === 'same') return <span className="sr-only">{CHANGE_LABEL.same}</span>;
  const Icon = change === 'added' ? Plus : change === 'removed' ? Minus : Pencil;
  const tone =
    change === 'added'
      ? 'border-green-600 text-green-800 dark:text-green-300'
      : change === 'removed'
        ? 'border-red-600 text-red-800 dark:text-red-300'
        : 'border-amber-600 text-amber-800 dark:text-amber-300';
  return (
    <span
      className={cn('inline-flex items-center gap-1 rounded-full border px-1.5 py-0.5 text-xs font-medium no-underline', tone)}
      style={{ textDecoration: 'none' }}
    >
      <Icon className="h-3 w-3" aria-hidden="true" />
      {CHANGE_LABEL[change]}
    </span>
  );
}

function Cell({
  entry,
  field,
  children,
  className,
}: {
  entry: DiffEntry<ParticipantStudentRow> | DiffEntry<ParticipantStaffRow>;
  field: string;
  children: React.ReactNode;
  className?: string;
}) {
  const changed = entry.change === 'changed' && entry.changedFields.includes(field);
  const before = entry.before as Record<string, unknown> | undefined;
  const prevValue = changed && before ? before[field] : undefined;
  return (
    <td className={cn('px-3 py-2 align-top', changed && CELL_CHANGED, className)}>
      {children}
      {changed ? (
        <span className="mt-0.5 block text-xs font-normal text-muted-foreground">
          <span className="sr-only">Nilai sebelumnya: </span>
          <span aria-hidden="true">sebelumnya: </span>
          <s>{prevValue === null || prevValue === undefined || prevValue === '' ? '–' : String(prevValue)}</s>
        </span>
      ) : null}
    </td>
  );
}

export interface ParticipantDiffTableProps {
  version: ParticipantVersion;
  previous: ParticipantVersion | null;
  /** Optional caption override (defaults to "Peserta vN dibandingkan vM"). */
  caption?: string;
}

/**
 * Participant set of `version` compared with `previous` (Design §3.5): added rows green, removed rows
 * red strike-through, changed cells highlighted with the previous value. Change type is always given
 * as text too (never colour alone). Inbound transcripts open in a side sheet.
 */
export function ParticipantDiffTable({ version, previous, caption }: ParticipantDiffTableProps) {
  const diff = useMemo(() => diffParticipantVersions(previous, version), [previous, version]);
  const summary = summarizeDiff(diff);
  const [transcript, setTranscript] = useState<{ href: string; nrp: string; name: string } | null>(null);

  const internal = diff.students.filter((e) => (e.after ?? e.before)?.section === 'internal');
  const inbound = diff.students.filter((e) => (e.after ?? e.before)?.section === 'inbound');
  const compare = previous !== null;
  const captionText =
    caption ??
    (compare
      ? `Peserta v${version.version} (${PSET_STATUS_LABEL[version.status]}) dibandingkan dengan v${previous.version}`
      : `Peserta v${version.version} (${PSET_STATUS_LABEL[version.status]}) — versi pertama`);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm">
        <p className="font-medium">{captionText}</p>
        {compare ? (
          <p className="text-muted-foreground" aria-live="polite">
            {summary.added} ditambahkan · {summary.removed} dihapus · {summary.changed} diubah
          </p>
        ) : null}
      </div>

      {(['internal', 'inbound'] as const).map((section) => {
        const entries = section === 'internal' ? internal : inbound;
        if (entries.length === 0) return null;
        return (
          <div key={section} className="overflow-x-auto rounded-md border">
            <table className="w-full min-w-[640px] text-sm">
              <caption className="px-3 py-2 text-left font-medium">
                {SECTION_LABEL[section]} ({entries.filter((e) => e.change !== 'removed').length})
              </caption>
              <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  {compare ? <th scope="col" className="px-3 py-2">Perubahan</th> : null}
                  <th scope="col" className="px-3 py-2">NRP</th>
                  <th scope="col" className="px-3 py-2">Nama</th>
                  {section === 'internal' ? (
                    <>
                      <th scope="col" className="px-3 py-2">Fakultas</th>
                      <th scope="col" className="px-3 py-2">Prodi</th>
                    </>
                  ) : (
                    <>
                      <th scope="col" className="px-3 py-2">Institusi asal</th>
                      <th scope="col" className="px-3 py-2">No. mahasiswa asal</th>
                      <th scope="col" className="px-3 py-2">Negara</th>
                      <th scope="col" className="px-3 py-2">Transkrip</th>
                    </>
                  )}
                </tr>
              </thead>
              <tbody>
                {entries.map((e) => {
                  const r = (e.after ?? e.before)!;
                  return (
                    <tr key={e.key} className={cn('border-t', ROW_CLASS[e.change])}>
                      {compare ? (
                        <td className="px-3 py-2 align-top">
                          <ChangeMarker change={e.change} />
                        </td>
                      ) : null}
                      <td className="px-3 py-2 align-top font-mono text-xs">
                        {r.nrp}
                        {r.registry_status !== 'active' ? (
                          <span className="ml-1 rounded border border-amber-500 px-1 text-[10px] uppercase text-amber-800 no-underline dark:text-amber-300">
                            {r.registry_status === 'graduated' ? 'Lulus' : 'Tidak aktif'}
                          </span>
                        ) : null}
                        {e.before?.row_note ? (
                          <span className="mt-1 block font-sans text-xs text-amber-800 no-underline dark:text-amber-300">
                            Catatan v{previous?.version}: {e.before.row_note}
                          </span>
                        ) : null}
                      </td>
                      <Cell entry={e} field="full_name">{r.full_name}</Cell>
                      {section === 'internal' ? (
                        <>
                          <Cell entry={e} field="faculty_name">{r.faculty_name ?? '–'}</Cell>
                          <Cell entry={e} field="prodi_name">{r.prodi_name ?? '–'}</Cell>
                        </>
                      ) : (
                        <>
                          <Cell entry={e} field="home_institution">{r.home_institution ?? '–'}</Cell>
                          <Cell entry={e} field="home_student_number">{r.home_student_number ?? '–'}</Cell>
                          <Cell entry={e} field="home_country_code">{r.home_country_code ?? '–'}</Cell>
                          <Cell entry={e} field="transcript_path">
                            {r.transcript_href && e.change !== 'removed' ? (
                              <Button
                                type="button"
                                variant="outline"
                                size="sm"
                                onClick={() => setTranscript({ href: r.transcript_href!, nrp: r.nrp, name: r.full_name })}
                              >
                                <FileText className="mr-1 h-4 w-4" aria-hidden="true" />
                                Lihat transkrip<span className="sr-only"> {r.full_name}</span>
                              </Button>
                            ) : r.transcript_path ? (
                              'Ada'
                            ) : (
                              <span className="text-red-700 dark:text-red-300">Belum ada</span>
                            )}
                          </Cell>
                        </>
                      )}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        );
      })}

      {diff.staff.length > 0 ? (
        <div className="overflow-x-auto rounded-md border">
          <table className="w-full min-w-[480px] text-sm">
            <caption className="px-3 py-2 text-left font-medium">
              Pegawai PETRA ({diff.staff.filter((e) => e.change !== 'removed').length})
            </caption>
            <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
              <tr>
                {compare ? <th scope="col" className="px-3 py-2">Perubahan</th> : null}
                <th scope="col" className="px-3 py-2">ID Pegawai</th>
                <th scope="col" className="px-3 py-2">Nama</th>
                <th scope="col" className="px-3 py-2">Unit</th>
              </tr>
            </thead>
            <tbody>
              {diff.staff.map((e) => {
                const r = (e.after ?? e.before)!;
                return (
                  <tr key={e.key} className={cn('border-t', ROW_CLASS[e.change])}>
                    {compare ? (
                      <td className="px-3 py-2 align-top">
                        <ChangeMarker change={e.change} />
                      </td>
                    ) : null}
                    <td className="px-3 py-2 align-top font-mono text-xs">
                      {r.employee_id}
                      {e.before?.row_note ? (
                        <span className="mt-1 block font-sans text-xs text-amber-800 dark:text-amber-300">
                          Catatan v{previous?.version}: {e.before.row_note}
                        </span>
                      ) : null}
                    </td>
                    <Cell entry={e} field="full_name">{r.full_name}</Cell>
                    <Cell entry={e} field="unit_name">{r.unit_name ?? '–'}</Cell>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      ) : null}

      {diff.students.length === 0 && diff.staff.length === 0 ? (
        <p className="text-sm text-muted-foreground">Versi ini tidak memiliki peserta.</p>
      ) : null}

      <Sheet open={transcript !== null} onOpenChange={(open) => !open && setTranscript(null)}>
        <SheetContent side="right" className="flex w-full flex-col gap-4 sm:max-w-2xl">
          <SheetHeader>
            <SheetTitle>Transkrip {transcript?.name}</SheetTitle>
            <SheetDescription>NRP {transcript?.nrp} · versi peserta v{version.version}</SheetDescription>
          </SheetHeader>
          {transcript ? (
            <>
              <iframe
                src={transcript.href}
                title={`Transkrip ${transcript.name}`}
                className="min-h-[60vh] w-full flex-1 rounded-md border"
              />
              <a
                href={transcript.href}
                target="_blank"
                rel="noopener noreferrer"
                className="text-sm font-medium text-primary underline underline-offset-4"
              >
                Buka transkrip di tab baru
              </a>
            </>
          ) : null}
        </SheetContent>
      </Sheet>
    </div>
  );
}
