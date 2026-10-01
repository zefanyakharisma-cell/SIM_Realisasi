'use client';

import { useId, useState, useTransition } from 'react';
import Link from 'next/link';
import { Link2, Search, Unlink } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { ActionDialog, NoteField } from '@/components/realisasi/verify/action-dialog';
import {
  dismissDuplicate,
  linkActivities,
  linkDuplicates,
  lookupActivityByCode,
  unlinkActivity,
  type ActivityLookup,
} from '@/lib/realisasi/actions/duplicates';
import { ACTIVITY_STATUS_LABEL, DUP_STATUS_LABEL } from '@/lib/realisasi/status';
import { formatPct } from '@/lib/realisasi/format';
import type { ActivityDetail, ActivityPermissions } from '@/lib/realisasi/types';

export interface DuplicateActionsProps {
  activityId: string;
  permissions: ActivityPermissions;
  duplicates: ActivityDetail['duplicates'];
}

/**
 * Duplicate handling on the activity detail page (R-33/R-34): open candidates with Tautkan /
 * Bukan duplikat, a manual "Tautkan dengan kegiatan lain" by activity code, and the admin-only
 * "Batalkan tautan". Renders nothing when the user has neither permission.
 */
export function DuplicateActions({ activityId, permissions, duplicates }: DuplicateActionsProps) {
  const uid = useId();
  const [note, setNote] = useState('');
  const [code, setCode] = useState('');
  const [found, setFound] = useState<ActivityLookup | null>(null);
  const [lookupError, setLookupError] = useState<string | null>(null);
  const [looking, startLookup] = useTransition();

  if (!permissions.can_link_duplicate && !permissions.can_unlink_duplicate) return null;

  const open = duplicates.filter((d) => d.status === 'open');

  function lookup() {
    setLookupError(null);
    setFound(null);
    startLookup(async () => {
      const res = await lookupActivityByCode(code, activityId);
      if (res.ok) setFound(res.data);
      else setLookupError(res.message);
    });
  }

  return (
    <div className="space-y-3">
      {permissions.can_link_duplicate && open.length > 0 ? (
        <div className="rounded-md border border-purple-300 bg-purple-50/60 p-3 dark:border-purple-800 dark:bg-purple-950/30">
          <h3 className="text-sm font-semibold">Kemungkinan duplikat ({open.length})</h3>
          <ul className="mt-2 space-y-2">
            {open.map((d) => (
              <li key={d.candidate_id} className="flex flex-wrap items-center gap-2 text-sm">
                <Link href={`/realisasi/kegiatan/${d.other_activity_id}`} className="font-mono text-xs underline underline-offset-4">
                  {d.other_code}
                </Link>
                <span className="min-w-0 flex-1 truncate" title={d.other_name}>
                  {d.other_name}
                </span>
                <span className="rounded-full border border-purple-500 px-2 py-0.5 text-xs">
                  Kemiripan {formatPct(d.score * 100)}
                </span>
                <ActionDialog
                  triggerLabel={
                    <>
                      <Link2 className="mr-1 h-4 w-4" aria-hidden="true" />
                      Tautkan<span className="sr-only"> dengan {d.other_code}</span>
                    </>
                  }
                  title="Tautkan sebagai satu kegiatan?"
                  description={`Kedua kegiatan digabung dalam satu grup kegiatan dan dihitung satu kali di tingkat universitas (R-39). Data unit, berkas, dan peserta masing-masing tetap terpisah. Hanya Admin IO yang dapat membatalkan tautan.`}
                  confirmLabel="Tautkan"
                  onOpenChange={(o) => o && setNote('')}
                  action={() => linkDuplicates(d.candidate_id, note.trim() || null)}
                  successMessage={`Kegiatan ditautkan dengan ${d.other_code}.`}
                >
                  {({ pending }) => (
                    <NoteField id={`${uid}-link-${d.candidate_id}`} label="Catatan" value={note} onChange={setNote} disabled={pending} />
                  )}
                </ActionDialog>
                <ActionDialog
                  triggerVariant="outline"
                  triggerLabel={
                    <>
                      Bukan duplikat<span className="sr-only"> ({d.other_code})</span>
                    </>
                  }
                  title="Tandai bukan duplikat?"
                  description={`Kandidat dengan ${d.other_code} akan ditutup sebagai "${DUP_STATUS_LABEL.dismissed}".`}
                  confirmLabel="Bukan duplikat"
                  onOpenChange={(o) => o && setNote('')}
                  action={() => dismissDuplicate(d.candidate_id, note.trim() || null)}
                  successMessage="Kandidat duplikat ditutup."
                >
                  {({ pending }) => (
                    <NoteField id={`${uid}-dismiss-${d.candidate_id}`} label="Catatan" value={note} onChange={setNote} disabled={pending} />
                  )}
                </ActionDialog>
              </li>
            ))}
          </ul>
        </div>
      ) : null}

      <div className="flex flex-wrap gap-2">
        {permissions.can_link_duplicate ? (
          <ActionDialog
            triggerVariant="outline"
            triggerTestId="action-link-duplicate"
            triggerLabel={
              <>
                <Link2 className="mr-1 h-4 w-4" aria-hidden="true" />
                Tautkan Duplikat
              </>
            }
            title="Tautkan dengan kegiatan lain"
            description="Gunakan bila dua unit melaporkan kegiatan yang sama. Kegiatan akan dihitung satu kali di tingkat universitas."
            confirmLabel="Tautkan"
            onOpenChange={(o) => {
              if (o) {
                setCode('');
                setNote('');
                setFound(null);
                setLookupError(null);
              }
            }}
            validate={() => {
              const e: Record<string, string> = {};
              if (!found) e.code = 'Cari dan pilih kegiatan yang akan ditautkan.';
              if (!note.trim()) e.note = 'Catatan wajib diisi.';
              return e;
            }}
            action={() => linkActivities(activityId, found!.id, note.trim())}
            successMessage={() => `Kegiatan ditautkan dengan ${found?.code ?? 'kegiatan lain'}.`}
          >
            {({ errors, pending }) => (
              <>
                <div className="space-y-1.5">
                  <label htmlFor={`${uid}-code`} className="text-sm font-medium">
                    Kode kegiatan lain
                    <span className="text-red-700 dark:text-red-400">
                      {' '}*<span className="sr-only"> (wajib)</span>
                    </span>
                  </label>
                  <div className="flex gap-2">
                    <Input
                      id={`${uid}-code`}
                      name="code"
                      value={code}
                      onChange={(e) => {
                        setCode(e.target.value);
                        setFound(null);
                      }}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter') {
                          e.preventDefault();
                          lookup();
                        }
                      }}
                      placeholder="RL-2026-0014"
                      autoComplete="off"
                      disabled={pending}
                      aria-invalid={errors.code || lookupError ? true : undefined}
                      aria-describedby={`${uid}-code-status`}
                      className="uppercase"
                    />
                    <Button type="button" variant="outline" onClick={lookup} loading={looking} disabled={pending || code.trim() === ''}>
                      {looking ? null : <Search aria-hidden="true" />}
                      Cari
                    </Button>
                  </div>
                  <div id={`${uid}-code-status`} aria-live="polite" className="text-sm">
                    {looking ? <span className="text-muted-foreground">Mencari…</span> : null}
                    {lookupError ? <span className="text-red-700 dark:text-red-400">{lookupError}</span> : null}
                    {!lookupError && errors.code ? <span className="text-red-700 dark:text-red-400">{errors.code}</span> : null}
                    {found ? (
                      <span className="block rounded-md border bg-muted/40 p-2">
                        <span className="font-mono text-xs">{found.code}</span> · {found.name}
                        <span className="block text-xs text-muted-foreground">
                          {found.submitter_unit_name} · {ACTIVITY_STATUS_LABEL[found.status]}
                        </span>
                      </span>
                    ) : null}
                  </div>
                </div>
                <NoteField
                  id={`${uid}-manual-note`}
                  label="Catatan"
                  required
                  value={note}
                  onChange={setNote}
                  error={errors.note}
                  disabled={pending}
                />
              </>
            )}
          </ActionDialog>
        ) : null}

        {permissions.can_unlink_duplicate ? (
          <ActionDialog
            triggerVariant="outline"
            triggerTestId="action-unlink-duplicate"
            triggerLabel={
              <>
                <Unlink className="mr-1 h-4 w-4" aria-hidden="true" />
                Batalkan tautan
              </>
            }
            title="Batalkan tautan duplikat?"
            description="Kegiatan ini dipisahkan ke grup kegiatan baru dan kandidat yang tertaut ditandai Bukan duplikat (R-34). Tindakan dicatat."
            confirmLabel="Batalkan tautan"
            confirmVariant="destructive"
            onOpenChange={(o) => o && setNote('')}
            validate={() => (note.trim() ? {} : { note: 'Catatan wajib diisi.' })}
            action={() => unlinkActivity(activityId, note.trim())}
            successMessage="Tautan duplikat dibatalkan."
          >
            {({ errors, pending }) => (
              <NoteField
                id={`${uid}-unlink-note`}
                label="Alasan"
                required
                value={note}
                onChange={setNote}
                error={errors.note}
                disabled={pending}
              />
            )}
          </ActionDialog>
        ) : null}
      </div>
    </div>
  );
}
