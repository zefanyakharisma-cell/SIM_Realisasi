'use client';
/**
 * Read-only participant set (one version) with optional diff highlighting and per-row note inputs
 * (CONTRACTS §6.8). Used on the activity detail page and by WP-VERIFY's Mobilitas queue.
 * Row changes are conveyed by text labels as well as colour (Design §6).
 */
import { FileText } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { CountryFlag } from '@/components/realisasi/country-flag';
import type { ParticipantStaffRow, ParticipantStudentRow, ParticipantVersion } from '@/lib/realisasi/types';
import { cn } from '@/lib/utils';

type Change = 'added' | 'removed' | 'changed';

export interface ParticipantTableProps {
  version: ParticipantVersion;
  highlight?: Record<string, Change>;
  removedRows?: ParticipantStudentRow[];
  editableRowNotes?: boolean;
  onRowNoteChange?: (kind: 'student' | 'staff', id: string, note: string) => void;
}

const CHANGE_LABEL: Record<Change, string> = { added: 'Baru', removed: 'Dihapus', changed: 'Berubah' };
const CHANGE_ROW_CLASS: Record<Change, string> = {
  added: 'bg-green-50',
  removed: 'bg-red-50 text-red-900 line-through decoration-red-400',
  changed: 'bg-amber-50',
};

const REGISTRY_LABEL: Record<string, string> = { graduated: 'Lulus', inactive: 'Tidak aktif' };

function ChangeTag({ change }: { change: Change | undefined }) {
  if (!change) return null;
  const variant = change === 'added' ? 'green' : change === 'removed' ? 'red' : 'amber';
  return (
    <Badge variant={variant} className="ml-2 no-underline">
      {CHANGE_LABEL[change]}
    </Badge>
  );
}

function RegistryTag({ status }: { status: string }) {
  const label = REGISTRY_LABEL[status];
  if (!label) return null;
  return (
    <Badge variant="amber" className="ml-2" title="Peringatan data registri (tidak memblokir)">
      ⚠ {label}
    </Badge>
  );
}

function NoteCell({
  kind,
  id,
  note,
  editable,
  onChange,
}: {
  kind: 'student' | 'staff';
  id: string;
  note: string | null;
  editable?: boolean;
  onChange?: ParticipantTableProps['onRowNoteChange'];
}) {
  if (editable) {
    return (
      <input
        type="text"
        defaultValue={note ?? ''}
        aria-label={`Catatan untuk ${id}`}
        placeholder="Catatan baris (opsional)"
        onChange={(e) => onChange?.(kind, id, e.target.value)}
        className="h-8 w-full min-w-[12rem] rounded-md border border-input bg-background px-2 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
      />
    );
  }
  return note ? <span className="text-amber-800">{note}</span> : <span className="text-muted-foreground">–</span>;
}

function SectionTable({
  title,
  count,
  headers,
  children,
  testId,
}: {
  title: string;
  count: number;
  headers: string[];
  children: React.ReactNode;
  testId: string;
}) {
  return (
    <section aria-label={title} data-testid={testId}>
      <h4 className="mb-2 text-sm font-semibold">
        {title} <span className="font-normal text-muted-foreground">({count})</span>
      </h4>
      {count === 0 ? (
        <p className="text-sm text-muted-foreground">Tidak ada data.</p>
      ) : (
        <div className="overflow-x-auto rounded-md border">
          <table className="w-full text-sm">
            <thead className="bg-muted/50 text-left text-xs text-muted-foreground">
              <tr>
                {headers.map((h) => (
                  <th key={h} scope="col" className="whitespace-nowrap px-3 py-2 font-medium">
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>{children}</tbody>
          </table>
        </div>
      )}
    </section>
  );
}

export function ParticipantTable({ version, highlight, removedRows, editableRowNotes, onRowNoteChange }: ParticipantTableProps) {
  const removed = removedRows ?? [];
  const internal: Array<{ row: ParticipantStudentRow; change?: Change }> = [
    ...version.students.filter((s) => s.section === 'internal').map((row) => ({ row, change: highlight?.[row.nrp] })),
    ...removed.filter((s) => s.section === 'internal').map((row) => ({ row, change: 'removed' as const })),
  ];
  const inbound: Array<{ row: ParticipantStudentRow; change?: Change }> = [
    ...version.students.filter((s) => s.section === 'inbound').map((row) => ({ row, change: highlight?.[row.nrp] })),
    ...removed.filter((s) => s.section === 'inbound').map((row) => ({ row, change: 'removed' as const })),
  ];
  const staff: Array<{ row: ParticipantStaffRow; change?: Change }> = version.staff.map((row) => ({
    row,
    change: highlight?.[row.employee_id],
  }));
  const showNotes = editableRowNotes || [...version.students, ...version.staff].some((r) => r.row_note);

  return (
    <div className="space-y-6" data-testid="participant-table">
      <SectionTable
        title="Mahasiswa PETRA"
        count={internal.length}
        testId="participants-internal"
        headers={['No', 'NRP', 'Nama', 'Fakultas', 'Prodi', ...(showNotes ? ['Catatan'] : [])]}
      >
        {internal.map(({ row, change }, i) => (
          <tr key={`${row.nrp}-${change ?? 'x'}`} className={cn('border-t', change && CHANGE_ROW_CLASS[change])}>
            <td className="px-3 py-2 text-muted-foreground">{i + 1}</td>
            <td className="whitespace-nowrap px-3 py-2 font-mono">
              {row.nrp}
              <ChangeTag change={change} />
            </td>
            <td className="px-3 py-2">
              {row.full_name}
              <RegistryTag status={row.registry_status} />
            </td>
            <td className="px-3 py-2">{row.faculty_name ?? '–'}</td>
            <td className="px-3 py-2">{row.prodi_name ?? '–'}</td>
            {showNotes && (
              <td className="px-3 py-2">
                <NoteCell kind="student" id={row.nrp} note={row.row_note} editable={editableRowNotes && change !== 'removed'} onChange={onRowNoteChange} />
              </td>
            )}
          </tr>
        ))}
      </SectionTable>

      <SectionTable
        title="Mahasiswa Inbound"
        count={inbound.length}
        testId="participants-inbound"
        headers={['No', 'NRP', 'Nama', 'Institusi asal', 'No. mahasiswa asal', 'Negara asal', 'Transkrip', ...(showNotes ? ['Catatan'] : [])]}
      >
        {inbound.map(({ row, change }, i) => (
          <tr key={`${row.nrp}-${change ?? 'x'}`} className={cn('border-t', change && CHANGE_ROW_CLASS[change])}>
            <td className="px-3 py-2 text-muted-foreground">{i + 1}</td>
            <td className="whitespace-nowrap px-3 py-2 font-mono">
              {row.nrp}
              <ChangeTag change={change} />
            </td>
            <td className="px-3 py-2">
              {row.full_name}
              <RegistryTag status={row.registry_status} />
            </td>
            <td className="px-3 py-2">{row.home_institution ?? '–'}</td>
            <td className="px-3 py-2">{row.home_student_number ?? '–'}</td>
            <td className="px-3 py-2">{row.home_country_code ? <CountryFlag code={row.home_country_code} /> : '–'}</td>
            <td className="px-3 py-2">
              {row.transcript_href ? (
                <a
                  href={row.transcript_href}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-1 text-primary underline-offset-2 hover:underline"
                >
                  <FileText className="h-3.5 w-3.5" aria-hidden />
                  Transkrip<span className="sr-only"> {row.nrp} (buka di tab baru)</span>
                </a>
              ) : (
                <span className="text-red-700">Belum ada</span>
              )}
            </td>
            {showNotes && (
              <td className="px-3 py-2">
                <NoteCell kind="student" id={row.nrp} note={row.row_note} editable={editableRowNotes && change !== 'removed'} onChange={onRowNoteChange} />
              </td>
            )}
          </tr>
        ))}
      </SectionTable>

      <SectionTable
        title="Pegawai PETRA"
        count={staff.length}
        testId="participants-staff"
        headers={['No', 'ID Pegawai', 'Nama', 'Unit', ...(showNotes ? ['Catatan'] : [])]}
      >
        {staff.map(({ row, change }, i) => (
          <tr key={row.employee_id} className={cn('border-t', change && CHANGE_ROW_CLASS[change])}>
            <td className="px-3 py-2 text-muted-foreground">{i + 1}</td>
            <td className="whitespace-nowrap px-3 py-2 font-mono">
              {row.employee_id}
              <ChangeTag change={change} />
            </td>
            <td className="px-3 py-2">
              {row.full_name}
              <RegistryTag status={row.registry_status} />
            </td>
            <td className="px-3 py-2">{row.unit_name ?? '–'}</td>
            {showNotes && (
              <td className="px-3 py-2">
                <NoteCell kind="staff" id={row.employee_id} note={row.row_note} editable={editableRowNotes && change !== 'removed'} onChange={onRowNoteChange} />
              </td>
            )}
          </tr>
        ))}
      </SectionTable>
    </div>
  );
}
