'use client';

import { useId, useState } from 'react';
import { Check, RotateCcw } from 'lucide-react';
import { Input } from '@/components/ui/input';
import { ActionDialog, NoteField } from '@/components/realisasi/verify/action-dialog';
import { mobilityApprove, mobilityRequestRevision } from '@/lib/realisasi/actions/verification';
import { diffParticipantVersions, summarizeDiff } from '@/lib/realisasi/participant-diff';
import { ACTIVITY_STATUS_LABEL, SECTION_LABEL } from '@/lib/realisasi/status';
import type { ActivityPermissions, ParticipantVersion, RowNotePayload } from '@/lib/realisasi/types';

export interface MobilityActionsProps {
  activityId: string;
  code: string;
  /** The version under review (latest `pending`). */
  version: ParticipantVersion | null;
  /** Previous non-draft version, for the change summary. */
  previous: ParticipantVersion | null;
  permissions: ActivityPermissions;
}

type RowKey = `${'student' | 'staff'}:${string}`;

function countsText(v: ParticipantVersion): string {
  const internal = v.students.filter((s) => s.section === 'internal').length;
  const inbound = v.students.filter((s) => s.section === 'inbound').length;
  const parts = [];
  if (internal) parts.push(`${internal} mahasiswa PETRA`);
  if (inbound) parts.push(`${inbound} mahasiswa inbound`);
  if (v.staff.length) parts.push(`${v.staff.length} pegawai`);
  return parts.join(', ') || 'tanpa peserta';
}

/**
 * Mobilitas-track actions (Approve / Minta Revisi with per-row notes, R-27). Renders nothing
 * unless `permissions.can_mobility_verify`.
 */
export function MobilityActions({ activityId, code, version, previous, permissions }: MobilityActionsProps) {
  const uid = useId();
  const [approveNote, setApproveNote] = useState('');
  const [revisionNote, setRevisionNote] = useState('');
  const [rowNotes, setRowNotes] = useState<Record<RowKey, string>>({});

  if (!permissions.can_mobility_verify) return null;

  const summary = version && previous ? summarizeDiff(diffParticipantVersions(previous, version)) : null;
  const versionText = version ? `v${version.version} (${countsText(version)})` : 'versi yang diajukan';

  function setRowNote(key: RowKey, note: string) {
    setRowNotes((prev) => ({ ...prev, [key]: note }));
  }

  function collectRowNotes(): RowNotePayload[] {
    return (Object.entries(rowNotes) as Array<[RowKey, string]>)
      .filter(([, note]) => note.trim() !== '')
      .map(([key, note]) => {
        const [kind, ...rest] = key.split(':');
        return { kind: kind as RowNotePayload['kind'], id: rest.join(':'), note: note.trim() };
      });
  }

  const rows: Array<{ key: RowKey; label: string; group: string }> = version
    ? [
        ...version.students.map((s) => ({
          key: `student:${s.nrp}` as RowKey,
          label: `${s.nrp} — ${s.full_name}`,
          group: SECTION_LABEL[s.section],
        })),
        ...version.staff.map((s) => ({
          key: `staff:${s.employee_id}` as RowKey,
          label: `${s.employee_id} — ${s.full_name}`,
          group: 'Pegawai PETRA',
        })),
      ]
    : [];

  return (
    <div className="flex flex-wrap items-center gap-2" role="group" aria-label={`Verifikasi Mobilitas ${code}`}>
      <ActionDialog
        triggerLabel={
          <>
            <Check className="mr-1 h-4 w-4" aria-hidden="true" />
            Setujui peserta
          </>
        }
        triggerTestId="action-approve"
        title={`Setujui peserta ${code}?`}
        description={
          <>
            Data peserta {versionText} akan disetujui dan menjadi satu-satunya versi yang dihitung (R-21)
            {previous ? `; versi v${previous.version} tetap tersimpan sebagai riwayat` : ''}.
            {summary ? ` Perubahan: ${summary.added} ditambahkan, ${summary.removed} dihapus, ${summary.changed} diubah.` : ''}
          </>
        }
        confirmLabel="Setujui"
        onOpenChange={(o) => o && setApproveNote('')}
        action={() => mobilityApprove(activityId, approveNote.trim() || null)}
        successMessage={(r) => `${code}: peserta disetujui · status ${ACTIVITY_STATUS_LABEL[r.status]}.`}
      >
        {({ pending }) => (
          <NoteField id={`${uid}-approve-note`} label="Catatan" value={approveNote} onChange={setApproveNote} disabled={pending} />
        )}
      </ActionDialog>

      <ActionDialog
        wide
        triggerLabel={
          <>
            <RotateCcw className="mr-1 h-4 w-4" aria-hidden="true" />
            Minta Revisi
          </>
        }
        triggerVariant="outline"
        triggerTestId="action-request-revision"
        title={`Minta revisi peserta ${code}`}
        description={`Unit akan membuat versi peserta baru. ${version ? `Versi v${version.version} disimpan apa adanya (hanya baca).` : ''} Catatan per baris bersifat opsional.`}
        confirmLabel="Kirim permintaan revisi"
        onOpenChange={(o) => {
          if (o) {
            setRevisionNote('');
            setRowNotes({});
          }
        }}
        validate={() => (revisionNote.trim() ? {} : { note: 'Catatan revisi wajib diisi.' })}
        action={() => mobilityRequestRevision(activityId, revisionNote.trim(), collectRowNotes())}
        successMessage={`${code}: permintaan revisi peserta dikirim ke unit.`}
      >
        {({ errors, pending }) => (
          <>
            <NoteField
              id={`${uid}-revision-note`}
              label="Catatan revisi"
              required
              value={revisionNote}
              onChange={setRevisionNote}
              error={errors.note}
              disabled={pending}
            />
            {rows.length > 0 ? (
              <fieldset className="space-y-2">
                <legend className="text-sm font-medium">Catatan per baris (opsional)</legend>
                <div className="max-h-72 overflow-y-auto rounded-md border">
                  <table className="w-full text-sm">
                    <thead className="sticky top-0 bg-muted text-left text-xs uppercase tracking-wide text-muted-foreground">
                      <tr>
                        <th scope="col" className="px-3 py-2">Peserta</th>
                        <th scope="col" className="px-3 py-2">Catatan</th>
                      </tr>
                    </thead>
                    <tbody>
                      {rows.map((r) => {
                        const inputId = `${uid}-row-${r.key}`;
                        return (
                          <tr key={r.key} className="border-t">
                            <th scope="row" className="px-3 py-2 text-left align-top font-normal">
                              <label htmlFor={inputId} className="block">
                                <span className="font-mono text-xs">{r.label}</span>
                                <span className="block text-xs text-muted-foreground">{r.group}</span>
                              </label>
                            </th>
                            <td className="px-3 py-2">
                              <Input
                                id={inputId}
                                name={inputId}
                                type="text"
                                value={rowNotes[r.key] ?? ''}
                                onChange={(e) => setRowNote(r.key, e.target.value)}
                                disabled={pending}
                                maxLength={1000}
                                placeholder="Mis. transkrip tidak terbaca"
                              />
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              </fieldset>
            ) : null}
          </>
        )}
      </ActionDialog>
    </div>
  );
}
