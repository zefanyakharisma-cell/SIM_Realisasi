/**
 * Human-readable activity diffs, shared by the Riwayat tab, the snapshot archive and the Excel
 * "Perubahan Pasca-Beku" sheet (requirements review L-2). Pure; client-safe.
 */

/** Indonesian labels for diff fields written by `save_activity_draft` / `edit_verified_activity`. */
export const DIFF_FIELD_LABEL: Record<string, string> = {
  name: 'Nama kegiatan',
  type_id: 'Jenis kegiatan',
  start_date: 'Tanggal mulai',
  end_date: 'Tanggal selesai',
  mode: 'Moda',
  venue: 'Tempat / platform',
  city: 'Kota',
  country_code: 'Negara',
  sks_recognized: 'SKS diakui',
  funding_source: 'Sumber dana',
  description: 'Deskripsi',
  submitter_unit_id: 'Unit pengaju',
  co_unit_ids: 'Unit lain',
  document_ids: 'Kerja sama',
  sdg_ids: 'SDG',
  external_persons: 'Pembicara / tamu',
  students: 'Mahasiswa',
  staff: 'Pegawai',
  row_notes: 'Catatan per baris',
  known_activity_ids: 'Kegiatan diketahui',
  split_from: 'Dipisah dari grup',
  kind: 'Jenis berkas',
  filename: 'Nama berkas',
  version: 'Versi',
};

export function diffFieldLabel(field: string): string {
  return DIFF_FIELD_LABEL[field] ?? field;
}

function show(v: unknown): string {
  if (v === null || v === undefined || v === '') return '–';
  if (typeof v === 'boolean') return v ? 'Ya' : 'Tidak';
  if (Array.isArray(v)) return v.length ? v.map(show).join(', ') : '–';
  if (typeof v === 'object') {
    const o = v as Record<string, unknown>;
    if (typeof o.full_name === 'string') return `${o.full_name}${o.institution ? ` (${String(o.institution)})` : ''}`;
    return Object.entries(o)
      .map(([k, x]) => `${diffFieldLabel(k)}: ${show(x)}`)
      .join('; ');
  }
  return String(v);
}

/** `added`/`removed` may be id lists or counts (masked diffs, WP-DB amendment 26). */
function rows(v: unknown): string | null {
  if (typeof v === 'number') return v > 0 ? `${v} baris` : null;
  if (Array.isArray(v)) return v.length ? v.map(show).join(', ') : null;
  return null;
}

/** One line per changed field: "Tempat / platform: A → B", "Mahasiswa: +X ; −Y". */
export function formatDiffLines(diff: unknown): string[] {
  if (!diff || typeof diff !== 'object') return [];
  const out: string[] = [];
  for (const [field, change] of Object.entries(diff as Record<string, unknown>)) {
    const label = diffFieldLabel(field);
    if (Array.isArray(change) && change.length === 2) {
      out.push(`${label}: ${show(change[0])} → ${show(change[1])}`);
    } else if (change && typeof change === 'object' && !Array.isArray(change) && ('added' in change || 'removed' in change)) {
      const c = change as { added?: unknown; removed?: unknown };
      const parts = [rows(c.added) && `+${rows(c.added)}`, rows(c.removed) && `−${rows(c.removed)}`].filter(Boolean);
      out.push(`${label}: ${parts.join(' ; ') || 'tidak ada perubahan baris'}`);
    } else if (field === 'row_notes' && typeof change === 'number') {
      out.push(`${label}: ${change} catatan`);
    } else {
      out.push(`${label}: ${show(change)}`);
    }
  }
  return out;
}
