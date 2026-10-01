'use client';
/** IO Mobility post-verification participant edit: editor + note + commit as auto-approved version (R-29). */
import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { AlertCircle } from 'lucide-react';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { toast } from '@/components/ui/toaster';
import { ParticipantsEditor } from '@/components/realisasi/wizard/participants-editor';
import { commitParticipantEdit } from '@/lib/realisasi/actions/submission';
import type { CountryOption } from '@/lib/realisasi/queries/lookups';
import type { ParticipantVersion } from '@/lib/realisasi/types';

export function ParticipantCommit({
  activityId,
  version,
  countries,
  required,
}: {
  activityId: string;
  version: ParticipantVersion | null;
  countries: CountryOption[];
  required: { any: boolean; internal: boolean; inbound: boolean };
}) {
  const router = useRouter();
  const [blocking, setBlocking] = useState(false);
  const [hasDraft, setHasDraft] = useState(version?.status === 'draft');
  const [note, setNote] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function commit() {
    setError(null);
    if (!note.trim()) {
      setError('Catatan perubahan wajib diisi.');
      return;
    }
    startTransition(async () => {
      const res = await commitParticipantEdit(activityId, note);
      if (!res.ok) {
        setError(res.message);
        return;
      }
      toast.success(`Versi peserta v${res.data.version} disimpan dan disetujui.`, {
        description: res.data.in_frozen_period ? 'Dicatat sebagai Perubahan Pasca-Beku.' : undefined,
      });
      router.push(`/realisasi/kegiatan/${activityId}?tab=peserta`);
      router.refresh();
    });
  }

  return (
    <div className="space-y-6">
      <ParticipantsEditor
        activityId={activityId}
        initialVersion={version}
        countries={countries}
        required={required}
        onBlockingChange={setBlocking}
        onSaved={() => setHasDraft(true)}
        versionNote="Perubahan disimpan sebagai draf versi baru; versi yang disetujui saat ini tetap berlaku sampai Anda menyimpan."
      />
      <section aria-labelledby="commit-title" className="space-y-3 rounded-lg border p-4">
        <h2 id="commit-title" className="font-semibold">
          Simpan sebagai versi baru
        </h2>
        <Label htmlFor="commit-note">Catatan perubahan *</Label>
        <Textarea
          id="commit-note"
          rows={3}
          value={note}
          onChange={(e) => setNote(e.target.value)}
          aria-invalid={Boolean(error) || undefined}
          aria-describedby={error ? 'commit-error' : undefined}
        />
        {error && (
          <Alert variant="destructive" role="alert" id="commit-error">
            <AlertCircle aria-hidden />
            <AlertDescription>{error}</AlertDescription>
          </Alert>
        )}
        <Button onClick={commit} loading={pending} disabled={blocking || !hasDraft} data-testid="commit-participants">
          Simpan &amp; setujui versi baru
        </Button>
        {!hasDraft && <p className="text-sm text-muted-foreground">Ubah data peserta terlebih dahulu.</p>}
      </section>
    </div>
  );
}
