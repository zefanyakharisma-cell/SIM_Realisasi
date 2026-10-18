// Arsip snapshot timeline + snapshot detail (Design §3.8). Server-safe.
import { formatDiffLines } from '@/lib/realisasi/diff-format';
import Link from 'next/link';
import { Archive, Lock, History } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Card } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { ExportButton } from '@/components/realisasi/export-button';
import { formatDate, formatDateTime, formatNumber, formatPct } from '@/lib/realisasi/format';
import { logActionLabel, TRACK_LABEL } from '@/lib/realisasi/status';
import type { LateAdditionRow, PostFreezeChangeRow, SnapshotDetail, SnapshotListRow } from '@/lib/realisasi/types';
import { EmptyRows, SummaryTable } from '@/components/realisasi/reports/kpi-tables';
import { cn } from '@/lib/utils';

export function SnapshotTimeline({ rows, selectedId }: { rows: SnapshotListRow[]; selectedId?: string }) {
  if (rows.length === 0) {
    return <EmptyRows text="Belum ada snapshot yang dibekukan untuk tahun akademik ini." />;
  }
  const byAy = new Map<string, SnapshotListRow[]>();
  for (const r of rows) byAy.set(r.ay_label, [...(byAy.get(r.ay_label) ?? []), r]);
  return (
    <div className="space-y-6">
      {[...byAy.entries()].map(([ay, items]) => (
        <section key={ay} aria-label={`Snapshot ${ay}`}>
          <h3 className="mb-2 text-sm font-semibold">Tahun Akademik {ay}</h3>
          <ol className="relative space-y-3 border-l pl-5">
            {items.map((s) => (
              <li key={s.id} className="relative" data-testid="snapshot-item">
                <span
                  aria-hidden="true"
                  className={cn(
                    'absolute -left-[27px] top-4 h-3 w-3 rounded-full border-2 border-background',
                    s.is_live ? 'bg-info' : 'bg-status-draft',
                  )}
                />
                <Card className={cn('p-4', selectedId === s.id && 'ring-2 ring-ring', !s.is_live && 'bg-muted/40')}>
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div className="min-w-0 space-y-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="font-semibold">{s.label}</span>
                        {s.is_live ? (
                          <Badge variant="blue">
                            <Lock className="h-3 w-3" aria-hidden="true" /> Berlaku
                          </Badge>
                        ) : (
                          <Badge variant="neutral" appearance="outline">
                            <History className="h-3 w-3" aria-hidden="true" /> Digantikan
                          </Badge>
                        )}
                      </div>
                      <p className="text-sm text-muted-foreground">
                        Dibekukan {formatDateTime(s.frozen_at)} oleh {s.frozen_by_name || 'Job terjadwal'} · jendela{' '}
                        {formatDate(s.window_start)} – {formatDate(s.window_end)} · cutoff {formatDate(s.cutoff_date)}
                      </p>
                      {s.refreeze_reason ? (
                        <p className="text-sm">
                          <span className="font-medium">Alasan bekukan ulang:</span> {s.refreeze_reason}
                        </p>
                      ) : null}
                      <p className="text-xs text-muted-foreground">
                        1.1 {formatNumber(s.summary?.kpi_1_1_total)} · 1.19.S1 {formatNumber(s.summary?.kpi_1_19_s1_international)} · 1.19.S4{' '}
                        {formatPct(s.summary?.kpi_1_19_24_pct)} · {formatNumber(s.late_additions)} tambahan
                        susulan · {formatNumber(s.post_freeze_changes)} perubahan pasca-beku
                      </p>
                    </div>
                    <div className="flex shrink-0 flex-wrap gap-2">
                      <Link
                        href={`/realisasi/laporan?report=arsip&ay=${s.ay_id}&snapshot=${s.id}`}
                        className="inline-flex h-9 items-center rounded-md border px-3 text-sm font-medium hover:bg-accent"
                      >
                        <Archive className="mr-1.5 h-4 w-4" aria-hidden="true" />
                        Rincian
                      </Link>
                      <ExportButton kind="snapshot" params={{ snapshot: s.id }} />
                    </div>
                  </div>
                </Card>
              </li>
            ))}
          </ol>
        </section>
      ))}
    </div>
  );
}

function LateAdditionsTable({ rows }: { rows: LateAdditionRow[] }) {
  if (rows.length === 0) return <EmptyRows text="Tidak ada tambahan susulan." />;
  return (
    <Table containerLabel="Tambahan susulan">
      <TableHeader>
        <TableRow>
          <TableHead>Kode</TableHead>
          <TableHead>Nama</TableHead>
          <TableHead>Unit</TableHead>
          <TableHead>Tanggal Mulai</TableHead>
          <TableHead>Diverifikasi</TableHead>
          <TableHead>Snapshot sebelumnya</TableHead>
          <TableHead>Dihitung di snapshot ini</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {rows.map((r) => (
          <TableRow key={r.activity_id}>
            <TableCell className="font-mono text-xs">
              <Link href={`/realisasi/kegiatan/${r.activity_id}`} className="text-primary hover:underline">
                {r.code}
              </Link>
            </TableCell>
            <TableCell>
              {r.name}
              <div className="text-xs text-muted-foreground">RENSTRA: {r.kpi_codes.join(', ')}</div>
            </TableCell>
            <TableCell className="text-sm">{r.unit_names.join(', ')}</TableCell>
            <TableCell className="whitespace-nowrap">{formatDate(r.start_date)}</TableCell>
            <TableCell className="whitespace-nowrap">{formatDateTime(r.verified_at)}</TableCell>
            <TableCell>{r.previous_snapshot_label ?? '–'}</TableCell>
            <TableCell>
              <Badge variant={r.counted_in_this_snapshot ? 'green' : 'neutral'}>{r.counted_in_this_snapshot ? 'Ya' : 'Tidak'}</Badge>
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

function diffLines(diff: PostFreezeChangeRow['diff']): string[] {
  // L-2: human field labels, same as Riwayat and the Excel sheet.
  return formatDiffLines(diff);
}

function PostFreezeTable({ rows }: { rows: PostFreezeChangeRow[] }) {
  if (rows.length === 0) return <EmptyRows text="Tidak ada perubahan pasca-beku." />;
  return (
    <Table containerLabel="Perubahan pasca-beku">
      <TableHeader>
        <TableRow>
          <TableHead>Waktu</TableHead>
          <TableHead>Kegiatan</TableHead>
          <TableHead>Jalur · Aksi</TableHead>
          <TableHead>Oleh</TableHead>
          <TableHead>Perubahan</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {rows.map((r) => (
          <TableRow key={r.log_id}>
            <TableCell className="whitespace-nowrap">{formatDateTime(r.created_at)}</TableCell>
            <TableCell>
              <Link href={`/realisasi/kegiatan/${r.activity_id}`} className="font-mono text-xs text-primary hover:underline">
                {r.code}
              </Link>
              <div className="text-sm">{r.name}</div>
            </TableCell>
            <TableCell className="text-sm">
              {r.track ? TRACK_LABEL[r.track] : '–'} · {logActionLabel(r.action)}
            </TableCell>
            <TableCell className="text-sm">{r.actor_name ?? '–'}</TableCell>
            <TableCell className="text-sm">
              {r.note ? <p className="italic">“{r.note}”</p> : null}
              <ul className="text-xs text-muted-foreground">
                {diffLines(r.diff).map((l) => (
                  <li key={l}>{l}</li>
                ))}
              </ul>
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

export function SnapshotDetailView({ detail }: { detail: SnapshotDetail }) {
  const s = detail.snapshot;
  return (
    <div className="space-y-6" data-testid="snapshot-detail">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h3 className="text-base font-semibold">Snapshot {s.label}</h3>
          <p className="text-sm text-muted-foreground">
            {s.is_live ? 'Berlaku' : 'Digantikan'} · dibekukan {formatDateTime(s.frozen_at)} oleh {s.frozen_by_name || 'Job terjadwal'}
          </p>
          {s.refreeze_reason ? <p className="text-sm">Alasan bekukan ulang: {s.refreeze_reason}</p> : null}
        </div>
        <ExportButton kind="snapshot" params={{ snapshot: s.id }} />
      </div>
      <section className="space-y-2">
        <h4 className="text-sm font-semibold">Ringkasan</h4>
        <SummaryTable values={detail.values} />
      </section>
      <section className="space-y-2">
        <h4 className="text-sm font-semibold">Tambahan susulan ({formatNumber(detail.late_additions.length)})</h4>
        <LateAdditionsTable rows={detail.late_additions} />
      </section>
      <section className="space-y-2">
        <h4 className="text-sm font-semibold">Perubahan pasca-beku ({formatNumber(detail.post_freeze_changes.length)})</h4>
        <PostFreezeTable rows={detail.post_freeze_changes} />
      </section>
    </div>
  );
}
