'use client';
/**
 * Step 2 — Peserta (Design §3.3; R-11, R-12, R-16..R-19, R-21, R-22). Also used for the unit
 * Mobility revision (a new draft version is created on first save) and the IO post-verification
 * participant edit.
 *
 * Flow per panel: paste ids / upload the Excel template → "Cek NRP" (lookup API) → rows marked
 * ✓ found, ✗ blocking (red, not saved), ⚠ warning (graduated/inactive, allowed). Whenever the set has
 * no blocking rows it is persisted with `saveParticipants` (DB re-validates; row errors map back).
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { AlertCircle, AlertTriangle, CheckCircle2, Download, FileText, Loader2, Trash2, Upload, XCircle } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { FileDrop } from '@/components/ui/file-drop';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { NativeSelect } from '@/components/ui/native-select';
import { Textarea } from '@/components/ui/textarea';
import { useSaveStatus } from '@/components/realisasi/wizard/save-status';
import { saveParticipants } from '@/lib/realisasi/actions/submission';
import { splitIdTokens } from '@/lib/realisasi/schemas/participants';
import { MAX_FILE_BYTES } from '@/lib/storage';
import type {
  CountryOption,
  EmployeeLookupResult,
  EmployeeLookupStatus,
  StudentLookupResult,
  StudentLookupStatus,
} from '@/lib/realisasi/queries/lookups';
import type { ParticipantVersion, StaffRowPayload, StudentRowPayload, StudentSection } from '@/lib/realisasi/types';
import { cn } from '@/lib/utils';

type RowStatus = StudentLookupStatus | EmployeeLookupStatus;

interface StudentRow {
  key: string;
  section: StudentSection;
  nrp: string;
  status: RowStatus;
  blocking: boolean;
  full_name: string | null;
  faculty_name: string | null;
  prodi_name: string | null;
  home_institution: string;
  home_student_number: string;
  home_country_code: string;
  transcript_path: string | null;
  transcript_href: string | null;
  row_note: string | null;
  serverError?: string;
}

interface StaffRow {
  key: string;
  employee_id: string;
  status: RowStatus;
  blocking: boolean;
  full_name: string | null;
  unit_name: string | null;
  row_note: string | null;
  serverError?: string;
}

const STATUS_TEXT: Record<RowStatus, string> = {
  ok: 'Ditemukan',
  not_found: 'Tidak ditemukan',
  graduated: 'Sudah lulus (peringatan)',
  inactive: 'Tidak aktif (peringatan)',
  not_inbound: 'Bukan mahasiswa inbound',
  is_inbound: 'Mahasiswa inbound — pindahkan ke panel Mahasiswa Inbound',
  duplicate: 'Duplikat',
};

function StatusIcon({ status, blocking }: { status: RowStatus; blocking: boolean }) {
  if (blocking) return <XCircle className="h-4 w-4 shrink-0 text-red-700" aria-hidden />;
  if (status === 'graduated' || status === 'inactive') return <AlertTriangle className="h-4 w-4 shrink-0 text-amber-700" aria-hidden />;
  return <CheckCircle2 className="h-4 w-4 shrink-0 text-green-700" aria-hidden />;
}

function rowClass(status: RowStatus, blocking: boolean): string {
  if (blocking) return 'bg-red-50';
  if (status === 'graduated' || status === 'inactive') return 'bg-amber-50';
  return '';
}

const key = () => globalThis.crypto.randomUUID();

function fromVersion(v: ParticipantVersion | null): { students: StudentRow[]; staff: StaffRow[] } {
  if (!v) return { students: [], staff: [] };
  return {
    students: v.students.map((s) => ({
      key: key(),
      section: s.section,
      nrp: s.nrp,
      status: s.registry_status === 'active' ? 'ok' : s.registry_status,
      blocking: false,
      full_name: s.full_name,
      faculty_name: s.faculty_name,
      prodi_name: s.prodi_name,
      home_institution: s.home_institution ?? '',
      home_student_number: s.home_student_number ?? '',
      home_country_code: s.home_country_code ?? '',
      transcript_path: s.transcript_path,
      transcript_href: s.transcript_href,
      row_note: s.row_note,
    })),
    staff: v.staff.map((s) => ({
      key: key(),
      employee_id: s.employee_id,
      status: s.registry_status === 'active' ? 'ok' : s.registry_status,
      blocking: false,
      full_name: s.full_name,
      unit_name: s.unit_name,
      row_note: s.row_note,
    })),
  };
}

interface DbRowError {
  section: 'internal' | 'inbound' | 'staff';
  index: number;
  id: string;
  code: string;
}

function dbRows(detail: unknown): DbRowError[] {
  if (typeof detail !== 'object' || detail === null || !('rows' in detail)) return [];
  const rows = (detail as { rows: unknown }).rows;
  return Array.isArray(rows) ? (rows.filter((r) => typeof r === 'object' && r !== null && 'id' in r) as DbRowError[]) : [];
}

const DB_CODE_STATUS: Record<string, RowStatus> = {
  R16_NRP_NOT_FOUND: 'not_found',
  R19_EMPLOYEE_NOT_FOUND: 'not_found',
  R22_DUPLICATE_NRP: 'duplicate',
  R22_DUPLICATE_EMPLOYEE: 'duplicate',
  R17_NOT_INBOUND: 'not_inbound',
  R16_SECTION_MISMATCH: 'is_inbound',
};

class LookupError extends Error {}

async function postJson<T>(url: string, body: unknown): Promise<T> {
  let res: Response;
  try {
    res = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  } catch {
    throw new LookupError('Layanan data mahasiswa tidak dapat dihubungi. Coba lagi.');
  }
  const json = (await res.json().catch(() => ({}))) as T & { message?: string };
  if (!res.ok) throw new LookupError(json.message ?? 'Layanan data mahasiswa tidak dapat dihubungi. Coba lagi.');
  return json;
}

export interface ParticipantsEditorProps {
  activityId: string;
  initialVersion: ParticipantVersion | null;
  countries: CountryOption[];
  required: { any: boolean; internal: boolean; inbound: boolean };
  /** Reports whether unsaved blocking rows exist (wizard disables "Lanjut"/"Ajukan"). */
  onBlockingChange?: (blocking: boolean) => void;
  /** Called after a successful save (e.g. router.refresh for the checklist). */
  onSaved?: (version: number) => void;
  /** Text shown above the panels (e.g. "Versi baru v3 akan dibuat saat disimpan"). */
  versionNote?: string;
}

export function ParticipantsEditor({ activityId, initialVersion, countries, required, onBlockingChange, onSaved, versionNote }: ParticipantsEditorProps) {
  const save = useSaveStatus();
  const initial = useMemo(() => fromVersion(initialVersion), [initialVersion]);
  const [students, setStudents] = useState<StudentRow[]>(initial.students);
  const [staff, setStaff] = useState<StaffRow[]>(initial.staff);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [warnings, setWarnings] = useState<string[]>([]);
  const [savedVersion, setSavedVersion] = useState<number | null>(initialVersion?.status === 'draft' ? initialVersion.version : null);
  const [saving, setSaving] = useState(false);
  const dirty = useRef(false);
  const seq = useRef(0);

  const blocking = students.some((s) => s.blocking) || staff.some((s) => s.blocking);
  useEffect(() => {
    onBlockingChange?.(blocking);
  }, [blocking, onBlockingChange]);

  const persist = useCallback(
    async (st: StudentRow[], sf: StaffRow[]) => {
      if (st.some((s) => s.blocking) || sf.some((s) => s.blocking)) return;
      const mySeq = ++seq.current;
      setSaving(true);
      save.setSaving();
      const payloadStudents: StudentRowPayload[] = st.map((s) =>
        s.section === 'internal'
          ? { section: 'internal', nrp: s.nrp }
          : {
              section: 'inbound',
              nrp: s.nrp,
              home_institution: s.home_institution.trim() || null,
              home_student_number: s.home_student_number.trim() || null,
              home_country_code: s.home_country_code || null,
              transcript_path: s.transcript_path,
            },
      );
      const payloadStaff: StaffRowPayload[] = sf.map((s) => ({ employee_id: s.employee_id }));
      const res = await saveParticipants(activityId, payloadStudents, payloadStaff);
      if (mySeq !== seq.current) return; // a newer save superseded this one
      setSaving(false);
      if (!res.ok) {
        setSaveError(res.message);
        save.setError(res.message);
        const errs = dbRows(res.detail);
        if (errs.length) {
          const mark = (id: string) => errs.find((e) => e.id === id);
          setStudents((rows) =>
            rows.map((r) => {
              const e = mark(r.nrp);
              return e && e.section !== 'staff'
                ? { ...r, blocking: true, status: DB_CODE_STATUS[e.code] ?? 'not_found', serverError: res.message }
                : r;
            }),
          );
          setStaff((rows) =>
            rows.map((r) => {
              const e = mark(r.employee_id);
              return e && e.section === 'staff' ? { ...r, blocking: true, status: DB_CODE_STATUS[e.code] ?? 'not_found', serverError: res.message } : r;
            }),
          );
        }
        return;
      }
      dirty.current = false;
      setSaveError(null);
      setSavedVersion(res.data.version);
      setWarnings(
        res.data.warnings.map(
          (w) => `${w.id}: ${w.status === 'graduated' ? 'sudah lulus' : 'tidak aktif'} (tetap dapat diajukan)`,
        ),
      );
      save.setSaved();
      onSaved?.(res.data.version);
    },
    [activityId, save, onSaved],
  );

  // Debounced persistence of edits to inbound text fields.
  const [tick, setTick] = useState(0);
  useEffect(() => {
    if (tick === 0) return;
    const t = setTimeout(() => void persist(students, staff), 800);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- runs only on explicit edit ticks; rows read at fire time
  }, [tick]);

  function commit(st: StudentRow[], sf: StaffRow[], immediate = true) {
    setStudents(st);
    setStaff(sf);
    dirty.current = true;
    save.setDirty();
    if (immediate) void persist(st, sf);
    else setTick((n) => n + 1);
  }

  async function addStudents(section: StudentSection, raw: string): Promise<string | null> {
    const tokens = splitIdTokens(raw);
    if (tokens.length === 0) return 'Tempel minimal satu NRP.';
    const existing = new Set(students.map((s) => s.nrp));
    const seenNow = new Set<string>();
    const rejected: string[] = [];
    const fresh: string[] = [];
    for (const t of tokens) {
      if (existing.has(t) || seenNow.has(t)) rejected.push(t);
      else fresh.push(t);
      seenNow.add(t);
    }
    if (fresh.length > 200) return 'Maksimal 200 NRP per pengecekan.';
    let results: StudentLookupResult[] = [];
    if (fresh.length) {
      const body = await postJson<{ results: StudentLookupResult[] }>('/api/lookup/students', { nrps: fresh, section });
      results = body.results;
    }
    const added: StudentRow[] = results.map((r) => ({
      key: key(),
      section,
      nrp: r.nrp,
      status: r.status,
      blocking: r.blocking,
      full_name: r.student?.full_name ?? null,
      faculty_name: r.student?.faculty_name ?? null,
      prodi_name: r.student?.prodi_name ?? null,
      home_institution: r.student?.home_institution ?? '',
      home_student_number: '',
      home_country_code: r.student?.home_country_code ?? '',
      transcript_path: null,
      transcript_href: null,
      row_note: null,
    }));
    commit([...students, ...added], staff);
    return rejected.length ? `NRP duplikat ditolak (sudah ada dalam daftar): ${[...new Set(rejected)].join(', ')}.` : null;
  }

  async function addStaff(raw: string): Promise<string | null> {
    const tokens = splitIdTokens(raw);
    if (tokens.length === 0) return 'Tempel minimal satu ID pegawai.';
    const existing = new Set(staff.map((s) => s.employee_id));
    const seenNow = new Set<string>();
    const rejected: string[] = [];
    const fresh: string[] = [];
    for (const t of tokens) {
      if (existing.has(t) || seenNow.has(t)) rejected.push(t);
      else fresh.push(t);
      seenNow.add(t);
    }
    if (fresh.length > 200) return 'Maksimal 200 ID per pengecekan.';
    let results: EmployeeLookupResult[] = [];
    if (fresh.length) {
      const body = await postJson<{ results: EmployeeLookupResult[] }>('/api/lookup/employees', { ids: fresh });
      results = body.results;
    }
    const added: StaffRow[] = results.map((r) => ({
      key: key(),
      employee_id: r.employee_id,
      status: r.status,
      blocking: r.blocking,
      full_name: r.employee?.full_name ?? null,
      unit_name: r.employee?.unit_name ?? null,
      row_note: null,
    }));
    commit(students, [...staff, ...added]);
    return rejected.length ? `ID pegawai duplikat ditolak (sudah ada dalam daftar): ${[...new Set(rejected)].join(', ')}.` : null;
  }

  const removeStudent = (k: string) => commit(students.filter((s) => s.key !== k), staff);
  const removeStaff = (k: string) => commit(students, staff.filter((s) => s.key !== k));
  const patchStudent = (k: string, patch: Partial<StudentRow>, immediate = false) =>
    commit(
      students.map((s) => (s.key === k ? { ...s, ...patch } : s)),
      staff,
      immediate,
    );

  async function uploadTranscript(row: StudentRow, file: File) {
    const fd = new FormData();
    fd.set('activity_id', activityId);
    fd.set('target', 'transcript');
    fd.set('nrp', row.nrp);
    fd.set('file', file);
    try {
      const res = await fetch('/api/upload', { method: 'POST', body: fd });
      const body = (await res.json()) as { path?: string; href?: string; message?: string };
      if (!res.ok || !body.path) throw new Error(body.message ?? 'Transkrip gagal diunggah.');
      patchStudent(row.key, { transcript_path: body.path, transcript_href: body.href ?? null }, true);
    } catch (e) {
      setSaveError(e instanceof Error ? e.message : 'Transkrip gagal diunggah.');
    }
  }

  const internal = students.filter((s) => s.section === 'internal');
  const inbound = students.filter((s) => s.section === 'inbound');
  const blockingCount = [...students, ...staff].filter((r) => r.blocking).length;

  return (
    <div className="space-y-5" data-testid="participants-editor">
      <div className="flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
        {versionNote && <span>{versionNote}</span>}
        {savedVersion !== null && (
          <Badge variant="neutral" data-testid="draft-version">
            Versi v{savedVersion} (draf)
          </Badge>
        )}
        {saving && (
          <span className="inline-flex items-center gap-1">
            <Loader2 className="h-3.5 w-3.5 animate-spin" aria-hidden /> Menyimpan peserta…
          </span>
        )}
      </div>

      {blockingCount > 0 && (
        <Alert variant="destructive" role="alert" data-testid="participants-blocking">
          <XCircle aria-hidden />
          <AlertTitle>{blockingCount} baris bermasalah — data peserta belum disimpan</AlertTitle>
          <AlertDescription>
            Hapus atau perbaiki baris bertanda ✗ (merah). Pengajuan tidak dapat dilanjutkan selama masih ada baris bermasalah.
          </AlertDescription>
        </Alert>
      )}
      {saveError && blockingCount === 0 && (
        <Alert variant="destructive" role="alert">
          <AlertCircle aria-hidden />
          <AlertDescription>{saveError}</AlertDescription>
        </Alert>
      )}
      {warnings.length > 0 && (
        <Alert variant="warning" role="status">
          <AlertTriangle aria-hidden />
          <AlertTitle>Peringatan data registri</AlertTitle>
          <AlertDescription>
            <ul className="list-disc pl-5">
              {warnings.map((w) => (
                <li key={w}>{w}</li>
              ))}
            </ul>
          </AlertDescription>
        </Alert>
      )}

      <Panel
        id="panel-internal"
        title="Mahasiswa PETRA"
        count={internal.length}
        required={required.internal}
        idLabel="NRP"
        templateKind="students"
        checkTestId="check-nrp"
        checkLabel="Cek NRP"
        onCheck={(raw) => addStudents('internal', raw)}
      >
        <StudentTable rows={internal} onRemove={removeStudent} />
      </Panel>

      <Panel
        id="panel-staff"
        title="Pegawai PETRA"
        count={staff.length}
        required={false}
        idLabel="ID pegawai"
        templateKind="staff"
        checkTestId="check-employee"
        checkLabel="Cek ID Pegawai"
        onCheck={addStaff}
      >
        {staff.length > 0 && (
          <div className="overflow-x-auto rounded-md border">
            <table className="w-full text-sm">
              <caption className="sr-only">Hasil pengecekan pegawai</caption>
              <thead className="bg-muted/50 text-left text-xs text-muted-foreground">
                <tr>
                  <th scope="col" className="px-3 py-2">Status</th>
                  <th scope="col" className="px-3 py-2">ID pegawai</th>
                  <th scope="col" className="px-3 py-2">Nama</th>
                  <th scope="col" className="px-3 py-2">Unit</th>
                  <th scope="col" className="px-3 py-2"><span className="sr-only">Aksi</span></th>
                </tr>
              </thead>
              <tbody>
                {staff.map((r) => (
                  <tr key={r.key} className={cn('border-t', rowClass(r.status, r.blocking))} data-testid="staff-row" data-status={r.status}>
                    <td className="px-3 py-2">
                      <span className="flex items-center gap-1.5">
                        <StatusIcon status={r.status} blocking={r.blocking} />
                        <span className={r.blocking ? 'font-medium text-red-800' : ''}>{STATUS_TEXT[r.status]}</span>
                      </span>
                    </td>
                    <td className="px-3 py-2 font-mono">{r.employee_id}</td>
                    <td className="px-3 py-2">{r.full_name ?? '–'}</td>
                    <td className="px-3 py-2">{r.unit_name ?? '–'}</td>
                    <td className="px-3 py-2 text-right">
                      <Button type="button" variant="ghost" size="icon" onClick={() => removeStaff(r.key)} aria-label={`Hapus ${r.employee_id}`}>
                        <Trash2 aria-hidden />
                      </Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Panel>

      <Panel
        id="panel-inbound"
        title="Mahasiswa Inbound"
        count={inbound.length}
        required={required.inbound}
        idLabel="NRP inbound"
        templateKind="students"
        checkTestId="check-nrp-inbound"
        checkLabel="Cek NRP"
        onCheck={(raw) => addStudents('inbound', raw)}
      >
        {inbound.length > 0 && (
          <ul className="space-y-3">
            {inbound.map((r) => (
              <li
                key={r.key}
                className={cn('rounded-md border p-3', rowClass(r.status, r.blocking))}
                data-testid="inbound-row"
                data-status={r.status}
              >
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <p className="flex flex-wrap items-center gap-2 text-sm">
                    <StatusIcon status={r.status} blocking={r.blocking} />
                    <span className="font-mono">{r.nrp}</span>
                    <span>{r.full_name ?? ''}</span>
                    <span className={r.blocking ? 'font-medium text-red-800' : 'text-muted-foreground'}>— {STATUS_TEXT[r.status]}</span>
                  </p>
                  <Button type="button" variant="ghost" size="icon" onClick={() => removeStudent(r.key)} aria-label={`Hapus ${r.nrp}`}>
                    <Trash2 aria-hidden />
                  </Button>
                </div>
                {r.row_note && <p className="mt-1 text-xs text-amber-800">Catatan IO: {r.row_note}</p>}
                {!r.blocking && (
                  <div className="mt-3 grid gap-3 md:grid-cols-2 lg:grid-cols-4">
                    <div className="space-y-1">
                      <Label htmlFor={`${r.key}-inst`}>Institusi asal *</Label>
                      <Input
                        id={`${r.key}-inst`}
                        value={r.home_institution}
                        onChange={(e) => patchStudent(r.key, { home_institution: e.target.value })}
                      />
                    </div>
                    <div className="space-y-1">
                      <Label htmlFor={`${r.key}-num`}>No. mahasiswa asal</Label>
                      <Input
                        id={`${r.key}-num`}
                        value={r.home_student_number}
                        onChange={(e) => patchStudent(r.key, { home_student_number: e.target.value })}
                      />
                    </div>
                    <div className="space-y-1">
                      <Label htmlFor={`${r.key}-country`}>Negara asal</Label>
                      <NativeSelect
                        id={`${r.key}-country`}
                        value={r.home_country_code}
                        placeholder="Pilih negara"
                        onChange={(e) => patchStudent(r.key, { home_country_code: e.target.value })}
                      >
                        {countries.map((c) => (
                          <option key={c.code} value={c.code}>
                            {c.name}
                          </option>
                        ))}
                      </NativeSelect>
                    </div>
                    <div className="space-y-1">
                      <p className="text-sm font-medium" id={`${r.key}-tr-label`}>
                        Transkrip (PDF) *
                      </p>
                      {r.transcript_href && (
                        <a
                          href={r.transcript_href}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="inline-flex items-center gap-1 text-xs text-primary hover:underline"
                        >
                          <FileText className="h-3.5 w-3.5" aria-hidden /> Lihat transkrip<span className="sr-only"> (tab baru)</span>
                        </a>
                      )}
                      <FileDrop
                        accept="application/pdf"
                        maxBytes={MAX_FILE_BYTES}
                        label={r.transcript_path ? 'Ganti transkrip' : 'Unggah transkrip'}
                        hint="PDF, maks. 10 MB"
                        aria-describedby={`${r.key}-tr-label`}
                        aria-invalid={!r.transcript_path || undefined}
                        onFiles={(files) => files[0] && void uploadTranscript(r, files[0])}
                      />
                    </div>
                  </div>
                )}
              </li>
            ))}
          </ul>
        )}
      </Panel>
    </div>
  );
}

function StudentTable({ rows, onRemove }: { rows: StudentRow[]; onRemove: (key: string) => void }) {
  if (rows.length === 0) return null;
  return (
    <div className="overflow-x-auto rounded-md border">
      <table className="w-full text-sm">
        <caption className="sr-only">Hasil pengecekan NRP</caption>
        <thead className="bg-muted/50 text-left text-xs text-muted-foreground">
          <tr>
            <th scope="col" className="px-3 py-2">Status</th>
            <th scope="col" className="px-3 py-2">NRP</th>
            <th scope="col" className="px-3 py-2">Nama</th>
            <th scope="col" className="px-3 py-2">Fakultas</th>
            <th scope="col" className="px-3 py-2">Prodi</th>
            <th scope="col" className="px-3 py-2"><span className="sr-only">Aksi</span></th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.key} className={cn('border-t', rowClass(r.status, r.blocking))} data-testid="student-row" data-status={r.status}>
              <td className="px-3 py-2">
                <span className="flex items-center gap-1.5">
                  <StatusIcon status={r.status} blocking={r.blocking} />
                  <span className={r.blocking ? 'font-medium text-red-800' : ''}>{STATUS_TEXT[r.status]}</span>
                </span>
                {r.row_note && <span className="mt-1 block text-xs text-amber-800">Catatan IO: {r.row_note}</span>}
              </td>
              <td className="px-3 py-2 font-mono">{r.nrp}</td>
              <td className="px-3 py-2">{r.full_name ?? '–'}</td>
              <td className="px-3 py-2">{r.faculty_name ?? '–'}</td>
              <td className="px-3 py-2">{r.prodi_name ?? '–'}</td>
              <td className="px-3 py-2 text-right">
                <Button type="button" variant="ghost" size="icon" onClick={() => onRemove(r.key)} aria-label={`Hapus ${r.nrp}`}>
                  <Trash2 aria-hidden />
                </Button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function Panel({
  id,
  title,
  count,
  required,
  idLabel,
  templateKind,
  checkTestId,
  checkLabel,
  onCheck,
  children,
}: {
  id: string;
  title: string;
  count: number;
  required: boolean;
  idLabel: string;
  templateKind: 'students' | 'staff';
  checkTestId: string;
  checkLabel: string;
  onCheck: (raw: string) => Promise<string | null>;
  children: React.ReactNode;
}) {
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<{ tone: 'error' | 'info'; text: string } | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  async function run(raw: string) {
    setBusy(true);
    setMessage(null);
    try {
      const msg = await onCheck(raw);
      setText('');
      if (msg) setMessage({ tone: 'info', text: msg });
    } catch (e) {
      setMessage({ tone: 'error', text: e instanceof Error ? e.message : 'Pengecekan gagal. Coba lagi.' });
    } finally {
      setBusy(false);
    }
  }

  async function onTemplate(file: File) {
    const fd = new FormData();
    fd.set('kind', templateKind);
    fd.set('file', file);
    setBusy(true);
    setMessage(null);
    try {
      const res = await fetch('/api/template/peserta', { method: 'POST', body: fd });
      const body = (await res.json()) as { ids?: string[]; message?: string };
      if (!res.ok || !body.ids) throw new Error(body.message ?? 'Berkas tidak dapat dibaca.');
      if (body.ids.length === 0) {
        setMessage({ tone: 'error', text: 'Tidak ada ID di kolom A berkas tersebut.' });
        return;
      }
      setBusy(false);
      await run(body.ids.join('\n'));
    } catch (e) {
      setMessage({ tone: 'error', text: e instanceof Error ? e.message : 'Berkas tidak dapat dibaca.' });
    } finally {
      setBusy(false);
      if (fileRef.current) fileRef.current.value = '';
    }
  }

  const textId = `${id}-ids`;
  return (
    <details open className="group rounded-lg border" data-testid={id}>
      <summary className="flex cursor-pointer list-none items-center gap-2 px-4 py-3 font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
        <span>{title}</span>
        <Badge variant="neutral" aria-label={`${count} baris`}>
          {count}
        </Badge>
        {required && <Badge variant="red">Wajib</Badge>}
        <span className="ml-auto text-xs text-muted-foreground group-open:hidden">Tampilkan</span>
      </summary>
      <div className="space-y-3 border-t px-4 py-4">
        <div className="space-y-1.5">
          <Label htmlFor={textId}>Tempel {idLabel} (satu per baris)</Label>
          <Textarea
            id={textId}
            rows={3}
            value={text}
            onChange={(e) => setText(e.target.value)}
            className="font-mono"
            placeholder={templateKind === 'staff' ? 'PG204517' : 'D31240187'}
          />
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <Button type="button" onClick={() => void run(text)} loading={busy} data-testid={checkTestId}>
            {checkLabel}
          </Button>
          <Button type="button" variant="outline" size="sm" onClick={() => fileRef.current?.click()} disabled={busy}>
            <Upload aria-hidden /> Unggah template Excel
          </Button>
          <input
            ref={fileRef}
            type="file"
            accept=".xlsx,.csv"
            className="sr-only"
            tabIndex={-1}
            aria-hidden
            onChange={(e) => {
              const f = e.target.files?.[0];
              if (f) void onTemplate(f);
            }}
          />
          <Button asChild variant="link" size="sm">
            <a href={`/api/template/peserta?kind=${templateKind}`} download>
              <Download aria-hidden /> Unduh template
            </a>
          </Button>
        </div>
        <p aria-live="polite" className={cn('text-sm', message?.tone === 'error' ? 'text-red-700' : 'text-amber-800')}>
          {message?.text}
        </p>
        {children}
      </div>
    </details>
  );
}
