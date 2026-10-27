'use client';
/**
 * Target RENSTRA: one target per unit, indicator and academic year, shown in the "Target" column of
 * Laporan per RENSTRA. 1.19.S4 has no per-unit table, so it takes one university-wide percentage.
 */
import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { NativeSelect } from '@/components/ui/native-select';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { toast } from '@/components/ui/toaster';
import { setRenstraTargets } from '@/lib/realisasi/actions/settings';
import { RENSTRA_DEF, RENSTRA_KEYS, renstraLabel, type RenstraKey } from '@/lib/realisasi/schemas/report';
import type { AcademicYearRow } from '@/lib/realisasi/queries/reports';
import { cn } from '@/lib/utils';

export interface TargetUnitRow {
  /** 0 = Universitas. */
  unit_id: number;
  name: string;
  level: string;
  depth: number;
}

const UNIT_SUFFIX: Record<string, string> = { mahasiswa: 'mahasiswa', kegiatan: 'kegiatan', persen: '%' };

export function RenstraTargetsManager({
  years,
  ay,
  renstra,
  units,
  initial,
}: {
  years: AcademicYearRow[];
  ay: number;
  renstra: RenstraKey;
  units: TargetUnitRow[];
  /** unit_id → target, as stored. */
  initial: Record<number, number>;
}) {
  const router = useRouter();
  const def = RENSTRA_DEF[renstra];
  const overallOnly = def.metric === null;
  const shown = overallOnly ? [{ unit_id: 0, name: 'Universitas', level: 'Universitas', depth: 0 }] : units;
  const toText = (id: number) => (initial[id] === undefined ? '' : String(initial[id]));
  const [values, setValues] = useState<Record<number, string>>(() => Object.fromEntries(shown.map((u) => [u.unit_id, toText(u.unit_id)])));
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  const changed = shown.filter((u) => (values[u.unit_id] ?? '').trim() !== toText(u.unit_id));

  const go = (next: { ay?: number; renstra?: RenstraKey }) => {
    const q = new URLSearchParams({ tab: 'target', ay: String(next.ay ?? ay), renstra: next.renstra ?? renstra });
    router.push(`/realisasi/pengaturan?${q.toString()}`);
  };

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    const rows: Array<{ unit_id: number; target: number | null }> = [];
    for (const u of changed) {
      const raw = (values[u.unit_id] ?? '').trim().replace(',', '.');
      const target = raw === '' ? null : Number(raw);
      if (target !== null && (!Number.isFinite(target) || target < 0 || (overallOnly && target > 100))) {
        setError(`Target ${u.name} tidak valid${overallOnly ? ' (0–100%)' : ''}.`);
        return;
      }
      rows.push({ unit_id: u.unit_id, target });
    }
    setError(null);
    start(async () => {
      const res = await setRenstraTargets({ academic_year_id: ay, renstra_key: renstra, rows });
      if (res.ok) {
        toast.success('Target disimpan.');
        router.refresh();
      } else {
        toast.error(res.message);
      }
    });
  };

  return (
    <Card className="space-y-4 p-4" data-testid="renstra-targets">
      <div className="space-y-1">
        <h2 className="text-base font-semibold">Target RENSTRA</h2>
        <p className="text-sm text-muted-foreground">
          Target per unit untuk setiap indikator dan tahun akademik, ditampilkan pada kolom Target di Laporan per RENSTRA. Kosongkan untuk
          menghapus target.
        </p>
      </div>
      <div className="flex flex-wrap items-end gap-3">
        <div className="grid gap-1">
          <Label htmlFor="t-ay" className="text-xs text-muted-foreground">
            Tahun Akademik
          </Label>
          <NativeSelect id="t-ay" value={String(ay)} onChange={(e) => go({ ay: Number(e.target.value) })} className="w-40">
            {years.map((y) => (
              <option key={y.id} value={y.id}>
                {y.label}
              </option>
            ))}
          </NativeSelect>
        </div>
        <div className="grid gap-1">
          <Label htmlFor="t-renstra" className="text-xs text-muted-foreground">
            Indikator RENSTRA
          </Label>
          <NativeSelect
            id="t-renstra"
            value={renstra}
            onChange={(e) => go({ renstra: e.target.value as RenstraKey })}
            className="w-[26rem] max-w-full"
          >
            {RENSTRA_KEYS.map((k) => (
              <option key={k} value={k}>
                {renstraLabel(k)}
              </option>
            ))}
          </NativeSelect>
        </div>
      </div>
      <form onSubmit={submit} noValidate className="space-y-4" aria-label="Target RENSTRA">
        <Table containerLabel="Target per unit">
          <TableHeader>
            <TableRow>
              <TableHead>Unit</TableHead>
              <TableHead>Tingkat</TableHead>
              <TableHead className="text-right">Target ({UNIT_SUFFIX[def.unit]})</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {shown.map((u) => {
              const id = `target-${u.unit_id}`;
              return (
                <TableRow key={u.unit_id} data-testid="target-row" data-unit-id={u.unit_id} className={cn(u.depth === 0 && 'bg-muted/40')}>
                  <TableCell className={cn(u.depth === 0 && 'font-semibold')} style={{ paddingLeft: `${0.75 + u.depth * 1.5}rem` }}>
                    <label htmlFor={id}>{u.name}</label>
                  </TableCell>
                  <TableCell className="text-sm text-muted-foreground">{u.level}</TableCell>
                  <TableCell className="text-right">
                    <Input
                      id={id}
                      type="number"
                      inputMode="decimal"
                      min={0}
                      max={overallOnly ? 100 : undefined}
                      step="any"
                      value={values[u.unit_id] ?? ''}
                      onChange={(e) => setValues((v) => ({ ...v, [u.unit_id]: e.target.value }))}
                      className="ml-auto w-28 text-right"
                    />
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
        {error ? (
          <p role="alert" className="text-sm text-red-700">
            {error}
          </p>
        ) : null}
        <div className="flex justify-end">
          <Button type="submit" loading={pending} disabled={changed.length === 0} data-testid="save-targets">
            Simpan target
          </Button>
        </div>
      </form>
    </Card>
  );
}
