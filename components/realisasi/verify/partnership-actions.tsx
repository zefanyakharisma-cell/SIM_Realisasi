'use client';

import { useId, useState } from 'react';
import { Check, RotateCcw, X } from 'lucide-react';
import { ActionDialog, NoteField } from '@/components/realisasi/verify/action-dialog';
import { partnershipApprove, partnershipReject, partnershipRequestRevision } from '@/lib/realisasi/actions/verification';
import { ACTIVITY_STATUS_LABEL, REJECT_REASON_LABEL } from '@/lib/realisasi/status';
import { REJECT_REASONS } from '@/lib/realisasi/schemas/verification';
import { NativeSelect } from '@/components/ui/native-select';
import type { ActivityPermissions, RejectReason } from '@/lib/realisasi/types';

export interface PartnershipActionsProps {
  activityId: string;
  code: string;
  permissions: ActivityPermissions;
}

/**
 * Kemitraan-track actions (Approve / Minta Revisi / Tolak) for the queue's expanded row and the
 * activity detail action bar. Renders nothing unless `permissions.can_partnership_verify`.
 */
export function PartnershipActions({ activityId, code, permissions }: PartnershipActionsProps) {
  const uid = useId();
  const [approveNote, setApproveNote] = useState('');
  const [revisionNote, setRevisionNote] = useState('');
  const [reason, setReason] = useState<RejectReason | ''>('');
  const [rejectNote, setRejectNote] = useState('');

  if (!permissions.can_partnership_verify) return null;

  return (
    <div className="flex flex-wrap items-center gap-2" role="group" aria-label={`Verifikasi Kemitraan ${code}`}>
      <ActionDialog
        triggerLabel={
          <>
            <Check className="mr-1 h-4 w-4" aria-hidden="true" />
            Setujui
          </>
        }
        triggerTestId="action-approve"
        title={`Setujui Kemitraan ${code}?`}
        description="Jalur Kemitraan akan ditandai Disetujui. Jika jalur Mobilitas sudah disetujui atau tidak diperlukan, kegiatan menjadi Terverifikasi dan unit diberi tahu."
        confirmLabel="Setujui"
        onOpenChange={(o) => o && setApproveNote('')}
        action={() => partnershipApprove(activityId, approveNote.trim() || null)}
        successMessage={(r) => `${code}: Kemitraan disetujui · status ${ACTIVITY_STATUS_LABEL[r.status]}.`}
      >
        {({ pending }) => (
          <NoteField
            id={`${uid}-approve-note`}
            label="Catatan"
            value={approveNote}
            onChange={setApproveNote}
            disabled={pending}
          />
        )}
      </ActionDialog>

      <ActionDialog
        triggerLabel={
          <>
            <RotateCcw className="mr-1 h-4 w-4" aria-hidden="true" />
            Minta Revisi
          </>
        }
        triggerVariant="outline"
        triggerTestId="action-request-revision"
        title={`Minta revisi Kemitraan ${code}`}
        description="Unit akan menerima catatan ini dan dapat memperbaiki Detail serta Berkas, lalu mengajukan ulang."
        confirmLabel="Kirim permintaan revisi"
        onOpenChange={(o) => o && setRevisionNote('')}
        validate={() => (revisionNote.trim() ? {} : { note: 'Catatan revisi wajib diisi.' })}
        action={() => partnershipRequestRevision(activityId, revisionNote.trim())}
        successMessage={`${code}: permintaan revisi dikirim ke unit.`}
      >
        {({ errors, pending }) => (
          <NoteField
            id={`${uid}-revision-note`}
            label="Catatan revisi"
            required
            value={revisionNote}
            onChange={setRevisionNote}
            error={errors.note}
            placeholder="Contoh: IA yang diunggah salah, mohon unggah IA yang ditandatangani kedua pihak."
            disabled={pending}
          />
        )}
      </ActionDialog>

      {permissions.can_reject ? (
        <ActionDialog
          triggerLabel={
            <>
              <X className="mr-1 h-4 w-4" aria-hidden="true" />
              Tolak
            </>
          }
          triggerVariant="destructive"
          triggerTestId="action-reject"
          title={`Tolak ${code}?`}
          description="Penolakan bersifat final (R-26). Kegiatan tidak dapat diajukan ulang dan tidak dihitung dalam KPI."
          confirmLabel="Tolak kegiatan"
          confirmVariant="destructive"
          onOpenChange={(o) => {
            if (o) {
              setReason('');
              setRejectNote('');
            }
          }}
          validate={() => {
            const e: Record<string, string> = {};
            if (!reason) e.reason = 'Pilih alasan penolakan.';
            if (!rejectNote.trim()) e.note = 'Catatan penolakan wajib diisi.';
            return e;
          }}
          action={() => partnershipReject(activityId, reason as RejectReason, rejectNote.trim())}
          successMessage={`${code} ditolak.`}
        >
          {({ errors, pending }) => (
            <>
              <div className="space-y-1.5">
                <label htmlFor={`${uid}-reason`} className="text-sm font-medium">
                  Alasan penolakan
                  <span className="text-red-700 dark:text-red-400">
                    {' '}*<span className="sr-only"> (wajib)</span>
                  </span>
                </label>
                <NativeSelect
                  id={`${uid}-reason`}
                  name="reason"
                  value={reason}
                  onChange={(e) => setReason(e.target.value as RejectReason | '')}
                  disabled={pending}
                  aria-invalid={errors.reason ? true : undefined}
                  aria-describedby={errors.reason ? `${uid}-reason-error` : undefined}
                  aria-required
                  data-testid="reject-reason"
                >
                  <option value="">Pilih alasan…</option>
                  {REJECT_REASONS.map((r) => (
                    <option key={r} value={r}>
                      {REJECT_REASON_LABEL[r]}
                    </option>
                  ))}
                </NativeSelect>
                {errors.reason ? (
                  <p id={`${uid}-reason-error`} className="text-sm text-red-700 dark:text-red-400">
                    {errors.reason}
                  </p>
                ) : null}
              </div>
              <NoteField
                id={`${uid}-reject-note`}
                label="Catatan penolakan"
                required
                value={rejectNote}
                onChange={setRejectNote}
                error={errors.note}
                disabled={pending}
              />
            </>
          )}
        </ActionDialog>
      ) : null}
    </div>
  );
}
