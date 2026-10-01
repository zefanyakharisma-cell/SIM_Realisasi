'use client';

import { useEffect, useRef, useState, useTransition } from 'react';
import { usePathname, useRouter } from 'next/navigation';
import { Input } from '@/components/ui/input';
import { NativeSelect } from '@/components/ui/native-select';
import {
  ACTIVITY_STATUSES,
  TRACK_STATUSES,
  activityFiltersToSearchParams,
  type ActivityListFilters,
} from '@/lib/realisasi/schemas/filters';
import { ACTIVITY_STATUS_LABEL, TRACK_STATUS_LABEL } from '@/lib/realisasi/status';
import type { ActivityFilterOptions } from '@/lib/realisasi/queries/activities';

/** Navigates to the list with new filters (replace, no scroll), reporting pending state. */
export function useFilterNavigation(filters: ActivityListFilters) {
  const router = useRouter();
  const pathname = usePathname();
  const [pending, startTransition] = useTransition();
  function apply(patch: Partial<ActivityListFilters>) {
    const next: ActivityListFilters = { ...filters, ...patch };
    for (const k of Object.keys(patch) as Array<keyof ActivityListFilters>) {
      if (patch[k] === undefined) delete next[k];
    }
    const qs = activityFiltersToSearchParams(next).toString();
    startTransition(() => router.replace(qs ? `${pathname}?${qs}` : pathname, { scroll: false }));
  }
  return { apply, pending };
}

const cellClass = 'px-2 pb-2 pt-1 align-top';
const numOrUndef = (v: string) => (v === '' ? undefined : Number(v));

/**
 * Per-column filter row rendered inside the Kegiatan table head (Design §3.2: "per-column
 * filters"). Every control is labelled; values live in the URL so the export link and a page
 * reload see the same filters (AT-12).
 */
export function ColumnFilterRow({ filters, options }: { filters: ActivityListFilters; options: ActivityFilterOptions }) {
  const { apply, pending } = useFilterNavigation(filters);
  const [q, setQ] = useState(filters.q ?? '');
  const lastApplied = useRef(filters.q ?? '');

  // Keep the box in sync when the URL changes elsewhere (preset chips, "Hapus filter", back button).
  useEffect(() => {
    const external = filters.q ?? '';
    if (external !== lastApplied.current) {
      lastApplied.current = external;
      setQ(external);
    }
  }, [filters.q]);

  // Debounced free-text search (Kode / Nama / Mitra / No. dokumen).
  useEffect(() => {
    const value = q.trim();
    if (value === lastApplied.current) return;
    const t = setTimeout(() => {
      lastApplied.current = value;
      apply({ q: value || undefined });
    }, 400);
    return () => clearTimeout(t);
    // `apply` is recreated each render; only the typed value should re-arm the timer.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [q]);

  const statusValue = filters.status?.length === 1 ? filters.status[0] : filters.status?.length ? '__multi' : '';
  const periodValue = filters.semester !== undefined ? `sem:${filters.semester}` : filters.ay !== undefined ? `ay:${filters.ay}` : '';
  const flagValue = filters.late ? 'late' : filters.sla ? `sla:${filters.sla}` : '';

  return (
    <tr className="border-b bg-muted/30" aria-busy={pending || undefined} data-testid="column-filters">
      <td className={cellClass} colSpan={2}>
        <label htmlFor="flt-q" className="sr-only">
          Cari kode, nama, mitra, atau nomor dokumen
        </label>
        <Input
          id="flt-q"
          type="search"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              lastApplied.current = q.trim();
              apply({ q: q.trim() || undefined });
            }
          }}
          placeholder="Cari kode / nama / mitra…"
          className="h-8 text-xs"
        />
      </td>
      <td className={cellClass}>
        <label htmlFor="flt-type" className="sr-only">
          Filter Jenis Kegiatan
        </label>
        <NativeSelect
          id="flt-type"
          value={filters.type_id ?? ''}
          onChange={(e) => apply({ type_id: numOrUndef(e.target.value) })}
          className="[&_select]:h-8 [&_select]:text-xs"
        >
          <option value="">Semua jenis</option>
          {options.types.map((t) => (
            <option key={t.id} value={t.id}>
              {t.label}
            </option>
          ))}
        </NativeSelect>
      </td>
      <td className={cellClass}>
        <label htmlFor="flt-unit" className="sr-only">
          Filter Unit
        </label>
        <NativeSelect
          id="flt-unit"
          value={filters.unit_id ?? ''}
          onChange={(e) => apply({ unit_id: numOrUndef(e.target.value) })}
          className="[&_select]:h-8 [&_select]:text-xs"
        >
          <option value="">Semua unit</option>
          {options.units.map((u) => (
            <option key={u.id} value={u.id}>
              {u.label}
            </option>
          ))}
        </NativeSelect>
      </td>
      <td className={cellClass}>
        <label htmlFor="flt-country" className="sr-only">
          Filter Negara Mitra
        </label>
        <NativeSelect
          id="flt-country"
          value={filters.country ?? ''}
          onChange={(e) => apply({ country: e.target.value || undefined })}
          className="[&_select]:h-8 [&_select]:text-xs"
        >
          <option value="">Semua negara</option>
          {options.countries.map((c) => (
            <option key={c.code} value={c.code}>
              {c.name}
            </option>
          ))}
        </NativeSelect>
      </td>
      <td className={cellClass}>
        <div className="flex flex-col gap-1">
          <label htmlFor="flt-from" className="sr-only">
            Tanggal mulai dari
          </label>
          <Input
            id="flt-from"
            type="date"
            value={filters.from ?? ''}
            max={filters.to}
            onChange={(e) => apply({ from: e.target.value || undefined })}
            className="h-8 text-xs"
          />
          <label htmlFor="flt-to" className="sr-only">
            Tanggal mulai sampai
          </label>
          <Input
            id="flt-to"
            type="date"
            value={filters.to ?? ''}
            min={filters.from}
            onChange={(e) => apply({ to: e.target.value || undefined })}
            className="h-8 text-xs"
          />
        </div>
      </td>
      <td className={cellClass}>
        <label htmlFor="flt-period" className="sr-only">
          Filter Tahun Akademik atau Semester
        </label>
        <NativeSelect
          id="flt-period"
          value={periodValue}
          onChange={(e) => {
            const [kind, id] = e.target.value.split(':');
            if (kind === 'ay') apply({ ay: Number(id), semester: undefined });
            else if (kind === 'sem') apply({ semester: Number(id), ay: undefined });
            else apply({ ay: undefined, semester: undefined });
          }}
          className="[&_select]:h-8 [&_select]:text-xs"
        >
          <option value="">Semua periode</option>
          {options.academicYears.map((ay) => (
            <optgroup key={ay.id} label={`TA ${ay.label}`}>
              <option value={`ay:${ay.id}`}>TA {ay.label} (semua)</option>
              {options.semesters
                .filter((s) => s.ay_id === ay.id)
                .map((s) => (
                  <option key={s.id} value={`sem:${s.id}`}>
                    {s.label}
                  </option>
                ))}
            </optgroup>
          ))}
        </NativeSelect>
      </td>
      <td className={cellClass}>
        <label htmlFor="flt-status" className="sr-only">
          Filter Status
        </label>
        <NativeSelect
          id="flt-status"
          value={statusValue}
          onChange={(e) => {
            const v = e.target.value;
            if (v === '__multi') return;
            apply({ status: v ? [v as (typeof ACTIVITY_STATUSES)[number]] : undefined });
          }}
          className="[&_select]:h-8 [&_select]:text-xs"
        >
          <option value="">Semua status</option>
          {statusValue === '__multi' ? (
            <option value="__multi">{filters.status!.map((s) => ACTIVITY_STATUS_LABEL[s]).join(', ')}</option>
          ) : null}
          {ACTIVITY_STATUSES.map((s) => (
            <option key={s} value={s}>
              {ACTIVITY_STATUS_LABEL[s]}
            </option>
          ))}
        </NativeSelect>
      </td>
      <td className={cellClass}>
        <div className="flex flex-col gap-1">
          <label htmlFor="flt-partnership" className="sr-only">
            Filter status jalur Kemitraan
          </label>
          <NativeSelect
            id="flt-partnership"
            value={filters.partnership ?? ''}
            onChange={(e) => apply({ partnership: (e.target.value || undefined) as ActivityListFilters['partnership'] })}
            className="[&_select]:h-8 [&_select]:text-xs"
          >
            <option value="">Kemitraan: semua</option>
            {TRACK_STATUSES.filter((s) => s !== 'not_required').map((s) => (
              <option key={s} value={s}>
                Kemitraan: {TRACK_STATUS_LABEL[s]}
              </option>
            ))}
          </NativeSelect>
          <label htmlFor="flt-mobility" className="sr-only">
            Filter status jalur Mobilitas
          </label>
          <NativeSelect
            id="flt-mobility"
            value={filters.mobility ?? ''}
            onChange={(e) => apply({ mobility: (e.target.value || undefined) as ActivityListFilters['mobility'] })}
            className="[&_select]:h-8 [&_select]:text-xs"
          >
            <option value="">Mobilitas: semua</option>
            {TRACK_STATUSES.filter((s) => s !== 'rejected').map((s) => (
              <option key={s} value={s}>
                Mobilitas: {TRACK_STATUS_LABEL[s]}
              </option>
            ))}
          </NativeSelect>
        </div>
      </td>
      <td className={cellClass}>
        <label htmlFor="flt-flags" className="sr-only">
          Filter Penanda
        </label>
        <NativeSelect
          id="flt-flags"
          value={flagValue}
          onChange={(e) => {
            const v = e.target.value;
            if (v === 'late') apply({ late: true, sla: undefined });
            else if (v === 'sla:yellow') apply({ sla: 'yellow', late: undefined });
            else if (v === 'sla:red') apply({ sla: 'red', late: undefined });
            else apply({ late: undefined, sla: undefined });
          }}
          className="[&_select]:h-8 [&_select]:text-xs"
        >
          <option value="">Semua</option>
          <option value="late">Terlambat</option>
          <option value="sla:yellow">SLA kuning</option>
          <option value="sla:red">SLA merah</option>
        </NativeSelect>
      </td>
    </tr>
  );
}
