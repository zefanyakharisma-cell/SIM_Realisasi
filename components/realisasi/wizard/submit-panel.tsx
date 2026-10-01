'use client';
/**
 * Validation checklist (`submission_checklist()`) + late notice + Ajukan / Ajukan ulang (Design §3.3 step 4).
 * The DB re-validates on submit; failures come back with `detail.failures` and are shown inline.
 */
import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { CheckCircle2, Clock, XCircle } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Button } from '@/components/ui/button';
import { toast } from '@/components/ui/toaster';
import { submitActivity } from '@/lib/realisasi/actions/submission';
import { useSaveStatus } from '@/components/realisasi/wizard/save-status';
import { diffFieldLabel } from '@/components/realisasi/activity/labels';
import type { ChecklistItem } from '@/lib/realisasi/types';

const CHECK_LABEL: Record<string, string> = {
  R07_REQUIRED_FIELD: 'Data wajib Detail lengkap',
  R07_AGREEMENT_REQUIRED: 'Minimal satu kerja sama dipilih',
  R04_AGREEMENT_NOT_VALID: 'Kerja sama berlaku pada tanggal kegiatan',
  R08_END_AFTER_TODAY: 'Kegiatan sudah selesai',
  R09_NO_ACADEMIC_YEAR: 'Tanggal mulai berada dalam tahun akademik terdaftar',
  R07_IA_REQUIRED: 'Implementation Arrangement (PDF) diunggah',
  R07_IR_REQUIRED: 'Implementation Report (PDF) diunggah',
  R11_PARTICIPANTS_REQUIRED: 'Data peserta diisi (bila diwajibkan Jenis)',
  R12_OUTBOUND_STUDENT_REQUIRED: 'Minimal satu mahasiswa PETRA (kegiatan outbound)',
  R12_INBOUND_STUDENT_REQUIRED: 'Minimal satu mahasiswa inbound (kegiatan inbound)',
  R16_NRP_NOT_FOUND: 'Semua NRP ditemukan di data BAAK',
  R17_INBOUND_DATA_REQUIRED: 'Data mahasiswa inbound lengkap (institusi asal + transkrip)',
  R19_EMPLOYEE_NOT_FOUND: 'Semua ID pegawai ditemukan di data SDM',
  R21_NEW_VERSION_REQUIRED: 'Versi peserta baru dibuat untuk revisi Mobilitas',
};

interface Failure {
  code: string;
  message: string;
}

function failuresFrom(detail: unknown): Failure[] {
  if (typeof detail !== 'object' || detail === null || !('failures' in detail)) return [];
  const f = (detail as { failures: unknown }).failures;
  return Array.isArray(f) ? f.filter((x): x is Failure => typeof x === 'object' && x !== null && 'code' in x && 'message' in x) : [];
}

export function SubmitPanel({
  activityId,
  checklist,
  resubmit = false,
  blockedReason,
  redirectTo,
}: {
  activityId: string;
  checklist: ChecklistItem[] | null;
  resubmit?: boolean;
  /** Client-side reason to keep the button disabled (e.g. unsaved red participant rows). */
  blockedReason?: string | null;
  redirectTo?: string;
}) {
  const router = useRouter();
  const { blocker, flush } = useSaveStatus();
  const [pending, startTransition] = useTransition();
  const [serverFailures, setServerFailures] = useState<Failure[]>([]);
  const [error, setError] = useState<string | null>(null);

  // Requirements review L-3: the "new participant version" rule only applies to a resubmission.
  const items = (checklist ?? []).filter((c) => c.code !== 'LATE_NOTICE' && (resubmit || c.code !== 'R21_NEW_VERSION_REQUIRED' || !c.ok));
  const late = (checklist ?? []).find((c) => c.code === 'LATE_NOTICE' && c.late);
  const failing = items.filter((c) => !c.ok);
  // M-1: unsaved Detail edits (revision mode has no autosave) also block "Ajukan ulang".
  const reason = blockedReason ?? blocker;
  const disabled = failing.length > 0 || Boolean(reason) || checklist === null;

  function onSubmit() {
    setError(null);
    setServerFailures([]);
    startTransition(async () => {
      // M-1: pending participant edits must be stored before the DB re-validates and submits.
      if (!(await flush())) {
        setError('Perubahan terakhir belum tersimpan. Periksa isian yang ditandai lalu coba lagi.');
        return;
      }
      const res = await submitActivity(activityId);
      if (!res.ok) {
        setError(res.message);
        setServerFailures(failuresFrom(res.detail));
        router.refresh();
        return;
      }
      toast.success(resubmit ? 'Kegiatan diajukan ulang.' : 'Kegiatan berhasil diajukan.', {
        description: res.data.is_late ? 'Kegiatan ditandai Terlambat.' : undefined,
      });
      router.push(redirectTo ?? `/realisasi/kegiatan/${activityId}`);
      router.refresh();
    });
  }

  return (
    <section aria-labelledby="checklist-title" className="space-y-4">
      <h2 id="checklist-title" className="text-base font-semibold">
        Pemeriksaan sebelum {resubmit ? 'diajukan ulang' : 'diajukan'}
      </h2>
      {checklist === null ? (
        <p className="text-sm text-muted-foreground">Pemeriksaan tidak tersedia untuk kegiatan ini.</p>
      ) : (
        <ul className="space-y-2" data-testid="submission-checklist">
          {items.map((c) => (
            <li key={c.code} className="flex items-start gap-2 text-sm" data-ok={c.ok} data-code={c.code}>
              {c.ok ? (
                <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-green-700" aria-hidden />
              ) : (
                <XCircle className="mt-0.5 h-4 w-4 shrink-0 text-red-700" aria-hidden />
              )}
              <span>
                <span className="sr-only">{c.ok ? 'Terpenuhi: ' : 'Belum terpenuhi: '}</span>
                <span className={c.ok ? '' : 'font-medium text-red-800'}>{CHECK_LABEL[c.code] ?? c.code}</span>
                {!c.ok && <span className="block text-red-800">{c.message}</span>}
                {!c.ok && c.fields && c.fields.length > 0 && (
                  <span className="block text-red-800" data-testid="checklist-fields">
                    Belum diisi: {c.fields.map(diffFieldLabel).join(', ')}
                  </span>
                )}
              </span>
            </li>
          ))}
        </ul>
      )}

      {late && (
        <Alert variant="warning" role="status">
          <Clock aria-hidden />
          <AlertTitle>Melewati batas pelaporan</AlertTitle>
          <AlertDescription>{late.message}</AlertDescription>
        </Alert>
      )}

      {reason && (
        <Alert variant="destructive" role="status" data-testid="submit-blocked">
          <XCircle aria-hidden />
          <AlertDescription>{reason}</AlertDescription>
        </Alert>
      )}

      {error && (
        <Alert variant="destructive" role="alert" data-testid="submit-error">
          <XCircle aria-hidden />
          <AlertTitle>Pengajuan gagal</AlertTitle>
          <AlertDescription>
            <p>{error}</p>
            {serverFailures.length > 1 && (
              <ul className="mt-1 list-disc pl-5">
                {serverFailures.map((f) => (
                  <li key={f.code}>{f.message}</li>
                ))}
              </ul>
            )}
          </AlertDescription>
        </Alert>
      )}

      <div className="flex flex-wrap items-center gap-3">
        <Button
          onClick={onSubmit}
          disabled={disabled}
          loading={pending}
          data-testid={resubmit ? 'action-resubmit' : 'wizard-submit'}
          aria-describedby={disabled ? 'submit-disabled-hint' : undefined}
        >
          {resubmit ? 'Ajukan ulang' : 'Ajukan'}
        </Button>
        {disabled && (
          <p id="submit-disabled-hint" className="text-sm text-muted-foreground">
            Lengkapi butir yang belum terpenuhi untuk dapat {resubmit ? 'mengajukan ulang' : 'mengajukan'}.
          </p>
        )}
      </div>
    </section>
  );
}
