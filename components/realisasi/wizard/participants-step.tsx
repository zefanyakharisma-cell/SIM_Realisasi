'use client';
/**
 * Peserta section of the single-page form: the editor; red rows (R-16, AT-10) block "Ajukan" through
 * the shared save-status blocker instead of a step navigation (Revisi V.1).
 */
import { useCallback, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { ParticipantsEditor, type ParticipantsEditorProps } from '@/components/realisasi/wizard/participants-editor';
import { useSaveActions } from '@/components/realisasi/wizard/save-status';

export function ParticipantsStep(props: Omit<ParticipantsEditorProps, 'onBlockingChange'>) {
  const save = useSaveActions();
  const router = useRouter();
  // the server-rendered submission checklist (R11/R12/R16…) must follow the saved participants
  const onSaved = useCallback(() => router.refresh(), [router]);
  const [blocking, setBlocking] = useState(false);
  useEffect(() => {
    save.setBlocker('participants', blocking ? 'Hapus baris peserta bertanda ✗ sebelum mengajukan.' : null);
    return () => save.setBlocker('participants', null);
  }, [blocking, save]);
  return <ParticipantsEditor {...props} onSaved={onSaved} onBlockingChange={setBlocking} />;
}
