// Minimal SIM Kerjasama document list with the realisasi flag (CONTRACTS §7, agreement_flags()).
import Link from 'next/link';
import { withUser } from '@/lib/db';
import { requireUser } from '@/lib/session';
import { formatDate } from '@/lib/realisasi/format';
import { getParam } from '@/lib/realisasi/schemas/report';
import { getAgreementFlags, listDocuments } from '@/lib/realisasi/queries/reports';
import { PageHeader } from '@/components/realisasi/page-header';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { NativeSelect } from '@/components/ui/native-select';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { AgreementFlagBadge } from '@/components/kerjasama/agreement-flag';

export const dynamic = 'force-dynamic';

const STATUS_LABEL: Record<string, string> = { active: 'Aktif', archived: 'Arsip', in_process: 'Dalam proses', rejected: 'Ditolak' };

export default async function DokumenPage(props: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const user = await requireUser();
  const sp = await props.searchParams;
  const q = getParam(sp, 'q')?.toLowerCase();
  const flagFilter = getParam(sp, 'flag');
  const { docs, flags } = await withUser(user.id, async (tx) => ({
    docs: await listDocuments(tx),
    flags: await getAgreementFlags(tx),
  }));
  const flagById = new Map(flags.map((f) => [f.document_id, f]));
  const rows = docs.filter(
    (d) =>
      (!q || `${d.doc_number} ${d.title} ${d.partner_names.join(' ')}`.toLowerCase().includes(q)) &&
      (!flagFilter || flagById.get(d.id)?.flag === flagFilter),
  );

  return (
    <div>
      <PageHeader title="Dokumen Kerja Sama" description="SIM Kerjasama (tampilan minimal) · status realisasi tahun akademik berjalan" />
      <form method="get" className="mb-4 flex flex-wrap items-end gap-3">
        <div className="grid gap-1">
          <Label htmlFor="doc-q" className="text-xs text-muted-foreground">Cari</Label>
          <Input id="doc-q" name="q" defaultValue={getParam(sp, 'q') ?? ''} className="w-64" placeholder="No. dokumen, judul, mitra" />
        </div>
        <div className="grid gap-1">
          <Label htmlFor="doc-flag" className="text-xs text-muted-foreground">Realisasi</Label>
          <NativeSelect id="doc-flag" name="flag" defaultValue={flagFilter ?? ''} className="w-64">
            <option value="">Semua</option>
            <option value="realized">Terealisasi</option>
            <option value="not_realized">Belum ada realisasi TA ini</option>
            <option value="grace">Masa tenggang</option>
            <option value="inactive">Tidak aktif</option>
          </NativeSelect>
        </div>
        <Button type="submit" variant="secondary">Terapkan</Button>
      </form>
      <p className="mb-2 text-sm text-muted-foreground">
        <span data-testid="list-total">{rows.length}</span> dokumen
      </p>
      <Table containerLabel="Dokumen kerja sama">
        <TableHeader>
          <TableRow>
            <TableHead>No. Dokumen</TableHead>
            <TableHead>Judul</TableHead>
            <TableHead>Mitra</TableHead>
            <TableHead>Berlaku</TableHead>
            <TableHead>Status</TableHead>
            <TableHead>Realisasi</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((d) => (
            <TableRow key={d.id}>
              <TableCell className="whitespace-nowrap">
                <Link href={`/kerjasama/dokumen/${d.id}/realisasi`} className="font-medium text-primary hover:underline">
                  {d.doc_number}
                </Link>
                <div className="text-xs text-muted-foreground">{d.kind}</div>
              </TableCell>
              <TableCell className="text-sm">{d.title}</TableCell>
              <TableCell className="text-sm">
                {d.partner_names.join(', ')}
                <div className="text-xs text-muted-foreground">{d.country_codes.join(', ')}</div>
              </TableCell>
              <TableCell className="whitespace-nowrap text-sm">
                {formatDate(d.start_date)} – {d.auto_renewed ? 'otomatis diperpanjang' : formatDate(d.end_date)}
              </TableCell>
              <TableCell>
                <Badge variant={d.status === 'active' ? 'green' : 'neutral'} appearance="outline">
                  {STATUS_LABEL[d.status] ?? d.status}
                </Badge>
              </TableCell>
              <TableCell>
                <AgreementFlagBadge flag={flagById.get(d.id)} />
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}
