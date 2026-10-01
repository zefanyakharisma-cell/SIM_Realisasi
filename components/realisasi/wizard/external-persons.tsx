'use client';
/** Repeatable "Pembicara / Dosen Asing / Tamu" rows (R-20; Design §3.3). */
import { Plus, Trash2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { NativeSelect } from '@/components/ui/native-select';
import { PERSON_ROLE_LABEL } from '@/lib/realisasi/status';
import type { PersonRole } from '@/lib/realisasi/types';
import type { CountryOption } from '@/lib/realisasi/queries/lookups';

export interface PersonRowState {
  key: string;
  full_name: string;
  institution: string;
  country_code: string;
  role: PersonRole | '';
  notes: string;
}

const ROLES = Object.keys(PERSON_ROLE_LABEL) as PersonRole[];

export function newPersonRow(): PersonRowState {
  return { key: globalThis.crypto.randomUUID(), full_name: '', institution: '', country_code: '', role: '', notes: '' };
}

export function ExternalPersons({
  rows,
  onChange,
  countries,
  errors,
  disabled,
}: {
  rows: PersonRowState[];
  onChange: (rows: PersonRowState[]) => void;
  countries: CountryOption[];
  /** Keyed `external_persons.<index>.<field>`. */
  errors: Record<string, string>;
  disabled?: boolean;
}) {
  const update = (i: number, patch: Partial<PersonRowState>) =>
    onChange(rows.map((r, idx) => (idx === i ? { ...r, ...patch } : r)));

  return (
    <div className="space-y-3">
      {rows.length === 0 && <p className="text-sm text-muted-foreground">Belum ada pembicara, dosen asing, atau tamu.</p>}
      {rows.map((r, i) => {
        const err = (f: string) => errors[`external_persons.${i}.${f}`];
        const fid = (f: string) => `person-${r.key}-${f}`;
        return (
          <fieldset key={r.key} className="grid gap-3 rounded-md border p-3 md:grid-cols-[1fr_1fr_12rem_12rem_auto]">
            <legend className="sr-only">Orang ke-{i + 1}</legend>
            {(
              [
                ['full_name', 'Nama'],
                ['institution', 'Institusi'],
              ] as const
            ).map(([f, label]) => (
              <div key={f} className="space-y-1">
                <Label htmlFor={fid(f)}>{label}</Label>
                <Input
                  id={fid(f)}
                  value={r[f]}
                  disabled={disabled}
                  onChange={(e) => update(i, { [f]: e.target.value })}
                  aria-invalid={Boolean(err(f)) || undefined}
                  aria-describedby={err(f) ? `${fid(f)}-err` : undefined}
                />
                {err(f) && (
                  <p id={`${fid(f)}-err`} className="text-xs text-destructive">
                    {err(f)}
                  </p>
                )}
              </div>
            ))}
            <div className="space-y-1">
              <Label htmlFor={fid('country_code')}>Negara</Label>
              <NativeSelect
                id={fid('country_code')}
                value={r.country_code}
                disabled={disabled}
                placeholder="Pilih negara"
                onChange={(e) => update(i, { country_code: e.target.value })}
                aria-invalid={Boolean(err('country_code')) || undefined}
                aria-describedby={err('country_code') ? `${fid('country_code')}-err` : undefined}
              >
                {countries.map((c) => (
                  <option key={c.code} value={c.code}>
                    {c.name}
                  </option>
                ))}
              </NativeSelect>
              {err('country_code') && (
                <p id={`${fid('country_code')}-err`} className="text-xs text-destructive">
                  {err('country_code')}
                </p>
              )}
            </div>
            <div className="space-y-1">
              <Label htmlFor={fid('role')}>Peran</Label>
              <NativeSelect
                id={fid('role')}
                value={r.role}
                disabled={disabled}
                placeholder="Pilih peran"
                onChange={(e) => update(i, { role: e.target.value as PersonRole | '' })}
                aria-invalid={Boolean(err('role')) || undefined}
                aria-describedby={err('role') ? `${fid('role')}-err` : undefined}
              >
                {ROLES.map((role) => (
                  <option key={role} value={role}>
                    {PERSON_ROLE_LABEL[role]}
                  </option>
                ))}
              </NativeSelect>
              {err('role') && (
                <p id={`${fid('role')}-err`} className="text-xs text-destructive">
                  {err('role')}
                </p>
              )}
            </div>
            <div className="flex items-end">
              <Button
                type="button"
                variant="ghost"
                size="icon"
                disabled={disabled}
                onClick={() => onChange(rows.filter((_, idx) => idx !== i))}
                aria-label={`Hapus orang ke-${i + 1}${r.full_name ? ` (${r.full_name})` : ''}`}
              >
                <Trash2 aria-hidden />
              </Button>
            </div>
          </fieldset>
        );
      })}
      <Button type="button" variant="outline" size="sm" disabled={disabled} onClick={() => onChange([...rows, newPersonRow()])}>
        <Plus aria-hidden /> Tambah orang
      </Button>
    </div>
  );
}
