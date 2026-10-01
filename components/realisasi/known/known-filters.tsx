'use client';

import { useEffect, useState, useTransition } from 'react';
import { usePathname, useRouter } from 'next/navigation';
import { FilterX } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { NativeSelect } from '@/components/ui/native-select';
import { KNOWN_STATUSES, knownFiltersToSearchParams, type KnownFilters } from '@/lib/realisasi/schemas/known';
import { KNOWN_STATUS_LABEL } from '@/lib/realisasi/status';

/** URL-backed filters for the register (`?status=unmatched` is linked from the S8 dashboard card). */
export function KnownFilterBar({ filters, units }: { filters: KnownFilters; units: Array<{ id: number; label: string }> }) {
  const router = useRouter();
  const pathname = usePathname();
  const [pending, startTransition] = useTransition();
  const [q, setQ] = useState(filters.q ?? '');

  useEffect(() => setQ(filters.q ?? ''), [filters.q]);

  function apply(patch: Partial<KnownFilters>) {
    const next: KnownFilters = { ...filters, ...patch };
    for (const k of Object.keys(patch) as Array<keyof KnownFilters>) if (patch[k] === undefined) delete next[k];
    const qs = knownFiltersToSearchParams(next).toString();
    startTransition(() => router.replace(qs ? `${pathname}?${qs}` : pathname, { scroll: false }));
  }

  const hasFilters = Object.keys(filters).length > 0;

  return (
    <form
      role="search"
      aria-label="Filter register"
      aria-busy={pending || undefined}
      className="grid gap-3 rounded-lg border bg-card p-3 sm:grid-cols-2 lg:grid-cols-6"
      onSubmit={(e) => {
        e.preventDefault();
        apply({ q: q.trim() || undefined });
      }}
    >
      <div className="space-y-1 lg:col-span-2">
        <label htmlFor="known-q" className="text-xs font-medium text-muted-foreground">
          Cari judul / mitra / referensi
        </label>
        <Input id="known-q" type="search" value={q} onChange={(e) => setQ(e.target.value)} onBlur={() => q.trim() !== (filters.q ?? '') && apply({ q: q.trim() || undefined })} />
      </div>
      <div className="space-y-1">
        <label htmlFor="known-status" className="text-xs font-medium text-muted-foreground">
          Status
        </label>
        <NativeSelect id="known-status" value={filters.status ?? ''} onChange={(e) => apply({ status: (e.target.value || undefined) as KnownFilters['status'] })}>
          <option value="">Semua status</option>
          {KNOWN_STATUSES.map((s) => (
            <option key={s} value={s}>
              {KNOWN_STATUS_LABEL[s]}
            </option>
          ))}
        </NativeSelect>
      </div>
      <div className="space-y-1">
        <label htmlFor="known-unit" className="text-xs font-medium text-muted-foreground">
          Unit
        </label>
        <NativeSelect id="known-unit" value={filters.unit_id ?? ''} onChange={(e) => apply({ unit_id: e.target.value ? Number(e.target.value) : undefined })}>
          <option value="">Semua unit</option>
          {units.map((u) => (
            <option key={u.id} value={u.id}>
              {u.label}
            </option>
          ))}
        </NativeSelect>
      </div>
      <div className="space-y-1">
        <label htmlFor="known-intl" className="text-xs font-medium text-muted-foreground">
          Cakupan
        </label>
        <NativeSelect
          id="known-intl"
          value={filters.intl === undefined ? '' : filters.intl ? '1' : '0'}
          onChange={(e) => apply({ intl: e.target.value === '' ? undefined : e.target.value === '1' })}
        >
          <option value="">Semua</option>
          <option value="1">Internasional</option>
          <option value="0">Domestik</option>
        </NativeSelect>
      </div>
      <div className="grid grid-cols-2 gap-2">
        <div className="space-y-1">
          <label htmlFor="known-from" className="text-xs font-medium text-muted-foreground">
            Dari
          </label>
          <Input id="known-from" type="date" value={filters.from ?? ''} onChange={(e) => apply({ from: e.target.value || undefined })} />
        </div>
        <div className="space-y-1">
          <label htmlFor="known-to" className="text-xs font-medium text-muted-foreground">
            Sampai
          </label>
          <Input id="known-to" type="date" value={filters.to ?? ''} onChange={(e) => apply({ to: e.target.value || undefined })} />
        </div>
      </div>
      {hasFilters ? (
        <div className="lg:col-span-6">
          <Button type="button" variant="ghost" size="sm" onClick={() => startTransition(() => router.replace(pathname, { scroll: false }))}>
            <FilterX aria-hidden="true" />
            Hapus filter
          </Button>
        </div>
      ) : null}
    </form>
  );
}
