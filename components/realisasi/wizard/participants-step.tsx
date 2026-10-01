'use client';
/** Step 2 wrapper: editor + navigation that is blocked while red rows exist (R-16, AT-10). */
import { useState } from 'react';
import { ParticipantsEditor, type ParticipantsEditorProps } from '@/components/realisasi/wizard/participants-editor';
import { WizardNav } from '@/components/realisasi/wizard/wizard-nav';

export function ParticipantsStep(props: Omit<ParticipantsEditorProps, 'onBlockingChange'>) {
  const [blocking, setBlocking] = useState(false);
  return (
    <div className="space-y-6">
      <ParticipantsEditor {...props} onBlockingChange={setBlocking} />
      <WizardNav
        draftId={props.activityId}
        step={2}
        nextDisabled={blocking}
        saveDisabled={blocking}
        nextHint={blocking ? 'Hapus baris bertanda ✗ sebelum melanjutkan.' : undefined}
      />
    </div>
  );
}
