// Realization evidence for an agreement (PRD §7.6, requirements review M-1). Server-safe.
// Used on the SIM Kerjasama "Realisasi" tab and on the renewal-evaluation page.
import { formatDate, formatNumber } from '@/lib/realisasi/format';
import type { AgreementRealization } from '@/lib/realisasi/types';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';

export interface AcademicYearRange {
  id: number;
  label: string;
  start_date: string;
  end_date: string;
}

function Stat({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="rounded-lg border bg-background p-4">
      <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className="mt-1 text-2xl font-semibold">{value}</p>
      {sub ? <p className="text-xs text-muted-foreground">{sub}</p> : null}
    </div>
  );
}

/** Verified activities of the chain per academic year (by start date), newest year first. */
export function countsPerAcademicYear(
  activities: AgreementRealization['activities'],
  years: AcademicYearRange[],
): Array<{ year: AcademicYearRange; verified: number; last: string | null }> {
  return years
    .map((year) => {
      const inYear = activities.filter((a) => a.status === 'verified' && a.start_date >= year.start_date && a.start_date <= year.end_date);
      const last = inYear.reduce<string | null>((m, a) => (m === null || a.start_date > m ? a.start_date : m), null);
      return { year, verified: inYear.length, last };
    })
    .filter((r) => r.verified > 0)
    .sort((a, b) => b.year.start_date.localeCompare(a.year.start_date));
}

/**
 * Summary strip (total, this AY, students in/out, last activity) and — with `years` — a per-AY
 * breakdown. The strip comes from `agreement_realization().summary` (complete counts); the per-AY
 * table is built from the activities the viewer may see (WP-DB amendment 27).
 */
export function RealizationSummary({
  ar,
  years,
  headingId,
}: {
  ar: AgreementRealization;
  years?: AcademicYearRange[];
  headingId?: string;
}) {
  const { summary } = ar;
  const perYear = years ? countsPerAcademicYear(ar.activities, years) : null;
  return (
    <div className="space-y-4">
      <section aria-labelledby={headingId} aria-label={headingId ? undefined : 'Ringkasan realisasi'} className="grid grid-cols-2 gap-3 lg:grid-cols-4" data-testid="realization-summary">
        <Stat label="Total kegiatan" value={formatNumber(summary.total_activities)} sub="seluruh rantai perpanjangan" />
        <Stat label="Tahun akademik ini" value={formatNumber(summary.activities_this_ay)} sub={ar.current_ay ? `TA ${ar.current_ay.label}` : undefined} />
        <Stat
          label="Mahasiswa (in/out)"
          value={`${formatNumber(summary.students_inbound)} / ${formatNumber(summary.students_outbound)}`}
          sub="inbound / outbound, versi disetujui"
        />
        <Stat label="Kegiatan terakhir" value={formatDate(summary.last_activity_date)} />
      </section>
      {perYear ? (
        perYear.length === 0 ? (
          <p className="text-sm text-muted-foreground" data-testid="realization-per-ay-empty">
            Belum ada kegiatan terverifikasi pada rantai kerja sama ini.
          </p>
        ) : (
          <div className="space-y-1">
            <Table containerLabel="Kegiatan terverifikasi per tahun akademik">
              <TableHeader>
                <TableRow>
                  <TableHead>Tahun akademik</TableHead>
                  <TableHead className="text-right">Kegiatan terverifikasi</TableHead>
                  <TableHead>Kegiatan terakhir</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {perYear.map((r) => (
                  <TableRow key={r.year.id} data-testid="realization-per-ay-row">
                    <TableCell>TA {r.year.label}</TableCell>
                    <TableCell className="text-right">{formatNumber(r.verified)}</TableCell>
                    <TableCell>{formatDate(r.last)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
            {ar.activities.length < summary.total_activities ? (
              <p className="text-xs text-muted-foreground">Rincian per tahun hanya memuat kegiatan yang dapat Anda lihat.</p>
            ) : null}
          </div>
        )
      ) : null}
    </div>
  );
}
