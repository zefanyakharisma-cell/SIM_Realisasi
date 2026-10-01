// SIM Kerjasama → Realisasi tab (Design §3.10): summary strip, chain activities, "Dokumen saat kegiatan".
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { ArrowLeft, Hourglass, Link2 } from 'lucide-react';
import { withUser } from '@/lib/db';
import { requireUser } from '@/lib/session';
import { parseDbError } from '@/lib/realisasi/errors';
import { formatDate, formatNumber } from '@/lib/realisasi/format';
import { getAgreementRealization } from '@/lib/realisasi/queries/reports';
import type { AgreementRealization } from '@/lib/realisasi/types';
import { PageHeader } from '@/components/realisasi/page-header';
import { EmptyState } from '@/components/realisasi/empty-state';
import { ExportButton } from '@/components/realisasi/export-button';
import { StatusBadge } from '@/components/realisasi/status-badge';
import { Badge } from '@/components/ui/badge';
import { Card } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';

export const dynamic = 'force-dynamic';

const DOC_STATUS: Record<string, string> = { active: 'Aktif', archived: 'Arsip', in_process: 'Dalam proses', rejected: 'Ditolak' };

function Stat({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="rounded-lg border bg-background p-4">
      <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className="mt-1 text-2xl font-semibold">{value}</p>
      {sub ? <p className="text-xs text-muted-foreground">{sub}</p> : null}
    </div>
  );
}

export default async function RealisasiTabPage(props: { params: Promise<{ id: string }> }) {
  const user = await requireUser();
  const { id } = await props.params;
  if (!/^\d{1,9}$/.test(id)) notFound();

  let ar: AgreementRealization;
  try {
    ar = await withUser(user.id, (tx) => getAgreementRealization(tx, Number(id)));
  } catch (e) {
    if (parseDbError(e).code === 'NOT_FOUND') notFound();
    throw e;
  }
  if (!ar?.document) notFound();

  const { document: doc, chain, summary, grace, activities } = ar;

  return (
    <div className="space-y-6">
      <Link href="/kerjasama/dokumen" className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground">
        <ArrowLeft className="h-4 w-4" aria-hidden="true" /> Dokumen kerja sama
      </Link>
      <PageHeader
        title={doc.doc_number}
        description={
          <span>
            {doc.kind} · {doc.title} · {DOC_STATUS[doc.status] ?? doc.status} · berlaku {formatDate(doc.start_date)} –{' '}
            {doc.auto_renewed ? 'otomatis diperpanjang' : formatDate(doc.end_date)}
          </span>
        }
        actions={<ExportButton kind="agreement-activities" params={{ document_id: String(doc.id) }} />}
      />

      <nav aria-label="Tab dokumen" className="flex gap-1 border-b">
        <span className="-mb-px cursor-not-allowed border-b-2 border-transparent px-4 py-2 text-sm text-muted-foreground" aria-disabled="true" title="Tersedia di SIM Kerjasama">
          Detail
        </span>
        <span aria-current="page" className="-mb-px border-b-2 border-primary px-4 py-2 text-sm font-medium text-primary">
          Realisasi
        </span>
      </nav>

      <section aria-label="Ringkasan realisasi" className="grid grid-cols-2 gap-3 lg:grid-cols-4" data-testid="realization-summary">
        <Stat label="Total kegiatan" value={formatNumber(summary.total_activities)} sub="seluruh rantai perpanjangan" />
        <Stat
          label="Tahun akademik ini"
          value={formatNumber(summary.activities_this_ay)}
          sub={ar.current_ay ? `TA ${ar.current_ay.label}` : undefined}
        />
        <Stat
          label="Mahasiswa (in/out)"
          value={`${formatNumber(summary.students_inbound)} / ${formatNumber(summary.students_outbound)}`}
          sub="inbound / outbound, versi disetujui"
        />
        <Stat label="Kegiatan terakhir" value={formatDate(summary.last_activity_date)} />
      </section>

      {chain && chain.documents.length > 1 ? (
        <Card className="p-4">
          <h2 className="mb-2 flex items-center gap-2 text-sm font-semibold">
            <Link2 className="h-4 w-4" aria-hidden="true" /> Rantai perpanjangan
          </h2>
          <ol className="flex flex-wrap items-center gap-2 text-sm">
            {chain.documents.map((d, i) => (
              <li key={d.id} className="flex items-center gap-2">
                {i > 0 ? <span aria-hidden="true">→</span> : null}
                <Link
                  href={`/kerjasama/dokumen/${d.id}/realisasi`}
                  className={d.id === doc.id ? 'font-semibold' : 'text-primary hover:underline'}
                  aria-current={d.id === doc.id ? 'page' : undefined}
                >
                  {d.doc_number}
                </Link>
                <span className="text-xs text-muted-foreground">
                  ({formatDate(d.start_date)} – {formatDate(d.end_date)}, {DOC_STATUS[d.status] ?? d.status})
                </span>
              </li>
            ))}
          </ol>
        </Card>
      ) : null}

      {activities.length === 0 ? (
        <EmptyState
          title="Belum ada realisasi untuk kerja sama ini"
          description={
            grace.in_grace ? (
              <span className="inline-flex items-center gap-1" data-testid="grace-note">
                <Hourglass className="h-4 w-4" aria-hidden="true" />
                Dalam masa tenggang hingga {formatDate(grace.grace_until)} — belum dihitung dalam penyebut KPI 1.19.24.
              </span>
            ) : undefined
          }
        />
      ) : (
        <div className="space-y-2">
          {grace.in_grace ? (
            <Badge variant="blue">Dalam masa tenggang hingga {formatDate(grace.grace_until)}</Badge>
          ) : null}
          <Table containerLabel="Kegiatan realisasi">
            <TableHeader>
              <TableRow>
                <TableHead>Kode</TableHead>
                <TableHead>Nama</TableHead>
                <TableHead>Tanggal</TableHead>
                <TableHead>Unit</TableHead>
                <TableHead>Dokumen saat kegiatan</TableHead>
                <TableHead>Status</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {activities.map((a) => (
                <TableRow key={a.id} data-testid="agreement-activity-row">
                  <TableCell className="whitespace-nowrap font-mono text-xs">
                    <Link href={`/realisasi/kegiatan/${a.id}`} className="text-primary hover:underline">
                      {a.code}
                    </Link>
                  </TableCell>
                  <TableCell>
                    <div className="font-medium">{a.name}</div>
                    <div className="text-xs text-muted-foreground">{a.type_name}</div>
                  </TableCell>
                  <TableCell className="whitespace-nowrap text-sm">
                    {formatDate(a.start_date)} – {formatDate(a.end_date)}
                  </TableCell>
                  <TableCell className="text-sm">{a.unit_names.join(', ')}</TableCell>
                  <TableCell className="text-sm" data-testid="doc-at-activity">
                    {a.original_doc_number}
                    {a.original_doc_number !== a.current_doc_number ? (
                      <div className="text-xs text-muted-foreground">kini {a.current_doc_number}</div>
                    ) : null}
                  </TableCell>
                  <TableCell>
                    <StatusBadge status={a.status} />
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}
    </div>
  );
}
