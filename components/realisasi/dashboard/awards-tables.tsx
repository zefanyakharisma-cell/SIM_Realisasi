/**
 * International Awards tab (Revisi V.1): four leaderboards per Program Studi, ranked by total.
 * Server-safe; every number comes from realisasi.international_awards().
 */
import { Trophy } from 'lucide-react';
import { Card } from '@/components/ui/card';
import { CardMenu } from '@/components/realisasi/dashboard/card-menu';
import { formatNumber } from '@/lib/realisasi/format';
import type { AwardsData, AwardsInitiativeRow, AwardsStudentRow } from '@/lib/realisasi/types';
import { cn } from '@/lib/utils';

interface Column<T> {
  key: keyof T & string;
  label: string;
}

const STUDENT_COLUMNS: Column<AwardsStudentRow>[] = [
  { key: 'jd_dd', label: 'Program Studi JD/DD' },
  { key: 'student_exchange', label: 'Student Exchange' },
  { key: 'short_summer', label: 'Short/Summer Program' },
  { key: 'short_international', label: 'Kegiatan Internasional (<14 hari)' },
];

const INITIATIVE_COLUMNS: Column<AwardsInitiativeRow>[] = [
  { key: 'inbound', label: 'Jumlah Inbound' },
  { key: 'outbound', label: 'Jumlah Outbound' },
  { key: 'activities', label: 'Jumlah Kegiatan' },
];

/** Competition ranking (1, 2, 2, 4) on `total`; rows arrive sorted by total desc. */
function ranks(rows: Array<{ total: number }>): number[] {
  return rows.map((r, i) => (i > 0 && rows[i - 1]!.total === r.total ? -1 : i + 1)).reduce<number[]>((acc, r, i) => {
    acc.push(r === -1 ? acc[i - 1]! : r);
    return acc;
  }, []);
}

function Leaderboard<T extends { unit_id: number; unit_name: string; total: number }>({
  id,
  title,
  description,
  rows,
  columns,
  exportHref,
}: {
  id: string;
  title: string;
  description: string;
  rows: T[];
  columns: Column<T>[];
  exportHref: string;
}) {
  const rk = ranks(rows);
  return (
    <Card className="p-4" data-testid={`awards-${id}`}>
      <div className="mb-3 flex items-start justify-between gap-2">
        <div>
          <h2 id={`awards-${id}-title`} className="text-sm font-semibold">
            {title}
          </h2>
          <p className="text-xs text-muted-foreground">{description}</p>
        </div>
        <CardMenu exportHref={exportHref} label={title} />
      </div>
      {rows.length === 0 ? (
        <p className="text-sm text-muted-foreground">Belum ada data pada periode ini.</p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full min-w-[560px] text-sm" aria-labelledby={`awards-${id}-title`}>
            <thead className="text-left text-xs text-muted-foreground">
              <tr className="border-b">
                <th scope="col" className="w-12 px-2 py-2 font-medium">
                  Rank
                </th>
                <th scope="col" className="px-2 py-2 font-medium">
                  Program Studi
                </th>
                {columns.map((c) => (
                  <th key={c.key} scope="col" className="px-2 py-2 text-right font-medium">
                    {c.label}
                  </th>
                ))}
                <th scope="col" className="px-2 py-2 text-right font-semibold text-foreground">
                  Total
                </th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r, i) => {
                const top = rk[i] === 1 && r.total > 0;
                return (
                  <tr key={r.unit_id} className={cn('border-b last:border-0', top && 'bg-warning-subtle')} data-testid="awards-row">
                    <td className="px-2 py-2 tabular-nums">
                      {top ? (
                        <span className="inline-flex items-center gap-1 font-semibold text-warning-fg">
                          <Trophy className="h-3.5 w-3.5" aria-hidden /> 1
                        </span>
                      ) : (
                        rk[i]
                      )}
                    </td>
                    <th scope="row" className="px-2 py-2 text-left font-medium">
                      {r.unit_name}
                    </th>
                    {columns.map((c) => (
                      <td key={c.key} className="px-2 py-2 text-right tabular-nums">
                        {formatNumber(r[c.key] as number)}
                      </td>
                    ))}
                    <td className="px-2 py-2 text-right font-semibold tabular-nums">{formatNumber(r.total)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </Card>
  );
}

export function AwardsTables({ data, exportQuery }: { data: AwardsData; exportQuery: string }) {
  const exportHref = `/api/export/awards?${exportQuery}`;
  return (
    <div className="grid gap-4 2xl:grid-cols-2" data-testid="awards-tables">
      <Leaderboard
        id="inbound"
        title="Mahasiswa Inbound"
        description="Mahasiswa inbound pada kegiatan mobilitas inbound, per unit pengaju."
        rows={data.inbound}
        columns={STUDENT_COLUMNS}
        exportHref={exportHref}
      />
      <Leaderboard
        id="outbound-domestic"
        title="Mahasiswa Outbound Dalam Negeri"
        description="Mahasiswa PETRA pada kegiatan outbound di Indonesia, per unit pengaju."
        rows={data.outbound_domestic}
        columns={STUDENT_COLUMNS}
        exportHref={exportHref}
      />
      <Leaderboard
        id="outbound-international"
        title="Mahasiswa Outbound Internasional"
        description="Mahasiswa PETRA pada kegiatan outbound di luar negeri, per unit pengaju."
        rows={data.outbound_international}
        columns={STUDENT_COLUMNS}
        exportHref={exportHref}
      />
      <Leaderboard
        id="initiatives"
        title="Inisiatif Internasional"
        description="Jumlah kegiatan internasional terverifikasi (inbound, outbound, dan kegiatan lain), per unit pengaju."
        rows={data.initiatives}
        columns={INITIATIVE_COLUMNS}
        exportHref={exportHref}
      />
    </div>
  );
}
