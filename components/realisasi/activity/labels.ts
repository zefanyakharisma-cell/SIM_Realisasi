/**
 * WP-SUBMIT display helpers shared by the wizard and the activity detail page. Pure; client-safe.
 */
import type { Direction } from '@/lib/realisasi/types';

// Diff field labels live in lib so the Excel builders share them (requirements review L-2).
export { DIFF_FIELD_LABEL, diffFieldLabel } from '@/lib/realisasi/diff-format';

/** Helper line under the Jenis select, derived from the agenda's rule (Revisi V.1). */
export function agendaHelper(a: { is_mobility: boolean; counts_for_s1: boolean }): string {
  const parts: string[] = [];
  if (a.is_mobility) {
    parts.push('Kegiatan mobilitas: wajib isi peserta, SKS diakui, dan satu PDF berisi transkrip, poster, dan dokumentasi; diverifikasi tim Mobilitas');
  } else {
    parts.push('Bukan kegiatan mobilitas: langsung tercatat setelah diajukan (tanpa verifikasi)');
  }
  if (a.counts_for_s1) parts.push('dihitung untuk RENSTRA 1.19.S1 bila bermitra internasional');
  return parts.join(' · ');
}

/** Which participant panels the kegiatan makes mandatory (R-11 / R-12): mobility + its direction. */
export function participantRequirements(a: { is_mobility: boolean; direction: Direction | null } | null | undefined) {
  if (!a || !a.is_mobility) return { any: false, internal: false, inbound: false };
  return {
    any: true,
    internal: a.direction === 'outbound',
    inbound: a.direction === 'inbound',
  };
}
