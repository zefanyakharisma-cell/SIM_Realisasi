'use client';
/**
 * Step 1 — Detail (Design §3.3). Also reused by the unit revision view (`mode="revision"`) and the
 * IO post-verification edit page (`mode="verified"`, R-29/R-30).
 *
 * - wizard: "Simpan Draf" / "Lanjut"; once a draft exists, valid changes autosave (debounced).
 * - revision: explicit "Simpan perubahan" (each save is logged as a revision diff, so no autosave).
 * - verified: explicit save with a mandatory change note → `edit_verified_activity`.
 */
import { useCallback, useEffect, useMemo, useRef, useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { AlertCircle, Info } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Button } from '@/components/ui/button';
import { Combobox } from '@/components/ui/combobox';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { NativeSelect } from '@/components/ui/native-select';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { Textarea } from '@/components/ui/textarea';
import { toast } from '@/components/ui/toaster';
import { activityTypeHelper, stepHref } from '@/components/realisasi/activity/labels';
import { AgreementPicker } from '@/components/realisasi/wizard/agreement-picker';
import { ExternalPersons, type PersonRowState } from '@/components/realisasi/wizard/external-persons';
import { SdgChips } from '@/components/realisasi/wizard/sdg-chips';
import { useSaveStatus } from '@/components/realisasi/wizard/save-status';
import { editVerifiedActivity, saveActivityDraft } from '@/lib/realisasi/actions/submission';
import { formatDate } from '@/lib/realisasi/format';
import { activityDetailSchema, activityDetailSubmitSchema, fieldErrors } from '@/lib/realisasi/schemas/activity';
import { FUNDING_LABEL, MODE_LABEL } from '@/lib/realisasi/status';
import type { FormOptions } from '@/lib/realisasi/queries/lookups';
import type { ActivityDetailPayload, ActivityMode, DocumentOption, FundingSource } from '@/lib/realisasi/types';

export type DetailFormMode = 'wizard' | 'revision' | 'verified';

interface FormState {
  name: string;
  type_id: string;
  start_date: string;
  end_date: string;
  mode: ActivityMode;
  venue: string;
  city: string;
  country_code: string;
  sks_recognized: string;
  funding_source: string;
  description: string;
  submitter_unit_id: string;
  co_unit_ids: number[];
  document_ids: number[];
  sdg_ids: number[];
  external_persons: PersonRowState[];
}

const FIELD_ORDER: Array<keyof FormState> = [
  'name',
  'type_id',
  'start_date',
  'end_date',
  'mode',
  'venue',
  'city',
  'country_code',
  'sks_recognized',
  'funding_source',
  'description',
  'submitter_unit_id',
  'co_unit_ids',
  'document_ids',
  'sdg_ids',
  'external_persons',
];

const FIELD_LABEL: Record<string, string> = {
  name: 'Nama kegiatan',
  type_id: 'Jenis kegiatan',
  start_date: 'Tanggal mulai',
  end_date: 'Tanggal selesai',
  mode: 'Moda',
  venue: 'Tempat / platform',
  city: 'Kota',
  country_code: 'Negara',
  sks_recognized: 'SKS diakui',
  funding_source: 'Sumber dana',
  description: 'Deskripsi',
  submitter_unit_id: 'Unit pengaju',
  co_unit_ids: 'Unit lain',
  document_ids: 'Kerja sama',
  sdg_ids: 'SDG',
  external_persons: 'Pembicara / tamu',
  note: 'Catatan perubahan',
};

function toState(p: ActivityDetailPayload | null, defaultUnit: number | null): FormState {
  return {
    name: p?.name ?? '',
    type_id: p?.type_id ? String(p.type_id) : '',
    start_date: p?.start_date ?? '',
    end_date: p?.end_date ?? '',
    mode: p?.mode ?? 'offline',
    venue: p?.venue ?? '',
    city: p?.city ?? '',
    country_code: p?.country_code ?? '',
    sks_recognized: p?.sks_recognized !== null && p?.sks_recognized !== undefined ? String(p.sks_recognized) : '',
    funding_source: p?.funding_source ?? '',
    description: p?.description ?? '',
    submitter_unit_id: p?.submitter_unit_id ? String(p.submitter_unit_id) : defaultUnit ? String(defaultUnit) : '',
    co_unit_ids: p?.co_unit_ids ?? [],
    document_ids: p?.document_ids ?? [],
    sdg_ids: p?.sdg_ids ?? [],
    external_persons: (p?.external_persons ?? []).map((x) => ({
      key: globalThis.crypto.randomUUID(),
      full_name: x.full_name,
      institution: x.institution,
      country_code: x.country_code,
      role: x.role,
      notes: x.notes ?? '',
    })),
  };
}

const blank = (s: string): string | null => (s.trim() === '' ? null : s.trim());

function toPayload(s: FormState): ActivityDetailPayload {
  const sks = s.sks_recognized.trim() === '' ? null : Number(s.sks_recognized.replace(',', '.'));
  return {
    name: s.name.trim(),
    type_id: Number(s.type_id) || 0,
    start_date: s.start_date,
    end_date: s.end_date,
    mode: s.mode,
    venue: blank(s.venue),
    city: s.mode === 'online' ? null : blank(s.city),
    country_code: s.mode === 'online' ? null : blank(s.country_code),
    sks_recognized: sks === null || Number.isNaN(sks) ? null : sks,
    funding_source: (blank(s.funding_source) as FundingSource | null) ?? null,
    description: s.description.trim(),
    submitter_unit_id: Number(s.submitter_unit_id) || 0,
    co_unit_ids: s.co_unit_ids,
    document_ids: s.document_ids,
    sdg_ids: s.sdg_ids,
    external_persons: s.external_persons.map((p) => ({
      full_name: p.full_name.trim(),
      institution: p.institution.trim(),
      country_code: p.country_code,
      role: (p.role || 'other') as ActivityDetailPayload['external_persons'][number]['role'],
      notes: blank(p.notes),
    })),
  };
}

/** Maps a server error to field errors where possible (CONTRACTS §2.9). */
function serverFieldErrors(code: string, message: string, detail: unknown): Record<string, string> {
  const fields =
    typeof detail === 'object' && detail !== null && 'fields' in detail && Array.isArray((detail as { fields: unknown }).fields)
      ? ((detail as { fields: unknown[] }).fields.filter((f) => typeof f === 'string') as string[])
      : [];
  switch (code) {
    case 'VALIDATION_REQUIRED':
    case 'R07_REQUIRED_FIELD':
      return Object.fromEntries(fields.map((f) => [f, `${FIELD_LABEL[f] ?? f} wajib diisi.`]));
    case 'VALIDATION_INVALID':
      return fields.length ? Object.fromEntries(fields.map((f) => [f, message])) : {};
    case 'END_BEFORE_START':
      return { end_date: message };
    case 'R04_AGREEMENT_NOT_VALID':
    case 'R07_AGREEMENT_REQUIRED':
      return { document_ids: message };
    case 'R14_UNIT_NOT_ALLOWED':
      return { submitter_unit_id: message };
    default:
      return {};
  }
}

function derivePeriod(start: string, years: FormOptions['academicYears']) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(start)) return null;
  for (const y of years) {
    if (start >= y.start_date && start <= y.end_date) {
      const sem = y.semesters.find((s) => start >= s.start_date && start <= s.end_date) ?? null;
      return { year: y, semester: sem };
    }
  }
  return { year: null, semester: null };
}

export interface DetailFormProps {
  mode: DetailFormMode;
  activityId: string | null;
  initial: ActivityDetailPayload | null;
  initialDocuments: DocumentOption[];
  options: FormOptions;
  /** Unit forced for submitters; null lets io_admin pick (create only). */
  lockedUnitId: number | null;
  today: string;
}

export function DetailForm({ mode, activityId, initial, initialDocuments, options, lockedUnitId, today }: DetailFormProps) {
  const router = useRouter();
  const save = useSaveStatus();
  const [state, setState] = useState<FormState>(() => toState(initial, lockedUnitId));
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [formError, setFormError] = useState<string | null>(null);
  const [note, setNote] = useState('');
  const [pending, startTransition] = useTransition();
  const summaryRef = useRef<HTMLDivElement>(null);
  const dirtyRef = useRef(false);
  const savingRef = useRef(false);

  const unitEditable = mode === 'wizard' && activityId === null && lockedUnitId === null;
  const type = options.activityTypes.find((t) => String(t.id) === state.type_id) ?? null;
  const period = useMemo(() => derivePeriod(state.start_date, options.academicYears), [state.start_date, options.academicYears]);
  const sdgNames = useMemo(() => Object.fromEntries(options.sdgs.map((s) => [s.id, s.name])), [options.sdgs]);
  const unitOptions = useMemo(
    () =>
      options.units
        .filter((u) => String(u.id) !== state.submitter_unit_id)
        .map((u) => ({ value: String(u.id), label: u.name })),
    [options.units, state.submitter_unit_id],
  );

  const set = <K extends keyof FormState>(key: K, value: FormState[K]) => {
    dirtyRef.current = true;
    setState((s) => ({ ...s, [key]: value }));
    if (errors[key as string]) setErrors(({ [key as string]: _drop, ...rest }) => rest);
    if (mode === 'wizard' && activityId) save.setDirty();
  };

  const showErrors = useCallback((errs: Record<string, string>, message?: string) => {
    setErrors(errs);
    setFormError(message ?? null);
    requestAnimationFrame(() => summaryRef.current?.focus());
  }, []);

  /** Persists the draft (create/update). Returns the id on success. */
  const persistDraft = useCallback(
    async (payload: ActivityDetailPayload, opts: { silent: boolean }): Promise<string | null> => {
      if (savingRef.current) return null;
      savingRef.current = true;
      save.setSaving();
      try {
        const res = await saveActivityDraft(activityId, payload);
        if (!res.ok) {
          save.setError(res.message);
          if (!opts.silent) showErrors(serverFieldErrors(res.code, res.message, res.detail), res.message);
          return null;
        }
        dirtyRef.current = false;
        save.setSaved();
        return res.data.id;
      } finally {
        savingRef.current = false;
      }
    },
    [activityId, save, showErrors],
  );

  // Autosave (wizard + existing draft only): debounce valid edits.
  useEffect(() => {
    if (mode !== 'wizard' || !activityId || !dirtyRef.current) return;
    const timer = setTimeout(() => {
      const parsed = activityDetailSchema.safeParse(toPayload(state));
      if (parsed.success) void persistDraft(parsed.data, { silent: true });
    }, 1500);
    return () => clearTimeout(timer);
  }, [state, mode, activityId, persistDraft]);

  function validate(strict: boolean): ActivityDetailPayload | null {
    const schema = strict ? activityDetailSubmitSchema : activityDetailSchema;
    const parsed = schema.safeParse(toPayload(state));
    if (!parsed.success) {
      showErrors(fieldErrors(parsed.error), 'Periksa kembali isian yang ditandai.');
      return null;
    }
    setErrors({});
    setFormError(null);
    return parsed.data;
  }

  function onSaveDraft(next: boolean) {
    const payload = validate(next);
    if (!payload) return;
    startTransition(async () => {
      const id = await persistDraft(payload, { silent: false });
      if (!id) return;
      if (next) router.push(stepHref(id, 2));
      else if (!activityId) router.replace(stepHref(id, 1));
      else toast.success('Draf tersimpan.');
    });
  }

  function onSaveRevision() {
    const payload = validate(false);
    if (!payload || !activityId) return;
    startTransition(async () => {
      const id = await persistDraft(payload, { silent: false });
      if (!id) return;
      toast.success('Perubahan Detail tersimpan.');
      router.refresh();
    });
  }

  function onSaveVerified() {
    const payload = validate(true);
    if (!payload || !activityId) return;
    if (note.trim() === '') {
      showErrors({ note: 'Catatan perubahan wajib diisi.' }, 'Catatan perubahan wajib diisi.');
      return;
    }
    const { submitter_unit_id: _immutable, ...partial } = payload;
    startTransition(async () => {
      const res = await editVerifiedActivity(activityId, partial, note);
      if (!res.ok) {
        showErrors(serverFieldErrors(res.code, res.message, res.detail), res.message);
        return;
      }
      const changed = Object.keys(res.data.diff ?? {}).length;
      toast.success(changed ? `${changed} perubahan tersimpan dan dicatat di Riwayat.` : 'Tidak ada perubahan.', {
        description: res.data.in_frozen_period ? 'Kegiatan berada pada periode beku — dicatat sebagai Perubahan Pasca-Beku.' : undefined,
      });
      router.push(`/realisasi/kegiatan/${activityId}?tab=riwayat`);
      router.refresh();
    });
  }

  const err = (k: string) => errors[k];
  const errId = (k: string) => `f-${k}-error`;
  const aria = (k: string, hintId?: string) => ({
    'aria-invalid': Boolean(err(k)) || undefined,
    'aria-describedby': [err(k) ? errId(k) : null, hintId ?? null].filter(Boolean).join(' ') || undefined,
  });
  const fieldError = (k: string) =>
    err(k) ? (
      <p id={errId(k)} className="text-xs text-destructive">
        {err(k)}
      </p>
    ) : null;

  const errorList = FIELD_ORDER.flatMap((k) =>
    Object.entries(errors)
      .filter(([key]) => key === k || key.startsWith(`${k}.`))
      .map(([key, msg]) => ({ key, msg, target: key.includes('.') ? key.split('.')[0]! : key })),
  ).concat(errors.note ? [{ key: 'note', msg: errors.note, target: 'note' }] : []);

  const endAfterToday = /^\d{4}-\d{2}-\d{2}$/.test(state.end_date) && state.end_date > today;

  return (
    <form
      noValidate
      onSubmit={(e) => {
        e.preventDefault();
        if (mode === 'wizard') onSaveDraft(true);
        else if (mode === 'revision') onSaveRevision();
        else onSaveVerified();
      }}
      className="space-y-8"
      aria-label="Detail kegiatan"
    >
      {(formError || errorList.length > 0) && (
        <div ref={summaryRef} tabIndex={-1} role="alert" className="outline-none" data-testid="form-error-summary">
          <Alert variant="destructive">
            <AlertCircle aria-hidden />
            <AlertTitle>{formError ?? 'Periksa kembali isian yang ditandai.'}</AlertTitle>
            {errorList.length > 0 && (
              <AlertDescription>
                <ul className="mt-1 list-disc pl-5">
                  {errorList.map((e) => (
                    <li key={e.key}>
                      <a href={`#f-${e.target}`} className="underline">
                        {FIELD_LABEL[e.target] ?? e.target}
                      </a>
                      : {e.msg}
                    </li>
                  ))}
                </ul>
              </AlertDescription>
            )}
          </Alert>
        </div>
      )}

      <section className="grid gap-x-6 gap-y-5 md:grid-cols-2" aria-labelledby="sec-info">
        <h2 id="sec-info" className="text-base font-semibold md:col-span-2">
          Informasi kegiatan
        </h2>

        <div className="space-y-1.5 md:col-span-2">
          <Label htmlFor="f-name">Nama kegiatan *</Label>
          <Input id="f-name" value={state.name} onChange={(e) => set('name', e.target.value)} required {...aria('name')} />
          {fieldError('name')}
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="f-type_id">Jenis kegiatan *</Label>
          <NativeSelect
            id="f-type_id"
            value={state.type_id}
            placeholder="Pilih jenis kegiatan"
            onChange={(e) => set('type_id', e.target.value)}
            required
            {...aria('type_id', 'f-type-helper')}
          >
            {options.activityTypes
              .filter((t) => t.is_active || String(t.id) === state.type_id)
              .map((t) => (
                <option key={t.id} value={t.id}>
                  {t.name}
                </option>
              ))}
          </NativeSelect>
          <p id="f-type-helper" className="text-xs text-muted-foreground" data-testid="type-helper">
            {type ? activityTypeHelper(type) : 'Pilih jenis untuk melihat aturan perhitungan dan kewajiban data peserta.'}
          </p>
          {fieldError('type_id')}
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="f-submitter_unit_id">Unit pengaju *</Label>
          {unitEditable ? (
            <NativeSelect
              id="f-submitter_unit_id"
              value={state.submitter_unit_id}
              placeholder="Pilih unit"
              onChange={(e) => set('submitter_unit_id', e.target.value)}
              {...aria('submitter_unit_id')}
            >
              {options.units
                .filter((u) => u.kind !== 'up')
                .map((u) => (
                  <option key={u.id} value={u.id}>
                    {u.name}
                  </option>
                ))}
            </NativeSelect>
          ) : (
            <p id="f-submitter_unit_id" className="flex h-9 items-center rounded-md border bg-muted/40 px-3 text-sm">
              {options.units.find((u) => String(u.id) === state.submitter_unit_id)?.name ?? '–'}
            </p>
          )}
          {fieldError('submitter_unit_id')}
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="f-start_date">Tanggal mulai *</Label>
          <Input
            id="f-start_date"
            type="date"
            value={state.start_date}
            onChange={(e) => set('start_date', e.target.value)}
            required
            {...aria('start_date', 'f-period')}
          />
          {fieldError('start_date')}
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="f-end_date">Tanggal selesai *</Label>
          <Input
            id="f-end_date"
            type="date"
            value={state.end_date}
            min={state.start_date || undefined}
            onChange={(e) => set('end_date', e.target.value)}
            required
            {...aria('end_date', endAfterToday ? 'f-end-hint' : undefined)}
          />
          {endAfterToday && (
            <p id="f-end-hint" className="text-xs text-amber-800">
              Kegiatan belum selesai. Draf dapat disimpan, tetapi baru dapat diajukan setelah {formatDate(state.end_date)} (R-08).
            </p>
          )}
          {fieldError('end_date')}
        </div>

        <div className="md:col-span-2" id="f-period" aria-live="polite" data-testid="derived-period">
          <p className="text-sm">
            <span className="text-muted-foreground">Semester · Tahun akademik: </span>
            {!period ? (
              <span className="text-muted-foreground">mengikuti tanggal mulai</span>
            ) : period.year ? (
              <span className="font-medium">
                {period.semester?.label ?? '–'} · TA {period.year.label}
              </span>
            ) : (
              <span className="font-medium text-amber-800">
                Di luar tahun akademik terdaftar — tidak dapat diajukan. Hubungi Admin IO (R-09).
              </span>
            )}
          </p>
        </div>

        <fieldset className="space-y-1.5 md:col-span-2">
          <legend className="text-sm font-medium">Moda *</legend>
          <RadioGroup
            value={state.mode}
            onValueChange={(v) => set('mode', v as ActivityMode)}
            className="flex flex-wrap gap-4"
            aria-label="Moda kegiatan"
          >
            {(Object.keys(MODE_LABEL) as ActivityMode[]).map((m) => (
              <div key={m} className="flex items-center gap-2">
                <RadioGroupItem id={`f-mode-${m}`} value={m} />
                <Label htmlFor={`f-mode-${m}`} className="font-normal">
                  {MODE_LABEL[m]}
                </Label>
              </div>
            ))}
          </RadioGroup>
        </fieldset>

        <div className="space-y-1.5">
          <Label htmlFor="f-venue">{state.mode === 'online' ? 'Nama platform *' : 'Tempat *'}</Label>
          <Input
            id="f-venue"
            value={state.venue}
            placeholder={state.mode === 'online' ? 'mis. Zoom, Microsoft Teams' : 'mis. Gedung P, Kampus Siwalankerto'}
            onChange={(e) => set('venue', e.target.value)}
            {...aria('venue')}
          />
          {fieldError('venue')}
        </div>

        {state.mode !== 'online' ? (
          <>
            <div className="space-y-1.5">
              <Label htmlFor="f-city">Kota *</Label>
              <Input id="f-city" value={state.city} onChange={(e) => set('city', e.target.value)} {...aria('city')} />
              {fieldError('city')}
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="f-country_code">Negara *</Label>
              <NativeSelect
                id="f-country_code"
                value={state.country_code}
                placeholder="Pilih negara"
                onChange={(e) => set('country_code', e.target.value)}
                {...aria('country_code')}
              >
                {options.countries.map((c) => (
                  <option key={c.code} value={c.code}>
                    {c.name}
                  </option>
                ))}
              </NativeSelect>
              {fieldError('country_code')}
            </div>
          </>
        ) : (
          <div className="hidden md:block" aria-hidden />
        )}

        <div className="space-y-1.5">
          <Label htmlFor="f-sks_recognized">SKS diakui</Label>
          <Input
            id="f-sks_recognized"
            inputMode="decimal"
            value={state.sks_recognized}
            onChange={(e) => set('sks_recognized', e.target.value)}
            {...aria('sks_recognized')}
          />
          {fieldError('sks_recognized')}
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="f-funding_source">Sumber dana</Label>
          <NativeSelect
            id="f-funding_source"
            value={state.funding_source}
            placeholder="Pilih sumber dana"
            onChange={(e) => set('funding_source', e.target.value)}
            {...aria('funding_source')}
          >
            {(Object.keys(FUNDING_LABEL) as FundingSource[]).map((f) => (
              <option key={f} value={f}>
                {FUNDING_LABEL[f]}
              </option>
            ))}
          </NativeSelect>
        </div>

        <div className="space-y-1.5 md:col-span-2">
          <Label htmlFor="f-description">Deskripsi *</Label>
          <Textarea
            id="f-description"
            rows={4}
            value={state.description}
            onChange={(e) => set('description', e.target.value)}
            {...aria('description')}
          />
          {fieldError('description')}
        </div>

        <div className="space-y-1.5 md:col-span-2">
          <Label id="f-co_unit_ids-label" htmlFor="f-co_unit_ids">
            Unit lain (akses baca)
          </Label>
          <Combobox
            id="f-co_unit_ids"
            aria-labelledby="f-co_unit_ids-label"
            options={unitOptions}
            value={state.co_unit_ids.map(String)}
            onChange={(v) => set('co_unit_ids', v.map(Number))}
            placeholder="Pilih unit lain (opsional)"
            searchPlaceholder="Cari unit…"
          />
          {fieldError('co_unit_ids')}
        </div>
      </section>

      <section className="space-y-3" aria-labelledby="f-document_ids-label">
        <h2 id="f-document_ids-label" className="text-base font-semibold">
          Kerja sama *
        </h2>
        <AgreementPicker
          id="f-document_ids"
          labelId="f-document_ids-label"
          start={state.start_date}
          end={state.end_date}
          unitId={Number(state.submitter_unit_id) || null}
          value={state.document_ids}
          onChange={(ids) => set('document_ids', ids)}
          known={initialDocuments}
          error={err('document_ids')}
          errorId={errId('document_ids')}
        />
        {fieldError('document_ids')}
      </section>

      <section className="space-y-3" aria-labelledby="sec-persons">
        <h2 id="sec-persons" className="text-base font-semibold">
          Pembicara / Dosen Asing / Tamu
        </h2>
        <p className="text-sm text-muted-foreground">Dicatat dan diverifikasi tim Kemitraan; tidak dihitung pada KPI 1.1.</p>
        <div id="f-external_persons">
          <ExternalPersons
            rows={state.external_persons}
            onChange={(rows) => set('external_persons', rows)}
            countries={options.countries}
            errors={errors}
          />
        </div>
      </section>

      <section className="space-y-3" aria-labelledby="sec-sdg">
        <h2 id="sec-sdg" className="text-base font-semibold">
          SDG terkait
        </h2>
        <div id="f-sdg_ids">
          <SdgChips value={state.sdg_ids} onChange={(ids) => set('sdg_ids', ids)} names={sdgNames} labelId="sec-sdg" />
        </div>
      </section>

      {mode === 'verified' && (
        <section className="space-y-1.5" aria-labelledby="sec-note">
          <h2 id="sec-note" className="text-base font-semibold">
            Catatan perubahan *
          </h2>
          <Alert variant="info">
            <Info aria-hidden />
            <AlertDescription>
              Perubahan dicatat di Riwayat beserta selisih nilainya. Status dan tanggal verifikasi tidak berubah.
            </AlertDescription>
          </Alert>
          <Label htmlFor="f-note" className="sr-only">
            Catatan perubahan
          </Label>
          <Textarea id="f-note" rows={3} value={note} onChange={(e) => setNote(e.target.value)} {...aria('note')} />
          {fieldError('note')}
        </section>
      )}

      <div className="flex flex-wrap items-center justify-end gap-3 border-t pt-4">
        {mode === 'wizard' && (
          <>
            <Button
              type="button"
              variant="outline"
              onClick={() => onSaveDraft(false)}
              loading={pending}
              data-testid="wizard-save-draft"
            >
              Simpan Draf
            </Button>
            <Button type="submit" loading={pending} data-testid="wizard-next">
              Lanjut
            </Button>
          </>
        )}
        {mode === 'revision' && (
          <Button type="submit" loading={pending} data-testid="save-detail">
            Simpan perubahan Detail
          </Button>
        )}
        {mode === 'verified' && (
          <Button type="submit" loading={pending} data-testid="save-verified-detail">
            Simpan perubahan
          </Button>
        )}
      </div>
    </form>
  );
}
