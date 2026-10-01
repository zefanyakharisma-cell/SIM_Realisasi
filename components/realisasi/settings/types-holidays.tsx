'use client';

import { useRouter } from 'next/navigation';
import { useMemo, useState, useTransition } from 'react';
import { Plus, Trash2 } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { NativeSelect } from '@/components/ui/native-select';
import { Switch } from '@/components/ui/switch';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { toast } from '@/components/ui/toaster';
import { deleteHoliday, upsertActivityType, upsertHoliday } from '@/lib/realisasi/actions/settings';
import { DIRECTION_LABEL } from '@/lib/realisasi/status';
import { formatDate } from '@/lib/realisasi/format';
import type { ActivityTypeInput } from '@/lib/realisasi/schemas/settings';

const NOTICE = 'Berlaku untuk perhitungan live; snapshot yang sudah dibekukan tidak berubah.';

interface TypeRow extends ActivityTypeInput {
  id: number;
}

type Flag = 'counts_as_mobility' | 'counts_for_s1' | 'requires_mobility_review' | 'is_active';
const FLAGS: Array<{ key: Flag; label: string }> = [
  { key: 'counts_as_mobility', label: 'Dihitung mobilitas (1.1)' },
  { key: 'counts_for_s1', label: 'Dihitung 1.19.S1' },
  { key: 'requires_mobility_review', label: 'Wajib verifikasi mobilitas' },
  { key: 'is_active', label: 'Aktif' },
];

export function ActivityTypesManager({ types }: { types: TypeRow[] }) {
  const router = useRouter();
  const [rows, setRows] = useState(types);
  const [pending, start] = useTransition();
  const [draft, setDraft] = useState<ActivityTypeInput>({
    name: '',
    direction: 'none',
    counts_as_mobility: false,
    counts_for_s1: true,
    requires_mobility_review: false,
    is_active: true,
    sort_order: (types.at(-1)?.sort_order ?? 0) + 1,
  });

  const save = (id: number | null, data: ActivityTypeInput, ok: string, after?: () => void) =>
    start(async () => {
      const res = await upsertActivityType(id, data);
      if (res.ok) {
        toast.success(ok, { description: NOTICE });
        after?.();
        router.refresh();
      } else {
        toast.error(res.message);
        setRows(types);
      }
    });

  const toggle = (row: TypeRow, flag: Flag, value: boolean) => {
    const next = { ...row, [flag]: value };
    setRows((rs) => rs.map((r) => (r.id === row.id ? next : r)));
    const { id, ...data } = next;
    save(id, data, `Jenis "${row.name}" diperbarui.`);
  };

  return (
    <Card className="space-y-4 p-5">
      <p className="text-sm text-muted-foreground">
        Jenis kegiatan tidak dapat dihapus; nonaktifkan agar tidak dapat dipilih lagi. {NOTICE}
      </p>
      <Table containerLabel="Jenis kegiatan">
        <TableHeader>
          <TableRow>
            <TableHead>Jenis</TableHead>
            <TableHead>Arah</TableHead>
            {FLAGS.map((f) => (
              <TableHead key={f.key} className="text-center">
                {f.label}
              </TableHead>
            ))}
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((r) => (
            <TableRow key={r.id} className={r.is_active ? undefined : 'opacity-60'}>
              <TableCell className="font-medium">
                {r.name} {r.is_active ? null : <Badge variant="neutral">Nonaktif</Badge>}
              </TableCell>
              <TableCell>{DIRECTION_LABEL[r.direction]}</TableCell>
              {FLAGS.map((f) => (
                <TableCell key={f.key} className="text-center">
                  <Switch
                    checked={r[f.key]}
                    disabled={pending}
                    aria-label={`${f.label}: ${r.name}`}
                    onCheckedChange={(v) => toggle(r, f.key, v)}
                  />
                </TableCell>
              ))}
            </TableRow>
          ))}
        </TableBody>
      </Table>
      <form
        className="flex flex-wrap items-end gap-3 border-t pt-4"
        onSubmit={(e) => {
          e.preventDefault();
          if (draft.name.trim().length < 3) {
            toast.error('Nama jenis minimal 3 karakter.');
            return;
          }
          save(null, draft, 'Jenis kegiatan ditambahkan.', () => setDraft((d) => ({ ...d, name: '', sort_order: d.sort_order + 1 })));
        }}
      >
        <div className="grid gap-1">
          <Label htmlFor="type-name">Jenis baru</Label>
          <Input id="type-name" value={draft.name} onChange={(e) => setDraft((d) => ({ ...d, name: e.target.value }))} className="w-64" />
        </div>
        <div className="grid gap-1">
          <Label htmlFor="type-dir">Arah</Label>
          <NativeSelect
            id="type-dir"
            value={draft.direction}
            onChange={(e) => setDraft((d) => ({ ...d, direction: e.target.value as ActivityTypeInput['direction'] }))}
          >
            {Object.entries(DIRECTION_LABEL).map(([k, v]) => (
              <option key={k} value={k}>
                {v}
              </option>
            ))}
          </NativeSelect>
        </div>
        <Button type="submit" variant="outline" disabled={pending}>
          <Plus aria-hidden="true" />
          Tambah jenis
        </Button>
      </form>
    </Card>
  );
}

export function HolidaysManager({ holidays }: { holidays: Array<{ day: string; name: string }> }) {
  const router = useRouter();
  const years = useMemo(() => [...new Set(holidays.map((h) => h.day.slice(0, 4)))].sort(), [holidays]);
  const [year, setYear] = useState(() => (years.includes('2026') ? '2026' : (years.at(-1) ?? '')));
  const [day, setDay] = useState('');
  const [name, setName] = useState('');
  const [pending, start] = useTransition();
  const shown = holidays.filter((h) => !year || h.day.startsWith(year));

  const act = (fn: () => Promise<{ ok: boolean; message?: string }>, ok: string, after?: () => void) =>
    start(async () => {
      const res = await fn();
      if (res.ok) {
        toast.success(ok, { description: 'SLA hari kerja dihitung ulang untuk perhitungan live.' });
        after?.();
        router.refresh();
      } else toast.error(('message' in res && res.message) || 'Gagal.');
    });

  return (
    <Card className="space-y-4 p-5">
      <div className="flex flex-wrap items-end gap-3">
        <div className="grid gap-1">
          <Label htmlFor="hol-year">Tahun</Label>
          <NativeSelect id="hol-year" value={year} onChange={(e) => setYear(e.target.value)} className="w-28">
            <option value="">Semua</option>
            {years.map((y) => (
              <option key={y} value={y}>
                {y}
              </option>
            ))}
          </NativeSelect>
        </div>
        <form
          className="flex flex-wrap items-end gap-3"
          onSubmit={(e) => {
            e.preventDefault();
            if (!day || name.trim().length < 2) {
              toast.error('Tanggal dan nama hari libur wajib diisi.');
              return;
            }
            act(() => upsertHoliday({ day, name: name.trim() }), 'Hari libur disimpan.', () => {
              setDay('');
              setName('');
            });
          }}
        >
          <div className="grid gap-1">
            <Label htmlFor="hol-day">Tanggal</Label>
            <Input id="hol-day" type="date" value={day} onChange={(e) => setDay(e.target.value)} className="w-40" />
          </div>
          <div className="grid gap-1">
            <Label htmlFor="hol-name">Nama</Label>
            <Input id="hol-name" value={name} onChange={(e) => setName(e.target.value)} className="w-64" />
          </div>
          <Button type="submit" variant="outline" disabled={pending}>
            <Plus aria-hidden="true" />
            Tambah / perbarui
          </Button>
        </form>
      </div>
      {shown.length === 0 ? (
        <p className="text-sm text-muted-foreground">Belum ada hari libur.</p>
      ) : (
        <Table containerLabel="Hari libur">
          <TableHeader>
            <TableRow>
              <TableHead>Tanggal</TableHead>
              <TableHead>Nama</TableHead>
              <TableHead className="text-right">Aksi</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {shown.map((h) => (
              <TableRow key={h.day}>
                <TableCell className="whitespace-nowrap">{formatDate(h.day)}</TableCell>
                <TableCell>{h.name}</TableCell>
                <TableCell className="text-right">
                  <Button
                    size="sm"
                    variant="ghost"
                    disabled={pending}
                    aria-label={`Hapus ${h.name} (${formatDate(h.day)})`}
                    onClick={() => act(() => deleteHoliday(h.day), 'Hari libur dihapus.')}
                  >
                    <Trash2 aria-hidden="true" />
                  </Button>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
    </Card>
  );
}
