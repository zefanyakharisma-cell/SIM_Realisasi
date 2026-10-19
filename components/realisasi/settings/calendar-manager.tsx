'use client';

import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import { Lock, Pencil, Plus, RefreshCcw, Snowflake } from 'lucide-react';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from '@/components/ui/alert-dialog';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Textarea } from '@/components/ui/textarea';
import { toast } from '@/components/ui/toaster';
import { freezeNow, refreeze, upsertAcademicYear, upsertSemester } from '@/lib/realisasi/actions/settings';
import { formatDate, formatDateTime } from '@/lib/realisasi/format';
import { SNAPSHOT_KIND_LABEL } from '@/lib/realisasi/status';
import type { SnapshotKind, SnapshotListRow } from '@/lib/realisasi/types';

interface Year { id: number; label: string; start_date: string; end_date: string }
interface Semester { id: number; academic_year_id: number; term: 'ganjil' | 'genap'; start_date: string; end_date: string; cutoff_date: string }

const TERM_LABEL = { ganjil: 'Ganjil', genap: 'Genap' } as const;
const kindOf = (t: Semester['term']): SnapshotKind => (t === 'ganjil' ? 'ganjil_ytd' : 'genap_full_year');

export function CalendarManager({
  years,
  semesters,
  snapshots,
  today,
}: {
  years: Year[];
  semesters: Semester[];
  snapshots: SnapshotListRow[];
  today: string;
}) {
  return (
    <div className="space-y-6">
      {years.map((y) => (
        <Card key={y.id} className="p-5">
          <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
            <div>
              <h2 className="text-base font-semibold">Tahun Akademik {y.label}</h2>
              <p className="text-sm text-muted-foreground">
                {formatDate(y.start_date)} – {formatDate(y.end_date)}
              </p>
            </div>
            <YearDialog year={y} />
          </div>
          <Table containerLabel={`Semester ${y.label}`}>
            <TableHeader>
              <TableRow>
                <TableHead>Semester</TableHead>
                <TableHead>Mulai</TableHead>
                <TableHead>Selesai</TableHead>
                <TableHead>Cutoff</TableHead>
                <TableHead>Snapshot</TableHead>
                <TableHead className="text-right">Aksi</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {semesters
                .filter((s) => s.academic_year_id === y.id)
                .map((s) => {
                  const kind = kindOf(s.term);
                  const live = snapshots.find((x) => x.ay_id === y.id && x.kind === kind && x.is_live);
                  const superseded = snapshots.filter((x) => x.ay_id === y.id && x.kind === kind && !x.is_live).length;
                  return (
                    <TableRow key={s.id} data-testid={`semester-row-${s.id}`}>
                      <TableCell className="font-medium">
                        {TERM_LABEL[s.term]} <span className="text-xs text-muted-foreground">→ {SNAPSHOT_KIND_LABEL[kind]}</span>
                      </TableCell>
                      <TableCell>{formatDate(s.start_date)}</TableCell>
                      <TableCell>{formatDate(s.end_date)}</TableCell>
                      <TableCell>
                        {formatDate(s.cutoff_date)}
                        {s.cutoff_date <= today && !live ? <div className="text-xs text-warning-fg">cutoff terlewati</div> : null}
                      </TableCell>
                      <TableCell>
                        {live ? (
                          <div className="space-y-0.5">
                            <Badge variant="blue">
                              <Lock className="h-3 w-3" aria-hidden="true" /> Dibekukan {formatDate(live.frozen_at)}
                            </Badge>
                            <div className="text-xs text-muted-foreground">
                              oleh {live.frozen_by_name || 'Job terjadwal'}
                              {superseded ? ` · ${superseded} versi digantikan` : ''}
                            </div>
                          </div>
                        ) : (
                          <Badge variant="neutral" appearance="outline">
                            Belum dibekukan
                          </Badge>
                        )}
                      </TableCell>
                      <TableCell className="text-right">
                        <div className="flex justify-end gap-2">
                          <SemesterDialog semester={s} />
                          {live ? (
                            <RefreezeDialog snapshot={live} />
                          ) : (
                            <FreezeButton
                              ayId={y.id}
                              kind={kind}
                              label={`${TERM_LABEL[s.term]} ${y.label}`}
                              cutoff={s.cutoff_date}
                              beforeCutoff={today < s.cutoff_date}
                            />
                          )}
                        </div>
                      </TableCell>
                    </TableRow>
                  );
                })}
            </TableBody>
          </Table>
        </Card>
      ))}
      <YearDialog />
    </div>
  );
}

function useAction() {
  const router = useRouter();
  const [pending, start] = useTransition();
  const run = <T,>(fn: () => Promise<{ ok: true; data: T } | { ok: false; message: string }>, success: string, onOk?: () => void) =>
    start(async () => {
      const res = await fn();
      if (res.ok) {
        toast.success(success, { description: 'Berlaku untuk perhitungan live; snapshot yang sudah dibekukan tidak berubah.' });
        onOk?.();
        router.refresh();
      } else toast.error(res.message);
    });
  return { pending, run };
}

/**
 * "Bekukan sekarang". Freezing before the semester cutoff would snapshot an incomplete period, so
 * the DB refuses it (`R55_BEFORE_CUTOFF`, WP-DB amendment 24 / requirements review M-3); the button
 * is disabled with the reason until the cutoff date.
 */
function FreezeButton({
  ayId,
  kind,
  label,
  cutoff,
  beforeCutoff,
}: {
  ayId: number;
  kind: SnapshotKind;
  label: string;
  cutoff: string;
  beforeCutoff: boolean;
}) {
  const { pending, run } = useAction();
  const hintId = `freeze-hint-${ayId}-${kind}`;
  if (beforeCutoff) {
    return (
      <div className="flex flex-col items-end gap-0.5">
        <Button size="sm" disabled aria-describedby={hintId} data-testid="freeze-now">
          <Snowflake aria-hidden="true" />
          Bekukan sekarang
        </Button>
        <span id={hintId} className="text-xs text-muted-foreground" data-testid="freeze-before-cutoff">
          Dapat dibekukan mulai cutoff {formatDate(cutoff)}
        </span>
      </div>
    );
  }
  return (
    <AlertDialog>
      <AlertDialogTrigger asChild>
        <Button size="sm" disabled={pending} data-testid="freeze-now">
          <Snowflake aria-hidden="true" />
          Bekukan sekarang
        </Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Bekukan snapshot {label}?</AlertDialogTitle>
          <AlertDialogDescription>
            Nilai RENSTRA, kontributor dan pengaturan saat ini akan disimpan sebagai snapshot {SNAPSHOT_KIND_LABEL[kind]}. Snapshot tidak dapat diubah;
            perbaikan hanya melalui &quot;Bekukan ulang&quot; dengan alasan.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>Batal</AlertDialogCancel>
          <AlertDialogAction onClick={() => run(() => freezeNow(ayId, kind), `Snapshot ${label} dibekukan.`)}>Bekukan</AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}

function RefreezeDialog({ snapshot }: { snapshot: SnapshotListRow }) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);
  const { pending, run } = useAction();
  const submit = () => {
    if (reason.trim().length < 5) {
      setError('Alasan pembekuan ulang wajib diisi (min. 5 karakter).');
      return;
    }
    setError(null);
    run(() => refreeze(snapshot.id, reason.trim()), `Snapshot ${snapshot.label} dibekukan ulang.`, () => {
      setOpen(false);
      setReason('');
    });
  };
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm" variant="outline" data-testid="refreeze">
          <RefreshCcw aria-hidden="true" />
          Bekukan ulang
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Bekukan ulang {snapshot.label}</DialogTitle>
          <DialogDescription>
            Snapshot lama (dibekukan {formatDateTime(snapshot.frozen_at)}) tetap disimpan dan ditandai &quot;Digantikan&quot;. Snapshot baru dihitung
            dari data hari ini.
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-1">
          <Label htmlFor={`reason-${snapshot.id}`}>Alasan (wajib)</Label>
          <Textarea
            id={`reason-${snapshot.id}`}
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            rows={3}
            aria-invalid={error ? true : undefined}
            aria-describedby={error ? `reason-err-${snapshot.id}` : undefined}
          />
          {error ? (
            <p id={`reason-err-${snapshot.id}`} className="text-xs text-danger-fg" role="alert">
              {error}
            </p>
          ) : null}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>
            Batal
          </Button>
          <Button onClick={submit} loading={pending}>
            Bekukan ulang
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function SemesterDialog({ semester }: { semester: Semester }) {
  const [open, setOpen] = useState(false);
  const initial = () => ({ start: semester.start_date, end: semester.end_date, cutoff: semester.cutoff_date });
  const [v, setV] = useState(initial);
  // L-14: reopen with the current (possibly refreshed) values, not a cancelled edit.
  const onOpenChange = (next: boolean) => {
    if (next) setV(initial());
    setOpen(next);
  };
  const { pending, run } = useAction();
  const save = () =>
    run(
      () =>
        upsertSemester({
          id: semester.id,
          academic_year_id: semester.academic_year_id,
          term: semester.term,
          start_date: v.start,
          end_date: v.end,
          cutoff_date: v.cutoff,
        }),
      'Semester disimpan.',
      () => setOpen(false),
    );
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogTrigger asChild>
        <Button size="sm" variant="ghost" aria-label={`Ubah semester ${TERM_LABEL[semester.term]}`}>
          <Pencil aria-hidden="true" />
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Ubah semester {TERM_LABEL[semester.term]}</DialogTitle>
          <DialogDescription>Snapshot yang sudah dibekukan tidak berubah (R-56).</DialogDescription>
        </DialogHeader>
        <div className="grid gap-3 sm:grid-cols-3">
          {(
            [
              ['start', 'Mulai'],
              ['end', 'Selesai'],
              ['cutoff', 'Cutoff'],
            ] as const
          ).map(([k, l]) => (
            <div key={k} className="grid gap-1">
              <Label htmlFor={`sem-${semester.id}-${k}`}>{l}</Label>
              <Input id={`sem-${semester.id}-${k}`} type="date" value={v[k]} onChange={(e) => setV((p) => ({ ...p, [k]: e.target.value }))} />
            </div>
          ))}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>
            Batal
          </Button>
          <Button onClick={save} loading={pending}>
            Simpan
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function YearDialog({ year }: { year?: Year }) {
  const [open, setOpen] = useState(false);
  const initial = () => ({ label: year?.label ?? '', start: year?.start_date ?? '', end: year?.end_date ?? '' });
  const [v, setV] = useState(initial);
  // L-14: reopen with the current (possibly refreshed) values, not a cancelled edit.
  const onOpenChange = (next: boolean) => {
    if (next) setV(initial());
    setOpen(next);
  };
  const { pending, run } = useAction();
  const save = () =>
    run(
      () => upsertAcademicYear({ id: year?.id ?? null, label: v.label, start_date: v.start, end_date: v.end }),
      year ? 'Tahun akademik disimpan.' : 'Tahun akademik ditambahkan (semester dibuat otomatis).',
      () => setOpen(false),
    );
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogTrigger asChild>
        {year ? (
          <Button size="sm" variant="outline">
            <Pencil aria-hidden="true" />
            Ubah tahun
          </Button>
        ) : (
          <Button variant="outline">
            <Plus aria-hidden="true" />
            Tambah tahun akademik
          </Button>
        )}
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{year ? `Ubah ${year.label}` : 'Tambah tahun akademik'}</DialogTitle>
          <DialogDescription>
            {year ? 'Periode kegiatan dihitung ulang dari kalender.' : 'Semester Ganjil (6 bulan) dan Genap dibuat otomatis dengan cutoff akhir + 30 hari.'}
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-3 sm:grid-cols-3">
          <div className="grid gap-1">
            <Label htmlFor="ay-label">Label</Label>
            <Input id="ay-label" placeholder="2027/2028" value={v.label} onChange={(e) => setV((p) => ({ ...p, label: e.target.value }))} />
          </div>
          <div className="grid gap-1">
            <Label htmlFor="ay-start">Mulai</Label>
            <Input id="ay-start" type="date" value={v.start} onChange={(e) => setV((p) => ({ ...p, start: e.target.value }))} />
          </div>
          <div className="grid gap-1">
            <Label htmlFor="ay-end">Selesai</Label>
            <Input id="ay-end" type="date" value={v.end} onChange={(e) => setV((p) => ({ ...p, end: e.target.value }))} />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>
            Batal
          </Button>
          <Button onClick={save} loading={pending}>
            Simpan
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
