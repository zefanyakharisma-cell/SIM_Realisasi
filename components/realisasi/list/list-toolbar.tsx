'use client';

import { FilterX } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { NativeSelect } from '@/components/ui/native-select';
import { useFilterNavigation } from '@/components/realisasi/list/column-filters';
import {
  PRESETS,
  PRESET_LABEL,
  SORTS,
  SORT_LABEL,
  hasActiveFilters,
  type ActivityListFilters,
} from '@/lib/realisasi/schemas/filters';
import { cn } from '@/lib/utils';

export interface ListToolbarProps {
  filters: ActivityListFilters;
  /** Presets offered to this role (viewers have nothing to act on → no "Perlu tindakan saya"). */
  presets?: ReadonlyArray<NonNullable<ActivityListFilters['preset']>>;
  total: number;
  limited?: boolean;
}

/**
 * Quick filter chip (Revisi V.1: only "Perlu tindakan saya" = what awaits my action/approval), sort order,
 * "Hapus filter" and the live row counter (`list-total`, used by AT-12).
 */
export function ListToolbar({ filters, presets = PRESETS, total, limited }: ListToolbarProps) {
  const { apply, pending } = useFilterNavigation(filters);
  const active = hasActiveFilters(filters);

  return (
    <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
      <div className="flex flex-wrap items-center gap-2" role="group" aria-label="Filter cepat">
        {presets.map((p) => {
          const on = filters.preset === p;
          return (
            <button
              key={p}
              type="button"
              aria-pressed={on}
              data-testid={`preset-${p}`}
              onClick={() => apply({ preset: on ? undefined : p })}
              className={cn(
                'inline-flex min-h-8 items-center rounded-full border px-3 text-xs font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2',
                on ? 'border-primary bg-primary text-primary-foreground' : 'border-input bg-background hover:bg-muted',
              )}
            >
              {on ? <span aria-hidden="true">✓&nbsp;</span> : null}
              {PRESET_LABEL[p]}
            </button>
          );
        })}
        {active ? (
          <Button type="button" variant="ghost" size="sm" onClick={() => apply(clearAll(filters))} data-testid="filters-reset">
            <FilterX aria-hidden="true" />
            Hapus filter
          </Button>
        ) : null}
      </div>
      <div className="flex flex-wrap items-center gap-3 text-sm">
        <p aria-live="polite" aria-busy={pending || undefined} className="text-muted-foreground">
          <span data-testid="list-total" className="font-semibold text-foreground">
            {total}
          </span>{' '}
          kegiatan{limited ? ' (dibatasi 2000 baris — persempit filter)' : ''}
          {pending ? ' · memuat…' : ''}
        </p>
        <div className="flex items-center gap-2">
          <label htmlFor="list-sort" className="text-muted-foreground">
            Urutkan
          </label>
          <NativeSelect
            id="list-sort"
            value={filters.sort ?? 'start_desc'}
            onChange={(e) => {
              const v = e.target.value as NonNullable<ActivityListFilters['sort']>;
              apply({ sort: v === 'start_desc' ? undefined : v });
            }}
            className="w-48"
          >
            {SORTS.map((s) => (
              <option key={s} value={s}>
                {SORT_LABEL[s]}
              </option>
            ))}
          </NativeSelect>
        </div>
      </div>
    </div>
  );
}

function clearAll(f: ActivityListFilters): Partial<ActivityListFilters> {
  const patch: Partial<ActivityListFilters> = {};
  for (const k of Object.keys(f) as Array<keyof ActivityListFilters>) {
    if (k !== 'sort' && k !== 'queue') patch[k] = undefined;
  }
  return patch;
}
