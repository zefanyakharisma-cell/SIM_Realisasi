// GET filter forms for the Laporan page (server-rendered, no client JS needed).
// Field names = URL keys the export parsers read, so "Unduh Excel" uses exactly the same filters (AT-12).
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { NativeSelect } from '@/components/ui/native-select';
import { ACTIVITY_STATUS_LABEL, KNOWN_STATUS_LABEL } from '@/lib/realisasi/status';
import type { ActivityListFilters } from '@/lib/realisasi/schemas/filters';
import type { KnownFilters } from '@/lib/realisasi/schemas/known';
import type { ActivityStatus } from '@/lib/realisasi/types';

type Opt = { id: number; name: string };

function Field({ id, label, children }: { id: string; label: string; children: React.ReactNode }) {
  return (
    <div className="grid gap-1">
      <Label htmlFor={id} className="text-xs text-muted-foreground">
        {label}
      </Label>
      {children}
    </div>
  );
}

export function ActivityFilterForm({
  report,
  filters,
  types,
  units,
  years,
  extra,
}: {
  report: string;
  filters: ActivityListFilters;
  types: Opt[];
  units: Opt[] | null;
  years: Array<{ id: number; label: string }>;
  extra?: React.ReactNode;
}) {
  const status = filters.status?.length === 1 ? filters.status[0] : '';
  return (
    <form method="get" action="/realisasi/laporan" className="flex flex-wrap items-end gap-3" aria-label="Filter kegiatan">
      <input type="hidden" name="report" value={report} />
      <Field id="f-q" label="Cari (kode/nama)">
        <Input id="f-q" name="q" defaultValue={filters.q ?? ''} className="w-48" />
      </Field>
      <Field id="f-status" label="Status">
        <NativeSelect id="f-status" name="status" defaultValue={status ?? ''} className="w-44">
          <option value="">Semua status</option>
          {(Object.keys(ACTIVITY_STATUS_LABEL) as ActivityStatus[]).map((s) => (
            <option key={s} value={s}>
              {ACTIVITY_STATUS_LABEL[s]}
            </option>
          ))}
        </NativeSelect>
      </Field>
      <Field id="f-ay" label="Tahun Akademik">
        <NativeSelect id="f-ay" name="ay" defaultValue={filters.ay ? String(filters.ay) : ''} className="w-36">
          <option value="">Semua</option>
          {years.map((y) => (
            <option key={y.id} value={y.id}>
              {y.label}
            </option>
          ))}
        </NativeSelect>
      </Field>
      <Field id="f-type" label="Jenis Kegiatan">
        <NativeSelect id="f-type" name="type_id" defaultValue={filters.type_id ? String(filters.type_id) : ''} className="w-56">
          <option value="">Semua jenis</option>
          {types.map((t) => (
            <option key={t.id} value={t.id}>
              {t.name}
            </option>
          ))}
        </NativeSelect>
      </Field>
      {units ? (
        <Field id="f-unit" label="Unit">
          <NativeSelect id="f-unit" name="unit_id" defaultValue={filters.unit_id ? String(filters.unit_id) : ''} className="w-56">
            <option value="">Semua unit</option>
            {units.map((u) => (
              <option key={u.id} value={u.id}>
                {u.name}
              </option>
            ))}
          </NativeSelect>
        </Field>
      ) : null}
      {extra}
      <Button type="submit" variant="secondary">
        Terapkan
      </Button>
    </form>
  );
}

export function KnownFilterForm({ filters, units }: { filters: KnownFilters; units: Opt[] }) {
  return (
    <form method="get" action="/realisasi/laporan" className="flex flex-wrap items-end gap-3" aria-label="Filter register">
      <input type="hidden" name="report" value="register" />
      <Field id="k-q" label="Cari judul">
        <Input id="k-q" name="q" defaultValue={filters.q ?? ''} className="w-48" />
      </Field>
      <Field id="k-status" label="Status">
        <NativeSelect id="k-status" name="status" defaultValue={filters.status ?? ''} className="w-44">
          <option value="">Semua status</option>
          {Object.entries(KNOWN_STATUS_LABEL).map(([k, v]) => (
            <option key={k} value={k}>
              {v}
            </option>
          ))}
        </NativeSelect>
      </Field>
      <Field id="k-unit" label="Unit">
        <NativeSelect id="k-unit" name="unit_id" defaultValue={filters.unit_id ? String(filters.unit_id) : ''} className="w-56">
          <option value="">Semua unit</option>
          {units.map((u) => (
            <option key={u.id} value={u.id}>
              {u.name}
            </option>
          ))}
        </NativeSelect>
      </Field>
      <Field id="k-from" label="Dari">
        <Input id="k-from" type="date" name="from" defaultValue={filters.from ?? ''} className="w-40" />
      </Field>
      <Field id="k-to" label="Sampai">
        <Input id="k-to" type="date" name="to" defaultValue={filters.to ?? ''} className="w-40" />
      </Field>
      <Button type="submit" variant="secondary">
        Terapkan
      </Button>
    </form>
  );
}
