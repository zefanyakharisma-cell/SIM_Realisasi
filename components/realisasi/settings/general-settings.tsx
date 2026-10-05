'use client';

import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import { CalendarClock, Info, PlayCircle } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { toast } from '@/components/ui/toaster';
import { runDailyJobs, setDemoToday, updateSettings } from '@/lib/realisasi/actions/settings';
import { GENERAL_SETTING_FIELDS, generalSettingsSchema, type GeneralSettingsInput } from '@/lib/realisasi/schemas/settings';
import type { DailyJobsResult } from '@/lib/realisasi/types';
import { formatDate } from '@/lib/realisasi/format';
import { SNAPSHOT_KIND_LABEL } from '@/lib/realisasi/status';

export const LIVE_NOTICE = 'Berlaku untuk perhitungan live; snapshot yang sudah dibekukan tidak berubah.';

export function GeneralSettingsForm({ initial }: { initial: GeneralSettingsInput }) {
  const router = useRouter();
  const [values, setValues] = useState<Record<string, string>>(
    Object.fromEntries(Object.entries(initial).map(([k, v]) => [k, String(v)])),
  );
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [dirty, setDirty] = useState(false);
  const [saved, setSaved] = useState(false);
  const [pending, start] = useTransition();

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    const parsed = generalSettingsSchema.safeParse(values);
    if (!parsed.success) {
      setErrors(Object.fromEntries(parsed.error.issues.map((i) => [String(i.path[0]), i.message])));
      return;
    }
    setErrors({});
    start(async () => {
      const res = await updateSettings(parsed.data);
      if (res.ok) {
        toast.success('Pengaturan disimpan.', { description: LIVE_NOTICE });
        setDirty(false);
        setSaved(true);
        router.refresh();
      } else {
        toast.error(res.message);
      }
    });
  };

  return (
    <Card className="p-5">
      <form onSubmit={submit} noValidate className="space-y-5" aria-label="Pengaturan umum">
        {dirty || saved ? (
          <Alert variant="info" role="status">
            <Info aria-hidden="true" />
            <AlertDescription>{LIVE_NOTICE}</AlertDescription>
          </Alert>
        ) : null}
        <div className="grid gap-4 md:grid-cols-2">
          {GENERAL_SETTING_FIELDS.map((f) => {
            const id = `set-${f.key}`;
            const err = errors[f.key];
            return (
              <div key={f.key} className="grid gap-1">
                <Label htmlFor={id}>{f.label}</Label>
                <div className="flex items-center gap-2">
                  <Input
                    id={id}
                    type="number"
                    inputMode="decimal"
                    step={f.step ?? '1'}
                    min={0}
                    value={values[f.key] ?? ''}
                    aria-invalid={err ? true : undefined}
                    aria-describedby={err ? `${id}-err` : undefined}
                    onChange={(e) => {
                      setValues((v) => ({ ...v, [f.key]: e.target.value }));
                      setDirty(true);
                      setSaved(false);
                    }}
                    className="w-28"
                  />
                  <span className="text-sm text-muted-foreground">{f.suffix}</span>
                </div>
                {err ? (
                  <p id={`${id}-err`} className="text-xs text-danger-fg">
                    {err}
                  </p>
                ) : null}
              </div>
            );
          })}
        </div>
        <div className="flex justify-end">
          <Button type="submit" loading={pending} disabled={!dirty}>
            Simpan pengaturan
          </Button>
        </div>
      </form>
    </Card>
  );
}

export function DemoTodayCard({ demoToday, today }: { demoToday: string | null; today: string }) {
  const router = useRouter();
  const [value, setValue] = useState(demoToday ?? today);
  const [pending, start] = useTransition();
  const [jobs, setJobs] = useState<DailyJobsResult | null>(null);

  const apply = (next: string | null) =>
    start(async () => {
      const res = await setDemoToday(next);
      if (res.ok) {
        toast.success(next ? `Tanggal demo diatur ke ${formatDate(next)}.` : 'Kembali ke tanggal hari ini.');
        router.refresh();
      } else toast.error(res.message);
    });

  const run = () =>
    start(async () => {
      const res = await runDailyJobs();
      if (res.ok) {
        setJobs(res.data);
        toast.success('Job harian selesai dijalankan.');
        router.refresh();
      } else toast.error(res.message);
    });

  return (
    <Card className="space-y-4 p-5" data-testid="demo-today-card">
      <div>
        <h2 className="flex items-center gap-2 text-base font-semibold">
          <CalendarClock className="h-4 w-4" aria-hidden="true" />
          Simulasi tanggal (demo)
        </h2>
        <p className="text-sm text-muted-foreground">
          Hari ini menurut sistem: <strong>{formatDate(today)}</strong>
          {demoToday ? ' (tanggal demo aktif)' : ' (tanggal nyata)'}. Semua aturan tanggal, pengingat dan pembekuan memakai tanggal ini.
        </p>
      </div>
      <div className="flex flex-wrap items-end gap-3">
        <div className="grid gap-1">
          <Label htmlFor="demo-today">Tanggal demo</Label>
          <Input id="demo-today" type="date" value={value} onChange={(e) => setValue(e.target.value)} className="w-44" />
        </div>
        <Button onClick={() => apply(value)} loading={pending} disabled={!value}>
          Terapkan tanggal
        </Button>
        <Button variant="outline" onClick={() => apply(null)} disabled={pending || demoToday === null}>
          Kembali ke hari ini
        </Button>
        <Button variant="secondary" onClick={run} disabled={pending} data-testid="run-daily-jobs">
          <PlayCircle aria-hidden="true" />
          Jalankan job harian
        </Button>
      </div>
      <p className="text-xs text-muted-foreground">{LIVE_NOTICE}</p>
      {jobs ? (
        <Alert variant="success" role="status">
          <AlertTitle>Job harian {formatDate(jobs.today)}</AlertTitle>
          <AlertDescription>
            {jobs.revision_reminders} pengingat revisi ·{' '}
            {jobs.deadline_reminders} pengingat tenggat ·{' '}
            {jobs.frozen.length === 0
              ? 'tidak ada snapshot baru'
              : `dibekukan: ${jobs.frozen.map((f) => `${SNAPSHOT_KIND_LABEL[f.kind]} ${f.ay_label}`).join(', ')}`}
          </AlertDescription>
        </Alert>
      ) : null}
    </Card>
  );
}
