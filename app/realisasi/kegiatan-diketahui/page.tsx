import Link from 'next/link';
import { Plus } from 'lucide-react';
import { Button, buttonVariants } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { CountryFlag } from '@/components/realisasi/country-flag';
import { EmptyState } from '@/components/realisasi/empty-state';
import { ExportButton } from '@/components/realisasi/export-button';
import { Forbidden } from '@/components/realisasi/forbidden';
import { PageHeader } from '@/components/realisasi/page-header';
import { KnownFilterBar } from '@/components/realisasi/known/known-filters';
import { KnownFormSheet } from '@/components/realisasi/known/known-form-sheet';
import { KnownRowActions, KnownSuggestions } from '@/components/realisasi/known/known-row-actions';
import { withUser } from '@/lib/db';
import { can, requireUser } from '@/lib/session';
import {
  getKnownSuggestionsFor,
  getNudgeResendDays,
  listCountryOptions,
  listKnownActivities,
  listUnitOptions,
} from '@/lib/realisasi/queries/known';
import { knownFiltersToSearchParams, parseKnownFilters } from '@/lib/realisasi/schemas/known';
import { KNOWN_SOURCE_LABEL, KNOWN_STATUS_LABEL, KNOWN_STATUS_TONE } from '@/lib/realisasi/status';
import { formatDate } from '@/lib/realisasi/format';

export const metadata = { title: 'Kegiatan Diketahui · SIM Realisasi' };

export default async function KegiatanDiketahuiPage(props: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const user = await requireUser();
  if (!can(user, 'known.view')) return <Forbidden />;
  const filters = parseKnownFilters(await props.searchParams);
  const canManage = can(user, 'known.manage');

  const data = await withUser(user.id, async (tx) => {
    const rows = await listKnownActivities(tx, filters);
    const suggestions = canManage ? await getKnownSuggestionsFor(tx, rows.filter((r) => r.status === 'unmatched').map((r) => r.id)) : {};
    return {
      rows,
      suggestions,
      units: await listUnitOptions(tx),
      countries: await listCountryOptions(tx),
      resendDays: await getNudgeResendDays(tx),
    };
  });
  const { rows, suggestions, units, countries, resendDays } = data;
  const hasFilters = Object.keys(filters).length > 0;

  return (
    <div className="space-y-4">
      <PageHeader
        title="Kegiatan Diketahui"
        description="Register kegiatan internasional yang diketahui dari sumber lain, dicocokkan dengan kegiatan SIM untuk KPI 1.19.S8."
        actions={
          <>
            <ExportButton kind="known-activities" params={knownFiltersToSearchParams(filters)} />
            {canManage ? (
              <KnownFormSheet
                units={units}
                countries={countries}
                trigger={
                  <Button type="button" size="sm" data-testid="known-create">
                    <Plus aria-hidden="true" />
                    Catat kegiatan
                  </Button>
                }
              />
            ) : null}
          </>
        }
      />
      <KnownFilterBar filters={filters} units={units} />
      <p className="text-sm text-muted-foreground">
        <span data-testid="list-total" className="font-semibold text-foreground">
          {rows.length}
        </span>{' '}
        entri
      </p>
      {rows.length === 0 ? (
        hasFilters ? (
          <EmptyState
            title="Tidak ada entri yang cocok dengan filter."
            action={
              <Link href="/realisasi/kegiatan-diketahui" className={buttonVariants({ variant: 'outline', size: 'sm' })}>
                Hapus filter
              </Link>
            }
          />
        ) : (
          <EmptyState title="Belum ada kegiatan dicatat dari sumber lain." />
        )
      ) : (
        <div className="overflow-x-auto rounded-lg border bg-card" role="region" aria-label="Register kegiatan diketahui" tabIndex={0}>
          <table className="w-full min-w-[1100px] text-sm" data-testid="known-table">
            <caption className="sr-only">Register kegiatan diketahui</caption>
            <thead className="bg-muted/60 text-left">
              <tr className="border-b">
                {['Tanggal', 'Judul', 'Unit', 'Mitra / Negara', 'Sumber', 'Status', 'Kegiatan SIM', canManage ? 'Tindakan' : null]
                  .filter(Boolean)
                  .map((h) => (
                    <th key={h} scope="col" className="h-10 px-3 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                      {h}
                    </th>
                  ))}
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id} className="border-b align-top last:border-0" data-testid="known-row" data-known-id={r.id}>
                  <td className="whitespace-nowrap px-3 py-2.5">{formatDate(r.activity_date)}</td>
                  <td className="max-w-[260px] px-3 py-2.5">
                    <span className="font-medium">{r.title}</span>
                    {r.notes ? <span className="mt-0.5 block whitespace-pre-line text-xs text-muted-foreground">{r.notes}</span> : null}
                    {canManage && r.status === 'unmatched' ? (
                      <KnownFormSheet
                        units={units}
                        countries={countries}
                        row={r}
                        trigger={
                          <button type="button" className="mt-1 text-xs font-medium text-primary underline underline-offset-4">
                            Ubah<span className="sr-only"> {r.title}</span>
                          </button>
                        }
                      />
                    ) : null}
                  </td>
                  <td className="px-3 py-2.5">{r.unit_name ?? <span className="text-muted-foreground">–</span>}</td>
                  <td className="px-3 py-2.5">
                    <span className="block">{r.partner_name ?? '–'}</span>
                    {r.country_code ? <CountryFlag code={r.country_code} name={r.country_name} /> : null}
                    <span className="block text-xs text-muted-foreground">{r.is_international ? 'Internasional' : 'Domestik'}</span>
                  </td>
                  <td className="px-3 py-2.5">
                    {KNOWN_SOURCE_LABEL[r.source]}
                    {r.source_reference ? <span className="block break-all text-xs text-muted-foreground">{r.source_reference}</span> : null}
                  </td>
                  <td className="px-3 py-2.5">
                    <Badge variant={KNOWN_STATUS_TONE[r.status]} appearance="outline">
                      {KNOWN_STATUS_LABEL[r.status]}
                    </Badge>
                  </td>
                  <td className="max-w-[340px] px-3 py-2.5">
                    {r.status === 'matched' && r.matched_activity_id ? (
                      <Link href={`/realisasi/kegiatan/${r.matched_activity_id}`} className="underline underline-offset-4">
                        <span className="font-mono text-xs">{r.matched_activity_code}</span> {r.matched_activity_name}
                      </Link>
                    ) : r.status === 'unmatched' && canManage ? (
                      <KnownSuggestions row={r} suggestions={suggestions[r.id] ?? []} canManage={canManage} />
                    ) : (
                      <span className="text-muted-foreground">–</span>
                    )}
                  </td>
                  {canManage ? (
                    <td className="px-3 py-2.5">
                      <KnownRowActions row={r} resendDays={resendDays} />
                    </td>
                  ) : null}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
