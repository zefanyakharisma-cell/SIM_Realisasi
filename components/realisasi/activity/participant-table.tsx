'use client';
/**
 * Read-only participant set (one version) with optional diff highlighting (CONTRACTS §6.8; Revisi V.1:
 * no per-row notes, transcripts live in the mobility bundle PDF). Used on the activity detail page and
 * in the Verifikasi Mobilitas queue.
 * Row changes are conveyed by text labels as well as colour (Design §6).
 */
import { Badge } from '@/components/ui/badge';
import { CountryFlag } from '@/components/realisasi/country-flag';
import type { ParticipantStaffRow, ParticipantStudentRow, ParticipantVersion } from '@/lib/realisasi/types';
import { cn } from '@/lib/utils';

type Change = 'added' | 'removed' | 'changed';

export interface ParticipantTableProps {
  version: ParticipantVersion;
  highlight?: Record<string, Change>;
  removedRows?: ParticipantStudentRow[];
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

export function ParticipantTable({ version, highlight, removedRows }: ParticipantTableProps) {
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

  return (
    <div className="space-y-6" data-testid="participant-table">
      <SectionTable
        title="Mahasiswa PETRA"
        count={internal.length}
        testId="participants-internal"
        headers={['No', 'NRP', 'Nama', 'Fakultas', 'Program Studi']}
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
          </tr>
        ))}
      </SectionTable>

      <SectionTable
        title="Mahasiswa Inbound"
        count={inbound.length}
        testId="participants-inbound"
        headers={['No', 'NRP', 'Nama', 'Institusi asal', 'No. mahasiswa asal', 'Negara asal']}
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
          </tr>
        ))}
      </SectionTable>

      <SectionTable
        title="Pegawai PETRA"
        count={staff.length}
        testId="participants-staff"
        headers={['No', 'ID Pegawai', 'Nama', 'Unit']}
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
          </tr>
        ))}
      </SectionTable>
    </div>
  );
}
