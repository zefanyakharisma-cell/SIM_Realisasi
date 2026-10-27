'use client';
/**
 * Jenis Kegiatan master (IO list "AGENDA - SIM REALISASI"): IO Admin adds, edits and deactivates types (never
 * deletes them). The program decides the participant rule — Student Mobility (students + mobility PDF, RENSTRA
 * 1.1, International Awards category), Faculty Mobility (PETRA staff outbound / external person inbound), both
 * verified by the Mobility team; "Lainnya" is recorded on submit. The 1.19.S1 flag is per type.
 */
import { useEffect, useMemo, useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { Pencil, Plus } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { NativeSelect } from '@/components/ui/native-select';
import { Switch } from '@/components/ui/switch';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Textarea } from '@/components/ui/textarea';
import { toast } from '@/components/ui/toaster';
import { saveAgenda } from '@/lib/realisasi/actions/settings';
import type { AgendaRow } from '@/lib/realisasi/queries/reports';
import { AGENDA_PROGRAMS, MOBILITY_CATEGORIES } from '@/lib/realisasi/schemas/settings';
import { AGENDA_PROGRAM_LABEL, MOBILITY_CATEGORY_LABEL, agendaRequirement } from '@/lib/realisasi/status';
import type { AgendaProgram, MobilityCategory } from '@/lib/realisasi/types';

const NOTICE = 'Berlaku untuk pengajuan baru dan perhitungan live; snapshot yang sudah dibekukan tidak berubah.';

type Draft = Omit<AgendaRow, 'id' | 'activities'> & { id: number | null };

function toInput(r: Draft) {
  return {
    id: r.id,
    name: r.name,
    program: r.program,
    description: r.description?.trim() ? r.description : null,
    mobility_category: r.program === 'student_mobility' ? r.mobility_category : null,
    counts_for_s1: r.counts_for_s1,
    sort_order: r.sort_order,
    is_active: r.is_active,
  };
}

function useSave() {
  const router = useRouter();
  const [pending, start] = useTransition();
  const save = (r: Draft, success: string, onOk?: () => void, onFail?: () => void) =>
    start(async () => {
      const res = await saveAgenda(toInput(r));
      if (res.ok) {
        toast.success(success, { description: NOTICE });
        onOk?.();
        router.refresh();
      } else {
        toast.error(res.message);
        onFail?.();
      }
    });
  return { pending, save };
}

export function AgendaManager({ agendas }: { agendas: AgendaRow[] }) {
  const [rows, setRows] = useState(agendas);
  const [q, setQ] = useState('');
  const { pending, save } = useSave();
  // router.refresh() after a save brings the server's list (new rows included)
  useEffect(() => setRows(agendas), [agendas]);

  const groups = useMemo(() => {
    const needle = q.trim().toLowerCase();
    const shown = needle
      ? rows.filter((r) => r.name.toLowerCase().includes(needle) || (r.description ?? '').toLowerCase().includes(needle))
      : rows;
    return AGENDA_PROGRAMS.map((p) => ({ program: p, rows: shown.filter((r) => r.program === p) })).filter((g) => g.rows.length > 0);
  }, [rows, q]);

  // inline toggles: optimistic, rolled back on error
  function toggle(next: AgendaRow) {
    const before = rows;
    setRows((rs) => rs.map((r) => (r.id === next.id ? next : r)));
    save(next, `"${next.name}" disimpan.`, undefined, () => setRows(before));
  }

  const nextOrder = rows.reduce((m, r) => Math.max(m, r.sort_order), 0) + 1;

  return (
    <Card className="space-y-4 p-4" data-testid="agenda-rules">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="space-y-1">
          <h2 className="text-base font-semibold">Jenis Kegiatan</h2>
          <p className="max-w-3xl text-sm text-muted-foreground">
            Daftar Jenis Kegiatan yang dipilih unit saat mengajukan kegiatan. Program menentukan data wajib: Student Mobility mengisi peserta
            mahasiswa dan PDF transkrip/poster/dokumentasi, Faculty Mobility mengisi dosen/staf PETRA (outbound) atau tamu eksternal (inbound);
            keduanya diverifikasi tim Mobilitas. Jenis yang dinonaktifkan tidak bisa dipilih untuk kegiatan baru.
          </p>
        </div>
        <AgendaDialog
          initial={{
            id: null,
            name: '',
            program: 'faculty_mobility',
            description: null,
            mobility_category: null,
            counts_for_s1: true,
            sort_order: nextOrder,
            is_active: true,
          }}
        />
      </div>
      <div className="max-w-sm">
        <label htmlFor="agenda-q" className="sr-only">
          Cari jenis kegiatan
        </label>
        <Input id="agenda-q" type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Cari jenis kegiatan…" />
      </div>
      {groups.map((g) => (
        <section key={g.program} className="space-y-2" aria-labelledby={`agenda-group-${g.program}`}>
          <div>
            <h3 id={`agenda-group-${g.program}`} className="text-sm font-semibold">
              {AGENDA_PROGRAM_LABEL[g.program]}
            </h3>
            <p className="text-xs text-muted-foreground">{agendaRequirement(g.program)}</p>
          </div>
          <Table containerLabel={`Jenis kegiatan ${AGENDA_PROGRAM_LABEL[g.program]}`}>
            <TableHeader>
              <TableRow>
                <TableHead>Jenis Kegiatan</TableHead>
                {g.program === 'student_mobility' ? <TableHead>Kategori International Awards</TableHead> : null}
                <TableHead>Dihitung 1.19.S1</TableHead>
                <TableHead>Aktif</TableHead>
                <TableHead className="text-right">Kegiatan</TableHead>
                <TableHead>
                  <span className="sr-only">Ubah</span>
                </TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {g.rows.map((r) => (
                <TableRow key={r.id} data-testid="agenda-rule-row">
                  <TableCell className="max-w-xl">
                    <span className="font-medium">{r.name}</span>
                    {!r.is_active ? (
                      <Badge variant="neutral" className="ml-2">
                        Nonaktif
                      </Badge>
                    ) : null}
                    {r.description ? <p className="mt-0.5 text-xs text-muted-foreground">{r.description}</p> : null}
                  </TableCell>
                  {g.program === 'student_mobility' ? (
                    <TableCell className="whitespace-nowrap text-sm">
                      {r.mobility_category ? MOBILITY_CATEGORY_LABEL[r.mobility_category] : '—'}
                    </TableCell>
                  ) : null}
                  <TableCell>
                    <Switch
                      checked={r.counts_for_s1}
                      disabled={pending}
                      onCheckedChange={(v) => toggle({ ...r, counts_for_s1: v })}
                      aria-label={`${r.name} dihitung 1.19.S1`}
                    />
                  </TableCell>
                  <TableCell>
                    <Switch
                      checked={r.is_active}
                      disabled={pending}
                      onCheckedChange={(v) => toggle({ ...r, is_active: v })}
                      aria-label={`${r.name} aktif`}
                    />
                  </TableCell>
                  <TableCell className="text-right tabular-nums">{r.activities}</TableCell>
                  <TableCell className="text-right">
                    <AgendaDialog initial={r} />
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </section>
      ))}
      {groups.length === 0 ? <p className="text-sm text-muted-foreground">Tidak ada jenis kegiatan yang cocok.</p> : null}
    </Card>
  );
}

function AgendaDialog({ initial }: { initial: Draft }) {
  const isNew = initial.id === null;
  const [open, setOpen] = useState(false);
  const [v, setV] = useState<Draft>(initial);
  const [error, setError] = useState<string | null>(null);
  const { pending, save } = useSave();
  const key = initial.id ?? 'new';

  // reopen with the current (possibly refreshed) values, not a cancelled edit
  const onOpenChange = (next: boolean) => {
    if (next) {
      setV(initial);
      setError(null);
    }
    setOpen(next);
  };
  const set = <K extends keyof Draft>(k: K, val: Draft[K]) => setV((p) => ({ ...p, [k]: val }));

  const submit = () => {
    if (!v.name.trim()) return setError('Nama jenis kegiatan wajib diisi.');
    if (v.program === 'student_mobility' && !v.mobility_category) return setError('Pilih kategori International Awards untuk Student Mobility.');
    setError(null);
    save(v, isNew ? `Jenis kegiatan "${v.name.trim()}" ditambahkan.` : `"${v.name.trim()}" disimpan.`, () => setOpen(false));
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogTrigger asChild>
        {isNew ? (
          <Button size="sm" data-testid="agenda-add">
            <Plus aria-hidden="true" />
            Tambah jenis kegiatan
          </Button>
        ) : (
          <Button size="sm" variant="ghost" aria-label={`Ubah ${initial.name}`}>
            <Pencil aria-hidden="true" />
          </Button>
        )}
      </DialogTrigger>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>{isNew ? 'Tambah jenis kegiatan' : `Ubah ${initial.name}`}</DialogTitle>
          <DialogDescription>{NOTICE}</DialogDescription>
        </DialogHeader>
        <div className="grid gap-3">
          <div className="grid gap-1">
            <Label htmlFor={`ag-${key}-name`}>Nama</Label>
            <Input id={`ag-${key}-name`} value={v.name} onChange={(e) => set('name', e.target.value)} maxLength={200} />
          </div>
          <div className="grid gap-1">
            <Label htmlFor={`ag-${key}-program`}>Program</Label>
            <NativeSelect
              id={`ag-${key}-program`}
              value={v.program}
              onChange={(e) => {
                const program = e.target.value as AgendaProgram;
                setV((p) => ({ ...p, program, mobility_category: program === 'student_mobility' ? p.mobility_category : null }));
              }}
            >
              {AGENDA_PROGRAMS.map((p) => (
                <option key={p} value={p}>
                  {AGENDA_PROGRAM_LABEL[p]}
                </option>
              ))}
            </NativeSelect>
            <p className="text-xs text-muted-foreground">{agendaRequirement(v.program)}</p>
          </div>
          {v.program === 'student_mobility' ? (
            <div className="grid gap-1">
              <Label htmlFor={`ag-${key}-cat`}>Kategori International Awards</Label>
              <NativeSelect
                id={`ag-${key}-cat`}
                value={v.mobility_category ?? ''}
                onChange={(e) => set('mobility_category', (e.target.value || null) as MobilityCategory | null)}
              >
                <option value="">Pilih kategori</option>
                {MOBILITY_CATEGORIES.map((c) => (
                  <option key={c} value={c}>
                    {MOBILITY_CATEGORY_LABEL[c]}
                  </option>
                ))}
              </NativeSelect>
            </div>
          ) : null}
          <div className="grid gap-1">
            <Label htmlFor={`ag-${key}-desc`}>Keterangan</Label>
            <Textarea id={`ag-${key}-desc`} rows={3} value={v.description ?? ''} onChange={(e) => set('description', e.target.value)} />
          </div>
          <div className="grid grid-cols-3 items-end gap-3">
            <div className="grid gap-1">
              <Label htmlFor={`ag-${key}-order`}>Urutan</Label>
              <Input
                id={`ag-${key}-order`}
                type="number"
                min={0}
                value={v.sort_order}
                onChange={(e) => set('sort_order', Math.max(0, Math.trunc(Number(e.target.value) || 0)))}
              />
            </div>
            <label className="flex items-center gap-2 text-sm">
              <Switch checked={v.counts_for_s1} onCheckedChange={(c) => set('counts_for_s1', c)} />
              Dihitung 1.19.S1
            </label>
            <label className="flex items-center gap-2 text-sm">
              <Switch checked={v.is_active} onCheckedChange={(c) => set('is_active', c)} />
              Aktif
            </label>
          </div>
          {error ? (
            <p className="text-xs text-red-700" role="alert">
              {error}
            </p>
          ) : null}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>
            Batal
          </Button>
          <Button onClick={submit} loading={pending}>
            Simpan
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
