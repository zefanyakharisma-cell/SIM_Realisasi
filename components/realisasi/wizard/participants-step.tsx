'use client';
/**
 * Peserta section of the single-page form: the editor; red rows (R-16, AT-10) block "Ajukan" through
 * the shared save-status blocker instead of a step navigation (Revisi V.1).
 */
import { useEffect, useState } from 'react';
import { ParticipantsEditor, type ParticipantsEditorProps } from '@/components/realisasi/wizard/participants-editor';
import { useSaveActions } from '@/components/realisasi/wizard/save-status';

export function ParticipantsStep(props: Omit<ParticipantsEditorProps, 'onBlockingChange'>) {
  const save = useSaveActions();
  const [blocking, setBlocking] = useState(false);
  useEffect(() => {
    save.setBlocker('participants', blocking ? 'Hapus baris peserta bertanda ✗ sebelum mengajukan.' : null);
    return () => save.setBlocker('participants', null);
  }, [blocking, save]);
  return <ParticipantsEditor {...props} onBlockingChange={setBlocking} />;
}
