// Server-safe preview tables for KPI read models (no hooks).
import Link from 'next/link';
import { Badge } from '@/components/ui/badge';
import { Hint } from '@/components/realisasi/hint';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { DIRECTION_LABEL, KNOWN_SOURCE_LABEL, FLAG_LABEL } from '@/lib/realisasi/status';
import { formatDate, formatNumber, formatPct } from '@/lib/realisasi/format';
import type {
  ActivityKpiRow,
  ChainKpiRow,
  DrilldownKpi,
  DrilldownResult,
  KnownKpiRow,
  KpiValues,
} from '@/lib/realisasi/types';
import { BUCKET_LABEL } from '@/lib/realisasi/schemas/report';

const CHAIN_STATUS: Record<ChainKpiRow['bucket'], { label: string; tone: 'green' | 'neutral' | 'amber' }> = {
  realized: { label: 'Terlaksana', tone: 'green' },
  not_realized: { label: 'Belum terlaksana', tone: 'neutral' },
  grace_excluded: { label: 'Masa tenggang', tone: 'amber' },
};

function LateAdditionPill({ show }: { show: boolean }) {
  if (!show) return null;
  return (
    <Hint content="Diverifikasi setelah snapshot periode kegiatan dibekukan">
      <Badge variant="blue" appearance="outline">
        {FLAG_LABEL.late_addition}
      </Badge>
    </Hint>
  );
}

export function EmptyRows({ text = 'Tidak ada data untuk filter ini.' }: { text?: string }) {
  return <p className="rounded-md border border-dashed p-6 text-center text-sm text-muted-foreground">{text}</p>;
}

export function ActivityKpiTable({ rows, kpi }: { rows: ActivityKpiRow[]; kpi: DrilldownKpi }) {
  if (rows.length === 0) return <EmptyRows />;
  return (
    <Table containerLabel="Rincian kegiatan KPI">
      <TableHeader>
        <TableRow>
          <TableHead>Kode</TableHead>
          <TableHead>Nama</TableHead>
          <TableHead>Unit</TableHead>
          <TableHead>Mitra · Negara</TableHead>
          <TableHead>Tanggal Mulai</TableHead>
          <TableHead>Kelompok</TableHead>
          {kpi === '1.1' ? <TableHead className="text-right">Mahasiswa</TableHead> : null}
        </TableRow>
      </TableHeader>
      <TableBody>
        {rows.map((r) => (
          <TableRow key={`${r.activity_id}-${r.bucket}`}>
            <TableCell className="whitespace-nowrap font-mono text-xs">
              <Link href={`/realisasi/kegiatan/${r.activity_id}`} className="text-primary hover:underline">
                {r.code}
              </Link>
            </TableCell>
            <TableCell>
              <div className="font-medium">{r.name}</div>
              <div className="text-xs text-muted-foreground">
                {r.type_name}
                {r.linked_count > 0 ? ` · ${r.linked_count} kegiatan tertaut` : ''}
              </div>
            </TableCell>
            <TableCell className="text-sm">{r.unit_names.join(', ')}</TableCell>
            <TableCell className="text-sm">
              {r.partner_names.join(', ')}
              <div className="text-xs text-muted-foreground">{r.country_codes.join(', ')}</div>
            </TableCell>
            <TableCell className="whitespace-nowrap text-sm">
              {formatDate(r.start_date)}
              <div className="text-xs text-muted-foreground">{r.semester_label ?? ''}</div>
            </TableCell>
            <TableCell className="text-sm">
              <div className="flex flex-wrap gap-1">
                <span>{BUCKET_LABEL[r.bucket] ?? DIRECTION_LABEL[r.direction]}</span>
                <LateAdditionPill show={r.is_late_addition} />
              </div>
            </TableCell>
            {kpi === '1.1' ? <TableCell className="text-right tabular-nums">{formatNumber(r.students)}</TableCell> : null}
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

export function ChainKpiTable({ rows }: { rows: ChainKpiRow[] }) {
  if (rows.length === 0) return <EmptyRows />;
  return (
    <Table containerLabel="Rincian kerja sama">
      <TableHeader>
        <TableRow>
          <TableHead>Dokumen (saat ini)</TableHead>
          <TableHead>Mitra · Negara</TableHead>
          <TableHead>Rantai</TableHead>
          <TableHead>Status</TableHead>
          <TableHead>Kegiatan</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {rows.map((r) => {
          const st = CHAIN_STATUS[r.bucket];
          return (
            <TableRow key={r.chain_id}>
              <TableCell>
                <Link href={`/kerjasama/dokumen/${r.current_document_id}/realisasi`} className="font-medium text-primary hover:underline">
                  {r.current_doc_number}
                </Link>
                <div className="text-xs text-muted-foreground">
                  {r.kind} · {r.title}
                </div>
                {r.doc_numbers.length > 1 ? (
                  <div className="text-xs text-muted-foreground">Rantai: {r.doc_numbers.join(' → ')}</div>
                ) : null}
              </TableCell>
              <TableCell className="text-sm">
                {r.partner_names.join(', ')}
                <div className="text-xs text-muted-foreground">
                  {r.country_codes.join(', ')} · {r.is_international ? 'Internasional' : 'Domestik'}
                </div>
              </TableCell>
              <TableCell className="whitespace-nowrap text-sm">
                {formatDate(r.chain_start)} – {r.auto_renewed ? 'otomatis diperpanjang' : formatDate(r.chain_end)}
              </TableCell>
              <TableCell>
                <div className="flex flex-col items-start gap-1">
                  <Badge variant={st.tone}>{st.label}</Badge>
                  {r.grace_until ? <span className="text-xs text-muted-foreground">s.d. {formatDate(r.grace_until)}</span> : null}
                  <LateAdditionPill show={r.is_late_addition} />
                </div>
              </TableCell>
              <TableCell className="text-sm">
                {r.activities.length === 0 ? (
                  <span className="text-muted-foreground">–</span>
                ) : (
                  <ul className="space-y-0.5">
                    {r.activities.map((a) => (
                      <li key={a.id}>
                        <Link href={`/realisasi/kegiatan/${a.id}`} className="font-mono text-xs text-primary hover:underline">
                          {a.code}
                        </Link>{' '}
                        <span className="text-xs text-muted-foreground">
                          {formatDate(a.start_date)} · via {a.original_doc_number}
                        </span>
                      </li>
                    ))}
                  </ul>
                )}
              </TableCell>
            </TableRow>
          );
        })}
      </TableBody>
    </Table>
  );
}

export function KnownKpiTable({ rows }: { rows: KnownKpiRow[] }) {
  if (rows.length === 0) return null;
  return (
    <Table containerLabel="Kegiatan belum dilaporkan">
      <TableHeader>
        <TableRow>
          <TableHead>ID</TableHead>
          <TableHead>Judul</TableHead>
          <TableHead>Tanggal</TableHead>
          <TableHead>Unit</TableHead>
          <TableHead>Mitra · Negara</TableHead>
          <TableHead>Sumber</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {rows.map((r) => (
          <TableRow key={r.known_id}>
            <TableCell className="tabular-nums">{r.known_id}</TableCell>
            <TableCell className="font-medium">
              {r.title ?? <span className="font-normal text-muted-foreground">Kegiatan internasional (rincian hanya untuk tim IO)</span>}
            </TableCell>
            <TableCell className="whitespace-nowrap">{formatDate(r.activity_date)}</TableCell>
            <TableCell>{r.unit_name ?? '–'}</TableCell>
            <TableCell>
              {r.partner_name ?? '–'} {r.country_code ? <span className="text-muted-foreground">· {r.country_code}</span> : null}
            </TableCell>
            <TableCell className="text-sm">
              {r.source ? (KNOWN_SOURCE_LABEL[r.source] ?? r.source) : '–'}
              {r.source_reference ? <div className="text-xs text-muted-foreground">{r.source_reference}</div> : null}
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

export function DrilldownTables({ dd }: { dd: DrilldownResult }) {
  const rows = dd.rows ?? [];
  const acts = rows.filter((r): r is ActivityKpiRow => r.row_type === 'activity');
  const chains = rows.filter((r): r is ChainKpiRow => r.row_type === 'chain');
  const known = rows.filter((r): r is KnownKpiRow => r.row_type === 'known');
  if (dd.kpi === '1.19.24') return <ChainKpiTable rows={chains} />;
  if (dd.kpi === '1.19.S8') {
    return (
      <div className="space-y-4">
        {!dd.bucket || dd.bucket === 'reported' ? (
          <section className="space-y-2">
            <h3 className="text-sm font-semibold">Dilaporkan via SIM ({formatNumber(acts.length)})</h3>
            <ActivityKpiTable rows={acts} kpi={dd.kpi} />
          </section>
        ) : null}
        {!dd.bucket || dd.bucket === 'unmatched_known' ? (
          <section className="space-y-2">
            <h3 className="text-sm font-semibold">Belum dilaporkan — register ({formatNumber(known.length)})</h3>
            {known.length === 0 ? <EmptyRows text="Tidak ada kegiatan internasional yang belum dilaporkan." /> : <KnownKpiTable rows={known} />}
          </section>
        ) : null}
      </div>
    );
  }
  return <ActivityKpiTable rows={acts} kpi={dd.kpi} />;
}

/** Ringkasan KPI table (same rows as the Excel "Ringkasan" sheet). */
export function SummaryTable({ values }: { values: KpiValues }) {
  const t = values.kpi_1_19_24;
  const rows: Array<[string, string, string, string]> = [
    ['1.1', 'Mahasiswa inbound', formatNumber(values.kpi_1_1.inbound), ''],
    ['1.1', 'Mahasiswa outbound', formatNumber(values.kpi_1_1.outbound), ''],
    ['1.1', 'Total mahasiswa', formatNumber(values.kpi_1_1.total), 'Pasangan (NRP, grup kegiatan) unik'],
    ['1.19.S1', 'Kegiatan internasional dengan mitra', formatNumber(values.kpi_1_19_s1.international), ''],
    ['1.19.S1', 'Kegiatan domestik (referensi)', formatNumber(values.kpi_1_19_s1.domestic), ''],
    ['1.19.24', 'Terlaksana — semua kerja sama', formatPct(t.all.pct), `${formatNumber(t.all.numerator)} dari ${formatNumber(t.all.denominator)} · ${formatNumber(t.all.grace_excluded)} masa tenggang`],
    ['1.19.24', 'Terlaksana — internasional', formatPct(t.international.pct), `${formatNumber(t.international.numerator)} dari ${formatNumber(t.international.denominator)} · ${formatNumber(t.international.grace_excluded)} masa tenggang`],
    ['1.19.24', 'Terlaksana — domestik', formatPct(t.domestic.pct), `${formatNumber(t.domestic.numerator)} dari ${formatNumber(t.domestic.denominator)} · ${formatNumber(t.domestic.grace_excluded)} masa tenggang`],
    ['1.19.S8', 'Kegiatan internasional dilaporkan via SIM', formatPct(values.kpi_1_19_s8.pct), `${formatNumber(values.kpi_1_19_s8.reported)} dilaporkan · ${formatNumber(values.kpi_1_19_s8.unmatched_known)} belum dilaporkan`],
  ];
  return (
    <Table containerLabel="Ringkasan KPI">
      <TableHeader>
        <TableRow>
          <TableHead>KPI</TableHead>
          <TableHead>Uraian</TableHead>
          <TableHead className="text-right">Nilai</TableHead>
          <TableHead>Catatan</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {rows.map(([k, d, v, n]) => (
          <TableRow key={`${k}-${d}`}>
            <TableCell className="font-mono text-xs">{k}</TableCell>
            <TableCell>{d}</TableCell>
            <TableCell className="text-right font-semibold tabular-nums">{v}</TableCell>
            <TableCell className="text-sm text-muted-foreground">{n}</TableCell>
          </TableRow>
        ))}
        {values.kpi_1_1.by_semester.map((s) => (
          <TableRow key={`sem-${s.semester_id}`}>
            <TableCell className="font-mono text-xs">1.1</TableCell>
            <TableCell>{s.label}</TableCell>
            <TableCell className="text-right font-semibold tabular-nums">{formatNumber(s.inbound + s.outbound)}</TableCell>
            <TableCell className="text-sm text-muted-foreground">
              Inbound {formatNumber(s.inbound)} · Outbound {formatNumber(s.outbound)}
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
