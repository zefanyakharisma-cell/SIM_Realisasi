'use client';

import { useId, useState } from 'react';
import { Link2, Unlink, X } from 'lucide-react';
import { ActionDialog, NoteField } from '@/components/realisasi/verify/action-dialog';
import { dismissDuplicate, linkDuplicates, unlinkActivity } from '@/lib/realisasi/actions/duplicates';

interface Side {
  id: string;
  code: string;
}

/** Tautkan / Bukan duplikat for an open candidate; admin-only "Batalkan tautan" for a linked one. */
export function CandidateActions({
  candidateId,
  status,
  a,
  b,
  canManage,
  canUnlink,
}: {
  candidateId: number;
  status: 'open' | 'linked' | 'dismissed';
  a: Side;
  b: Side;
  canManage: boolean;
  canUnlink: boolean;
}) {
  const uid = useId();
  const [note, setNote] = useState('');
  const [side, setSide] = useState<string>(b.id);
  const pair = `${a.code} & ${b.code}`;

  if (status === 'open' && canManage) {
    return (
      <div className="flex flex-wrap gap-2" role="group" aria-label={`Tindakan kandidat ${pair}`}>
        <ActionDialog
          triggerLabel={
            <>
              <Link2 aria-hidden="true" />
              Tautkan sebagai satu kegiatan
            </>
          }
          triggerTestId="dup-link"
          title="Tautkan sebagai satu kegiatan?"
          description={`${pair} digabung dalam satu grup kegiatan (grup kegiatan yang dibuat lebih dulu dipertahankan). Di tingkat universitas kegiatan dihitung satu kali; masing-masing unit tetap menghitungnya. Hanya Admin IO yang dapat membatalkan.`}
          confirmLabel="Tautkan"
          onOpenChange={(o) => o && setNote('')}
          action={() => linkDuplicates(candidateId, note.trim() || null)}
          successMessage={`${pair} ditautkan.`}
        >
          {({ pending }) => <NoteField id={`${uid}-link`} label="Catatan" value={note} onChange={setNote} disabled={pending} />}
        </ActionDialog>
        <ActionDialog
          triggerVariant="outline"
          triggerTestId="dup-dismiss"
          triggerLabel={
            <>
              <X aria-hidden="true" />
              Bukan duplikat
            </>
          }
          title="Tandai bukan duplikat?"
          description={`Kandidat ${pair} ditutup. Kedua kegiatan tetap dihitung terpisah.`}
          confirmLabel="Bukan duplikat"
          onOpenChange={(o) => o && setNote('')}
          action={() => dismissDuplicate(candidateId, note.trim() || null)}
          successMessage="Kandidat ditandai bukan duplikat."
        >
          {({ pending }) => <NoteField id={`${uid}-dismiss`} label="Catatan" value={note} onChange={setNote} disabled={pending} />}
        </ActionDialog>
      </div>
    );
  }

  if (status === 'linked' && canUnlink) {
    return (
      <ActionDialog
        triggerVariant="outline"
        triggerTestId="dup-unlink"
        triggerLabel={
          <>
            <Unlink aria-hidden="true" />
            Batalkan tautan
          </>
        }
        title="Batalkan tautan duplikat?"
        description="Kegiatan yang dipilih dipisahkan ke grup kegiatan baru; kandidat tertaut ditandai Bukan duplikat (R-34). Tindakan dicatat di riwayat."
        confirmLabel="Batalkan tautan"
        confirmVariant="destructive"
        onOpenChange={(o) => {
          if (o) {
            setNote('');
            setSide(b.id);
          }
        }}
        validate={() => (note.trim() ? {} : { note: 'Catatan wajib diisi.' })}
        action={() => unlinkActivity(side, note.trim())}
        successMessage="Tautan dibatalkan."
      >
        {({ errors, pending }) => (
          <>
            <fieldset className="space-y-2">
              <legend className="text-sm font-medium">Kegiatan yang dipisahkan</legend>
              {[a, b].map((s) => (
                <label key={s.id} className="flex items-center gap-2 text-sm">
                  <input
                    type="radio"
                    name={`${uid}-side`}
                    value={s.id}
                    checked={side === s.id}
                    onChange={() => setSide(s.id)}
                    disabled={pending}
                    className="h-4 w-4"
                  />
                  <span className="font-mono text-xs">{s.code}</span>
                </label>
              ))}
            </fieldset>
            <NoteField id={`${uid}-unlink`} label="Alasan" required value={note} onChange={setNote} error={errors.note} disabled={pending} />
          </>
        )}
      </ActionDialog>
    );
  }
  return null;
}
