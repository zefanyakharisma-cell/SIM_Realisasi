// SIM Kerjasama → renewal evaluation (PRD §7.6 bullet 3, Architecture §7 "Renewal evaluation";
// requirements review M-1): the realization summary shown as evidence for the renewal decision.
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { ArrowLeft, Hourglass, Info } from 'lucide-react';
import { withUser } from '@/lib/db';
import { requireUser } from '@/lib/session';
import { parseDbError } from '@/lib/realisasi/errors';
import { formatDate } from '@/lib/realisasi/format';
import { getAgreementRealization, listAcademicYears } from '@/lib/realisasi/queries/reports';
import type { AgreementRealization } from '@/lib/realisasi/types';
import { PageHeader } from '@/components/realisasi/page-header';
import { ExportButton } from '@/components/realisasi/export-button';
import { DocumentTabs } from '@/components/realisasi/agreements/document-tabs';
import { RealizationSummary, type AcademicYearRange } from '@/components/realisasi/agreements/realization-summary';
import { Alert, AlertDescription } from '@/components/ui/alert';

export const dynamic = 'force-dynamic';
export const metadata = { title: 'Evaluasi Perpanjangan · SIM Realisasi' };

export default async function EvaluasiPage(props: { params: Promise<{ id: string }> }) {
  const user = await requireUser();
  const { id } = await props.params;
  if (!/^\d{1,9}$/.test(id)) notFound();

  let ar: AgreementRealization;
  let years: AcademicYearRange[];
  try {
    ({ ar, years } = await withUser(user.id, async (tx) => ({
      ar: await getAgreementRealization(tx, Number(id)),
      years: await listAcademicYears(tx),
    })));
  } catch (e) {
    if (parseDbError(e).code === 'NOT_FOUND') notFound();
    throw e;
  }
  if (!ar?.document) notFound();
  const { document: doc, chain, grace } = ar;
  const end = chain?.auto_renewed ? null : (chain?.chain_end ?? doc.end_date);

  return (
    <div className="space-y-6">
      <Link href="/kerjasama/dokumen" className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground">
        <ArrowLeft className="h-4 w-4" aria-hidden="true" /> Dokumen kerja sama
      </Link>
      <PageHeader
        title={`Evaluasi perpanjangan ${doc.doc_number}`}
        description={`${doc.kind} · ${doc.title}`}
        actions={<ExportButton kind="agreement-activities" params={{ document_id: String(doc.id) }} />}
      />
      <DocumentTabs id={doc.id} current="evaluasi" />

      <section aria-labelledby="eval-evidence" className="space-y-3">
        <h2 id="eval-evidence" className="text-lg font-semibold">
          Bukti realisasi untuk evaluasi perpanjangan
        </h2>
        <p className="text-sm text-muted-foreground">
          Rantai kerja sama berlaku {formatDate(chain?.chain_start ?? doc.start_date)} –{' '}
          {end ? formatDate(end) : 'otomatis diperpanjang'}. Angka dihitung dari kegiatan terverifikasi pada seluruh rantai
          perpanjangan.
        </p>
        <RealizationSummary ar={ar} years={years} headingId="eval-evidence" />
        {grace.in_grace ? (
          <Alert variant="info">
            <Hourglass aria-hidden="true" />
            <AlertDescription>
              Dalam masa tenggang hingga {formatDate(grace.grace_until)} — kerja sama baru belum dihitung dalam penyebut RENSTRA 1.19.24.
            </AlertDescription>
          </Alert>
        ) : null}
        {ar.summary.total_activities === 0 && !grace.in_grace ? (
          <Alert variant="warning" data-testid="eval-no-realization">
            <Info aria-hidden="true" />
            <AlertDescription>Belum ada realisasi yang terverifikasi untuk kerja sama ini.</AlertDescription>
          </Alert>
        ) : null}
        <p className="text-sm">
          <Link href={`/kerjasama/dokumen/${doc.id}/realisasi`} className="font-medium text-primary underline underline-offset-4">
            Lihat daftar kegiatan realisasi
          </Link>
        </p>
      </section>
    </div>
  );
}
