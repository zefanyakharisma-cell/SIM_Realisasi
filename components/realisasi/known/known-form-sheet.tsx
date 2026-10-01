'use client';

import { useId, useRef, useState, useTransition, type ReactNode } from 'react';
import { useRouter } from 'next/navigation';
import { AlertCircle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { NativeSelect } from '@/components/ui/native-select';
import { Textarea } from '@/components/ui/textarea';
import { Sheet, SheetContent, SheetDescription, SheetFooter, SheetHeader, SheetTitle, SheetTrigger } from '@/components/ui/sheet';
import { toast } from '@/components/ui/toaster';
import { createKnownActivity, updateKnownActivity } from '@/lib/realisasi/actions/known';
import { KNOWN_SOURCES, knownActivitySchema, type KnownActivityFormValues } from '@/lib/realisasi/schemas/known';
import { KNOWN_SOURCE_LABEL } from '@/lib/realisasi/status';
import type { KnownActivityPayload, KnownActivityRow } from '@/lib/realisasi/types';

type Errors = Partial<Record<keyof KnownActivityFormValues, string>>;

const FIELD_LABEL: Record<keyof KnownActivityFormValues, string> = {
  title: 'Judul kegiatan',
  activity_date: 'Tanggal kegiatan',
  unit_id: 'Unit',
  partner_name: 'Nama mitra',
  country_code: 'Negara',
  is_international: 'Internasional',
  source: 'Sumber informasi',
  source_reference: 'Referensi sumber',
  notes: 'Catatan',
};

function initial(row?: KnownActivityRow): KnownActivityFormValues {
  return {
    title: row?.title ?? '',
    activity_date: row?.activity_date ?? '',
    unit_id: row?.unit_id ? String(row.unit_id) : '',
    partner_name: row?.partner_name ?? '',
    country_code: row?.country_code ?? '',
    is_international: row?.is_international ?? true,
    source: row?.source ?? '',
    source_reference: row?.source_reference ?? '',
    notes: row?.notes ?? '',
  };
}

/** "+ Catat kegiatan" side-sheet form (Design §3.7); also used to edit an unmatched entry. */
export function KnownFormSheet({
  units,
  countries,
  row,
  trigger,
}: {
  units: Array<{ id: number; label: string }>;
  countries: Array<{ code: string; name: string }>;
  row?: KnownActivityRow;
  trigger: ReactNode;
}) {
  const uid = useId();
  const router = useRouter();
  const formRef = useRef<HTMLFormElement>(null);
  const [open, setOpen] = useState(false);
  const [values, setValues] = useState<KnownActivityFormValues>(() => initial(row));
  const [errors, setErrors] = useState<Errors>({});
  const [serverError, setServerError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function set<K extends keyof KnownActivityFormValues>(k: K, v: KnownActivityFormValues[K]) {
    setValues((prev) => ({ ...prev, [k]: v }));
  }

  function onOpenChange(next: boolean) {
    if (pending) return;
    setOpen(next);
    if (next) {
      setValues(initial(row));
      setErrors({});
      setServerError(null);
    }
  }

  function submit(e: React.FormEvent) {
    e.preventDefault();
    setServerError(null);
    const parsed = knownActivitySchema.safeParse({
      ...values,
      unit_id: values.unit_id === '' ? null : values.unit_id,
      source: values.source === '' ? undefined : values.source,
    });
    if (!parsed.success) {
      const errs: Errors = {};
      for (const issue of parsed.error.issues) {
        const k = issue.path[0] as keyof KnownActivityFormValues;
        if (k && !errs[k]) errs[k] = issue.message;
      }
      setErrors(errs);
      requestAnimationFrame(() => formRef.current?.querySelector<HTMLElement>('[aria-invalid="true"]')?.focus());
      return;
    }
    setErrors({});
    const payload = parsed.data as KnownActivityPayload;
    startTransition(async () => {
      const res = row ? await updateKnownActivity(row.id, payload) : await createKnownActivity(payload);
      if (!res.ok) {
        setServerError(res.message);
        return;
      }
      toast.success(row ? 'Entri diperbarui.' : 'Kegiatan dicatat di register.');
      setOpen(false);
      router.refresh();
    });
  }

  const errorList = Object.entries(errors) as Array<[keyof KnownActivityFormValues, string]>;
  const field = (k: keyof KnownActivityFormValues) => ({
    id: `${uid}-${k}`,
    name: k,
    'aria-invalid': errors[k] ? true : undefined,
    'aria-describedby': errors[k] ? `${uid}-${k}-error` : undefined,
    disabled: pending,
  });
  const label = (k: keyof KnownActivityFormValues, required = false) => (
    <label htmlFor={`${uid}-${k}`} className="text-sm font-medium">
      {FIELD_LABEL[k]}
      {required ? (
        <span className="text-red-700 dark:text-red-400">
          {' '}*<span className="sr-only"> (wajib)</span>
        </span>
      ) : null}
    </label>
  );
  const err = (k: keyof KnownActivityFormValues) =>
    errors[k] ? (
      <p id={`${uid}-${k}-error`} className="text-sm text-red-700 dark:text-red-400">
        {errors[k]}
      </p>
    ) : null;

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetTrigger asChild>{trigger}</SheetTrigger>
      <SheetContent side="right" className="w-full overflow-y-auto sm:max-w-lg">
        <form ref={formRef} onSubmit={submit} noValidate className="space-y-4" data-testid="known-form">
          <SheetHeader>
            <SheetTitle>{row ? 'Ubah entri register' : 'Catat kegiatan'}</SheetTitle>
            <SheetDescription>
              Kegiatan internasional yang diketahui dari sumber lain (surat tugas, berita, laporan fakultas) untuk mengukur KPI 1.19.S8.
            </SheetDescription>
          </SheetHeader>
          {serverError || errorList.length > 0 ? (
            <div role="alert" className="rounded-md border border-red-300 bg-red-50 p-3 text-sm text-red-900 dark:border-red-800 dark:bg-red-950/50 dark:text-red-200">
              <p className="flex items-center gap-1 font-medium">
                <AlertCircle className="h-4 w-4" aria-hidden="true" />
                {serverError ?? `Periksa ${errorList.length} isian berikut:`}
              </p>
              {!serverError ? (
                <ul className="mt-1 list-disc pl-6">
                  {errorList.map(([k, m]) => (
                    <li key={k}>
                      {FIELD_LABEL[k]}: {m}
                    </li>
                  ))}
                </ul>
              ) : null}
            </div>
          ) : null}
          <div className="space-y-1.5">
            {label('title', true)}
            <Input {...field('title')} value={values.title} onChange={(e) => set('title', e.target.value)} aria-required />
            {err('title')}
          </div>
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="space-y-1.5">
              {label('activity_date', true)}
              <Input type="date" {...field('activity_date')} value={values.activity_date} onChange={(e) => set('activity_date', e.target.value)} aria-required />
              {err('activity_date')}
            </div>
            <div className="space-y-1.5">
              {label('unit_id')}
              <NativeSelect {...field('unit_id')} value={values.unit_id} onChange={(e) => set('unit_id', e.target.value)}>
                <option value="">Belum diketahui</option>
                {units.map((u) => (
                  <option key={u.id} value={u.id}>
                    {u.label}
                  </option>
                ))}
              </NativeSelect>
              {err('unit_id')}
            </div>
          </div>
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="space-y-1.5">
              {label('partner_name')}
              <Input {...field('partner_name')} value={values.partner_name} onChange={(e) => set('partner_name', e.target.value)} />
              {err('partner_name')}
            </div>
            <div className="space-y-1.5">
              {label('country_code')}
              <NativeSelect
                {...field('country_code')}
                value={values.country_code}
                onChange={(e) => {
                  set('country_code', e.target.value);
                  if (e.target.value) set('is_international', e.target.value !== 'ID');
                }}
              >
                <option value="">Belum diketahui</option>
                {countries.map((c) => (
                  <option key={c.code} value={c.code}>
                    {c.name}
                  </option>
                ))}
              </NativeSelect>
              {err('country_code')}
            </div>
          </div>
          <div className="flex items-center gap-2">
            <input
              type="checkbox"
              id={`${uid}-is_international`}
              checked={values.is_international}
              onChange={(e) => set('is_international', e.target.checked)}
              disabled={pending}
              className="h-4 w-4"
            />
            <label htmlFor={`${uid}-is_international`} className="text-sm">
              Kegiatan internasional (mitra luar negeri)
            </label>
          </div>
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="space-y-1.5">
              {label('source', true)}
              <NativeSelect {...field('source')} value={values.source} onChange={(e) => set('source', e.target.value as KnownActivityFormValues['source'])} aria-required>
                <option value="">Pilih sumber…</option>
                {KNOWN_SOURCES.map((s) => (
                  <option key={s} value={s}>
                    {KNOWN_SOURCE_LABEL[s]}
                  </option>
                ))}
              </NativeSelect>
              {err('source')}
            </div>
            <div className="space-y-1.5">
              {label('source_reference')}
              <Input {...field('source_reference')} value={values.source_reference} onChange={(e) => set('source_reference', e.target.value)} placeholder="No. surat / tautan" />
              {err('source_reference')}
            </div>
          </div>
          <div className="space-y-1.5">
            {label('notes')}
            <Textarea {...field('notes')} rows={3} value={values.notes} onChange={(e) => set('notes', e.target.value)} />
            {err('notes')}
          </div>
          <SheetFooter className="gap-2">
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)} disabled={pending}>
              Batal
            </Button>
            <Button type="submit" loading={pending} data-testid="known-submit">
              {row ? 'Simpan perubahan' : 'Simpan'}
            </Button>
          </SheetFooter>
        </form>
      </SheetContent>
    </Sheet>
  );
}
