/**
 * Read-only Detail summary of an activity (CONTRACTS §6.8). Server-safe: no hooks, no handlers.
 * Imported by WP-VERIFY's Kemitraan queue (compact) and used on the detail page / wizard review.
 */
import Link from 'next/link';
import { AlertTriangle, Archive } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { CountryFlag } from '@/components/realisasi/country-flag';
import { sdgStyle } from '@/components/realisasi/activity/sdg';
import { formatDate, formatNumber } from '@/lib/realisasi/format';
import { DIRECTION_LABEL, FUNDING_LABEL, MODE_LABEL, PERSON_ROLE_LABEL } from '@/lib/realisasi/status';
import type { ActivityDetail } from '@/lib/realisasi/types';
import { cn } from '@/lib/utils';

function Field({ label, children, wide }: { label: string; children: React.ReactNode; wide?: boolean }) {
  return (
    <div className={cn('min-w-0', wide && 'sm:col-span-2')}>
      <dt className="text-xs font-medium text-muted-foreground">{label}</dt>
      <dd className="mt-0.5 break-words text-sm">{children}</dd>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section aria-label={title} className="space-y-3">
      <h3 className="text-sm font-semibold">{title}</h3>
      {children}
    </section>
  );
}

const DASH = '–';

export function ActivityDetailSummary({ detail, compact = false }: { detail: ActivityDetail; compact?: boolean }) {
  const otherUnits = detail.units.filter((u) => !u.is_submitter);
  const location =
    detail.mode === 'online'
      ? detail.venue ?? DASH
      : [detail.venue, detail.city, detail.country_name ?? detail.country_code].filter(Boolean).join(', ') || DASH;

  return (
    <div className={cn('space-y-6', compact && 'space-y-4')} data-testid="activity-detail-summary">
      <Section title="Informasi kegiatan">
        <dl className="grid gap-x-6 gap-y-3 sm:grid-cols-2">
          <Field label="Jenis kegiatan">
            {detail.type.name}
            {detail.type.direction !== 'none' && (
              <span className="text-muted-foreground"> · {DIRECTION_LABEL[detail.type.direction]}</span>
            )}
          </Field>
          <Field label="Tanggal">
            {formatDate(detail.start_date)} – {formatDate(detail.end_date)}{' '}
            <span className="text-muted-foreground">({formatNumber(detail.duration_days)} hari)</span>
          </Field>
          <Field label="Semester · Tahun akademik">
            {detail.semester?.label ?? <span className="text-amber-700">Di luar tahun akademik terdaftar</span>}
          </Field>
          <Field label="Moda">{MODE_LABEL[detail.mode]}</Field>
          <Field label={detail.mode === 'online' ? 'Platform' : 'Tempat'}>{location}</Field>
          {!compact && (
            <>
              <Field label="SKS diakui">{detail.sks_recognized ?? DASH}</Field>
              <Field label="Sumber dana">{detail.funding_source ? FUNDING_LABEL[detail.funding_source] : DASH}</Field>
              <Field label="Batas pelaporan">{formatDate(detail.reporting_deadline)}</Field>
            </>
          )}
          <Field label="Unit pengaju">{detail.submitter_unit.name}</Field>
          <Field label="Unit lain">{otherUnits.length ? otherUnits.map((u) => u.name).join(', ') : DASH}</Field>
          <Field label="Deskripsi" wide>
            <p className={cn('whitespace-pre-line', compact && 'line-clamp-4')}>{detail.description}</p>
          </Field>
        </dl>
      </Section>

      <Section title={`Kerja sama (${detail.documents.length})`}>
        {detail.documents.length === 0 ? (
          <p className="text-sm text-muted-foreground">Belum ada kerja sama yang dipilih.</p>
        ) : (
          <ul className="grid gap-3 md:grid-cols-2">
            {detail.documents.map((d) => (
              <li key={d.original_document_id} className="rounded-md border p-3 text-sm">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-medium">{d.original_doc_number}</span>
                  <Badge variant="outline">{d.kind}</Badge>
                  {d.is_archived && (
                    <Badge variant="neutral">
                      <Archive className="mr-1 h-3 w-3" aria-hidden />
                      Arsip (diperbarui)
                    </Badge>
                  )}
                </div>
                <p className="mt-1 text-muted-foreground">{d.title}</p>
                {d.current_document_id !== d.original_document_id && (
                  <p className="mt-1 text-xs text-muted-foreground">
                    Dokumen saat ini: <span className="font-medium text-foreground">{d.current_doc_number}</span>
                  </p>
                )}
                <p className="mt-1 text-xs text-muted-foreground">
                  Berlaku {formatDate(d.start_date)} – {formatDate(d.end_date)}
                </p>
                <ul className="mt-2 space-y-1" aria-label="Mitra">
                  {d.partners.map((p) => (
                    <li key={p.partner_id} className="flex items-center gap-2">
                      <CountryFlag code={p.country_code} name={p.country_name} />
                      <span>{p.name}</span>
                    </li>
                  ))}
                </ul>
                {d.out_of_scope_warning && (
                  <p className="mt-2 flex items-start gap-1.5 rounded bg-amber-50 p-2 text-xs text-amber-900">
                    <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" aria-hidden />
                    Unit pengaju tidak termasuk dalam Lingkup Kerja Sama dokumen ini.
                  </p>
                )}
              </li>
            ))}
          </ul>
        )}
        {detail.partners.length > 0 && (
          <p className="text-xs text-muted-foreground">
            Mitra tercatat saat pengajuan:{' '}
            {[...new Map(detail.partners.map((p) => [p.partner_id, p])).values()]
              .map((p) => `${p.partner_name} (${p.country_name ?? p.country_code})`)
              .join('; ')}
          </p>
        )}
      </Section>

      <Section title={`Pembicara / Dosen Asing / Tamu (${detail.external_persons.length})`}>
        {detail.external_persons.length === 0 ? (
          <p className="text-sm text-muted-foreground">Tidak ada.</p>
        ) : (
          <div className="overflow-x-auto rounded-md border">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs text-muted-foreground">
                <tr>
                  <th scope="col" className="px-3 py-2 font-medium">Nama</th>
                  <th scope="col" className="px-3 py-2 font-medium">Institusi</th>
                  <th scope="col" className="px-3 py-2 font-medium">Negara</th>
                  <th scope="col" className="px-3 py-2 font-medium">Peran</th>
                </tr>
              </thead>
              <tbody>
                {detail.external_persons.map((p) => (
                  <tr key={p.id} className="border-t">
                    <td className="px-3 py-2">{p.full_name}</td>
                    <td className="px-3 py-2">{p.institution}</td>
                    <td className="px-3 py-2">
                      <CountryFlag code={p.country_code} />
                    </td>
                    <td className="px-3 py-2">
                      {PERSON_ROLE_LABEL[p.role]}
                      {p.notes && <span className="block text-xs text-muted-foreground">{p.notes}</span>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Section>

      {!compact && (
        <Section title="SDG terkait">
          {detail.sdg_ids.length === 0 ? (
            <p className="text-sm text-muted-foreground">Tidak ada SDG dipilih.</p>
          ) : (
            <ul className="flex flex-wrap gap-2">
              {detail.sdg_ids.map((id) => {
                const s = sdgStyle(id);
                return (
                  <li
                    key={id}
                    className="rounded-full px-3 py-1 text-xs font-medium"
                    style={{ backgroundColor: s.color, color: s.text }}
                  >
                    SDG {id} · {s.name}
                  </li>
                );
              })}
            </ul>
          )}
        </Section>
      )}

      {detail.linked_activities.length > 0 && (
        <Section title="Kegiatan tertaut (satu grup kegiatan)">
          <ul className="space-y-1 text-sm">
            {detail.linked_activities.map((a) => (
              <li key={a.id}>
                <Link href={`/realisasi/kegiatan/${a.id}`} className="text-primary underline-offset-2 hover:underline">
                  {a.code} · {a.name}
                </Link>{' '}
                <span className="text-muted-foreground">({a.unit_name})</span>
              </li>
            ))}
          </ul>
        </Section>
      )}
    </div>
  );
}
