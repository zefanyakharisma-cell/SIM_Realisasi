'use client';
/**
 * Aturan Jenis Kegiatan (Revisi V.1): Jenis Kegiatan comes from SIM Kerjasama's Agenda Kerjasama list;
 * Realisasi only keeps how each agenda counts — its mobility category (which makes the kegiatan a
 * mobility kegiatan: participants + PDF + Verifikasi Mobilitas, RENSTRA 1.1, International Awards) and
 * whether it counts for 1.19.S1.
 */
import { useMemo, useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { Badge } from '@/components/ui/badge';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { NativeSelect } from '@/components/ui/native-select';
import { Switch } from '@/components/ui/switch';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { toast } from '@/components/ui/toaster';
import { setAgendaRule } from '@/lib/realisasi/actions/settings';
import type { AgendaRuleRow } from '@/lib/realisasi/queries/reports';
import { MOBILITY_CATEGORIES } from '@/lib/realisasi/schemas/settings';
import { MOBILITY_CATEGORY_LABEL } from '@/lib/realisasi/status';

const NOTICE = 'Berlaku untuk pengajuan baru dan perhitungan live; snapshot yang sudah dibekukan tidak berubah.';

export function AgendaRulesManager({ rules }: { rules: AgendaRuleRow[] }) {
  const router = useRouter();
  const [rows, setRows] = useState(rules);
  const [q, setQ] = useState('');
  const [pending, start] = useTransition();

  const shown = useMemo(() => {
    const needle = q.trim().toLowerCase();
    return needle ? rows.filter((r) => r.name.toLowerCase().includes(needle)) : rows;
  }, [rows, q]);

  function save(next: AgendaRuleRow) {
    const before = rows;
    setRows((rs) => rs.map((r) => (r.agenda_id === next.agenda_id ? next : r)));
    start(async () => {
      const res = await setAgendaRule({
        agenda_id: next.agenda_id,
        mobility_category: next.mobility_category,
        counts_for_s1: next.counts_for_s1,
      });
      if (res.ok) {
        toast.success(`Aturan "${next.name}" disimpan.`, { description: NOTICE });
        router.refresh();
      } else {
        toast.error(res.message);
        setRows(before);
      }
    });
  }

  return (
    <Card className="space-y-4 p-4" data-testid="agenda-rules">
      <div className="space-y-1">
        <h2 className="text-base font-semibold">Aturan Jenis Kegiatan</h2>
        <p className="text-sm text-muted-foreground">
          Daftar Jenis Kegiatan diambil dari Agenda Kerjasama di SIM Kerjasama. Jenis dengan kategori mobilitas wajib mengisi peserta dan PDF
          transkrip/poster/dokumentasi, lalu diverifikasi tim Mobilitas; jenis lainnya langsung tercatat setelah diajukan.
        </p>
      </div>
      <div className="max-w-sm">
        <label htmlFor="agenda-q" className="sr-only">
          Cari jenis kegiatan
        </label>
        <Input id="agenda-q" type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Cari jenis kegiatan…" />
      </div>
      <Table containerLabel="Aturan jenis kegiatan">
        <TableHeader>
          <TableRow>
            <TableHead>Jenis Kegiatan (SIM Kerjasama)</TableHead>
            <TableHead>Kategori mobilitas</TableHead>
            <TableHead>Dihitung 1.19.S1</TableHead>
            <TableHead className="text-right">Kegiatan</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {shown.map((r) => {
            const selId = `agenda-cat-${r.agenda_id}`;
            return (
              <TableRow key={r.agenda_id} data-testid="agenda-rule-row">
                <TableCell>
                  <label htmlFor={selId} className="font-medium">
                    {r.name}
                  </label>
                  {!r.is_active ? (
                    <Badge variant="neutral" className="ml-2">
                      Nonaktif di SIM Kerjasama
                    </Badge>
                  ) : null}
                </TableCell>
                <TableCell>
                  <NativeSelect
                    id={selId}
                    value={r.mobility_category ?? ''}
                    disabled={pending}
                    onChange={(e) =>
                      save({ ...r, mobility_category: (e.target.value || null) as AgendaRuleRow['mobility_category'] })
                    }
                    className="w-64"
                  >
                    <option value="">Bukan mobilitas</option>
                    {MOBILITY_CATEGORIES.map((c) => (
                      <option key={c} value={c}>
                        {MOBILITY_CATEGORY_LABEL[c]}
                      </option>
                    ))}
                  </NativeSelect>
                </TableCell>
                <TableCell>
                  <Switch
                    checked={r.counts_for_s1}
                    disabled={pending}
                    onCheckedChange={(v) => save({ ...r, counts_for_s1: v })}
                    aria-label={`${r.name} dihitung 1.19.S1`}
                  />
                </TableCell>
                <TableCell className="text-right tabular-nums">{r.activities}</TableCell>
              </TableRow>
            );
          })}
        </TableBody>
      </Table>
      {shown.length === 0 ? <p className="text-sm text-muted-foreground">Tidak ada jenis kegiatan yang cocok.</p> : null}
    </Card>
  );
}
