'use client';

import { useId, useState } from 'react';
import { Check, RotateCcw } from 'lucide-react';
import { ActionDialog, NoteField } from '@/components/realisasi/verify/action-dialog';
import { mobilityApprove, mobilityRequestRevision } from '@/lib/realisasi/actions/verification';
import { diffParticipantVersions, summarizeDiff } from '@/lib/realisasi/participant-diff';
import { ACTIVITY_STATUS_LABEL } from '@/lib/realisasi/status';
import type { ActivityPermissions, ParticipantVersion } from '@/lib/realisasi/types';

export interface MobilityActionsProps {
  activityId: string;
  code: string;
  /** The version under review (latest `pending`). */
  version: ParticipantVersion | null;
  /** Previous non-draft version, for the change summary. */
  previous: ParticipantVersion | null;
  permissions: ActivityPermissions;
  /** Open duplicate-student conflicts (Revisi V.1 rule 2.1) block approval until resolved. */
  conflictsOpen?: number;
}

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
 * Mobilitas-track actions (Approve / Minta Revisi, R-27). Revisi V.1: Setujui is a plain confirmation (no Catatan);
 * Minta Revisi keeps one required general note.
 * Renders nothing unless `permissions.can_mobility_verify`.
 */
export function MobilityActions({ activityId, code, version, previous, permissions, conflictsOpen = 0 }: MobilityActionsProps) {
  const uid = useId();
  const [revisionNote, setRevisionNote] = useState('');

  if (!permissions.can_mobility_verify) return null;

  const summary = version && previous ? summarizeDiff(diffParticipantVersions(previous, version)) : null;
  const versionText = version ? `v${version.version} (${countsText(version)})` : 'versi yang diajukan';

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
        triggerDisabled={conflictsOpen > 0}
        title={`Setujui peserta ${code}?`}
        description={
          <>
            Apakah Anda yakin ingin menyetujui peserta {code}? Data peserta {versionText} akan disetujui dan menjadi satu-satunya versi yang dihitung (R-21)
            {previous ? `; versi v${previous.version} tetap tersimpan sebagai riwayat` : ''}.
            {summary ? ` Perubahan: ${summary.added} ditambahkan, ${summary.removed} dihapus, ${summary.changed} diubah.` : ''}
          </>
        }
        confirmLabel="Ya, setujui"
        action={() => mobilityApprove(activityId, null)}
        successMessage={(r) => `${code}: peserta disetujui · status ${ACTIVITY_STATUS_LABEL[r.status]}.`}
      />

      <ActionDialog
        triggerLabel={
          <>
            <RotateCcw className="mr-1 h-4 w-4" aria-hidden="true" />
            Minta Revisi
          </>
        }
        triggerVariant="outline"
        triggerTestId="action-request-revision"
        title={`Minta revisi peserta ${code}`}
        description={`Unit akan membuat versi peserta baru. ${version ? `Versi v${version.version} disimpan apa adanya (hanya baca).` : ''}`}
        confirmLabel="Kirim permintaan revisi"
        onOpenChange={(o) => {
          if (o) setRevisionNote('');
        }}
        validate={() => (revisionNote.trim() ? {} : { note: 'Catatan revisi wajib diisi.' })}
        action={() => mobilityRequestRevision(activityId, revisionNote.trim())}
        successMessage={`${code}: permintaan revisi peserta dikirim ke unit.`}
      >
        {({ errors, pending }) => (
          <NoteField
            id={`${uid}-revision-note`}
            label="Catatan revisi"
            required
            value={revisionNote}
            onChange={setRevisionNote}
            error={errors.note}
            disabled={pending}
          />
        )}
      </ActionDialog>
      {conflictsOpen > 0 ? (
        <p className="w-full text-xs text-amber-800 dark:text-amber-300" role="status" data-testid="approve-blocked-conflicts">
          Selesaikan {conflictsOpen} duplikat mahasiswa terlebih dahulu sebelum menyetujui peserta.
        </p>
      ) : null}
    </div>
  );
}
