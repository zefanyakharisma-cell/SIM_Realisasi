/**
 * WP-SUBMIT display helpers shared by the wizard and the activity detail page. Pure; client-safe.
 */
import type { Direction } from '@/lib/realisasi/types';

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
  kind: 'Jenis berkas',
  filename: 'Nama berkas',
  version: 'Versi',
};

export function diffFieldLabel(field: string): string {
  return DIFF_FIELD_LABEL[field] ?? field;
}

/** Helper line under the Jenis select, derived from the type's flags (Design §3.3). */
export function activityTypeHelper(t: {
  direction: Direction;
  counts_as_mobility: boolean;
  counts_for_s1: boolean;
  requires_mobility_review: boolean;
}): string {
  const parts: string[] = [];
  if (t.counts_as_mobility && t.direction === 'outbound') {
    parts.push('Dihitung sebagai mobilitas outbound — wajib isi peserta mahasiswa PETRA');
  } else if (t.counts_as_mobility && t.direction === 'inbound') {
    parts.push('Dihitung sebagai mobilitas inbound — wajib isi peserta mahasiswa inbound');
  } else if (t.requires_mobility_review) {
    parts.push('Diverifikasi tim Mobilitas — wajib isi data peserta');
  } else {
    parts.push('Tidak dihitung sebagai mobilitas — data peserta opsional');
  }
  if (t.counts_for_s1) parts.push('dihitung untuk KPI 1.19.S1 bila bermitra internasional');
  return parts.join(' · ');
}

/** Which participant panels the Jenis makes mandatory (R-11 / R-12). */
export function participantRequirements(t: { direction: Direction; requires_mobility_review: boolean } | null | undefined) {
  if (!t) return { any: false, internal: false, inbound: false };
  return {
    any: t.requires_mobility_review,
    internal: t.direction === 'outbound',
    inbound: t.direction === 'inbound',
  };
}

export function stepHref(draftId: string, step: number): string {
  return `/realisasi/kegiatan/baru?draft=${encodeURIComponent(draftId)}&step=${step}`;
}
