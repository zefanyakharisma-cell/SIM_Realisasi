/**
 * Status language (Design.md §2, CONTRACTS §6.6). Pure; client-safe.
 */
import type {
  ActivityMode,
  ActivityStatus,
  ConflictStatus,
  Direction,
  FileKind,
  LogKind,
  MobilityCategory,
  Period,
  PersonRole,
  PsetStatus,
  Role,
  SnapshotKind,
  StudentSection,
  Team,
  TrackStatus,
} from '@/lib/realisasi/types';

export type Tone = 'neutral' | 'blue' | 'amber' | 'green' | 'red' | 'purple' | 'yellow';

export const ACTIVITY_STATUS_LABEL: Record<ActivityStatus, string> = {
  draft: 'Draf',
  in_verification: 'Dalam Verifikasi',
  revision_requested: 'Perlu Revisi',
  verified: 'Terverifikasi',
};

export const ACTIVITY_STATUS_TONE: Record<ActivityStatus, Tone> = {
  draft: 'neutral',
  in_verification: 'blue',
  revision_requested: 'amber',
  verified: 'green',
};

/** Tooltip text so status is never conveyed by colour alone (Design §6). */
export const ACTIVITY_STATUS_DESCRIPTION: Record<ActivityStatus, string> = {
  draft: 'Belum diajukan ke International Office.',
  in_verification: 'Menunggu Verifikasi Mobilitas oleh International Office.',
  revision_requested: 'Tim Mobilitas meminta perbaikan dari unit.',
  verified: 'Tercatat dan dihitung dalam capaian Renstra.',
};

export const TRACK_STATUS_LABEL: Record<TrackStatus, string> = {
  not_required: 'Tidak diperlukan',
  pending: 'Menunggu',
  revision_requested: 'Perlu Revisi',
  approved: 'Disetujui',
};

export const TRACK_STATUS_TONE: Record<TrackStatus, Tone> = {
  not_required: 'neutral',
  pending: 'blue',
  revision_requested: 'amber',
  approved: 'green',
};

export const TRACK_LABEL: Record<Team, string> = {
  mobility: 'Mobilitas',
};

export const PSET_STATUS_LABEL: Record<PsetStatus, string> = {
  draft: 'Draf',
  pending: 'Menunggu',
  revision_requested: 'Perlu Revisi',
  approved: 'Disetujui',
  superseded: 'Digantikan',
};

export const PSET_STATUS_TONE: Record<PsetStatus, Tone> = {
  draft: 'neutral',
  pending: 'blue',
  revision_requested: 'amber',
  approved: 'green',
  superseded: 'neutral',
};

export const CONFLICT_STATUS_LABEL: Record<ConflictStatus, string> = {
  open: 'Menunggu keputusan',
  resolved: 'Diputuskan',
};

export const CONFLICT_STATUS_TONE: Record<ConflictStatus, Tone> = {
  open: 'purple',
  resolved: 'green',
};

/** International Awards categories (Revisi V.1). */
export const MOBILITY_CATEGORY_LABEL: Record<MobilityCategory, string> = {
  jd_dd: 'Joint Degree / Double Degree',
  student_exchange: 'Student Exchange',
  short_summer: 'Short / Summer Program',
  other_mobility: 'Mobilitas lainnya',
};

export const DIRECTION_LABEL: Record<Direction, string> = {
  inbound: 'Inbound',
  outbound: 'Outbound',
};

export const MODE_LABEL: Record<ActivityMode, string> = {
  offline: 'Luring',
  online: 'Daring',
  hybrid: 'Hibrida',
};

export const PERSON_ROLE_LABEL: Record<PersonRole, string> = {
  speaker: 'Pembicara',
  visiting_lecturer: 'Dosen Tamu / Asing',
  researcher: 'Peneliti',
  staff_visitor: 'Staf Tamu',
  other: 'Lainnya',
};

export const FILE_KIND_LABEL: Record<FileKind, string> = {
  ia: 'Implementation Arrangement',
  ir: 'Implementation Report',
  mobility_bundle: 'Transkrip, Poster & Dokumentasi (PDF)',
  evidence: 'Bukti',
};

export const SECTION_LABEL: Record<StudentSection, string> = {
  internal: 'Mahasiswa PETRA',
  inbound: 'Mahasiswa Inbound',
};

export const SNAPSHOT_KIND_LABEL: Record<SnapshotKind, string> = {
  ganjil_ytd: 'Ganjil',
  genap_full_year: 'Setahun',
};

/** Revisi V.1 cut-offs for charts and Excel downloads. */
export const PERIOD_LABEL: Record<Period, string> = {
  ganjil: 'Ganjil',
  genap: 'Genap',
  full: 'Setahun (kumulatif)',
  ytd: 'YTD',
};

export const ROLE_LABEL: Record<Role, string> = {
  submitter: 'Pengaju Unit',
  io_staff: 'Staf IO',
  io_admin: 'Admin IO',
  viewer: 'Pimpinan (lihat saja)',
};

export const LOG_KIND_LABEL: Record<LogKind, string> = {
  verification: 'Verifikasi',
  revision: 'Revisi',
  update: 'Perubahan',
  system: 'Sistem',
};

/** `activity_log.action` labels; unknown actions fall back via `logActionLabel`. */
export const LOG_ACTION_LABEL: Record<string, string> = {
  create: 'Draf dibuat',
  submit: 'Diajukan',
  resubmit: 'Diajukan ulang',
  approve: 'Disetujui',
  request_revision: 'Diminta revisi',
  edit: 'Diubah',
  edit_detail: 'Detail diperbaiki',
  file_upload: 'Berkas diunggah',
  file_remove: 'Berkas dihapus',
  resolve_conflict: 'Keputusan duplikat mahasiswa',
};

export function logActionLabel(action: string): string {
  return LOG_ACTION_LABEL[action] ?? action;
}

export const FLAG_LABEL = {
  late: 'Terlambat',
  out_of_scope: 'Di luar lingkup',
  conflict: 'Duplikat mahasiswa',
  late_addition: 'Tambahan susulan',
} as const;

export type FlagKey = keyof typeof FLAG_LABEL;

/** Outline colour per flag (Design §2). */
export const FLAG_TONE: Record<FlagKey, Tone> = {
  late: 'amber',
  out_of_scope: 'neutral',
  conflict: 'purple',
  late_addition: 'blue',
};

export const FLAG_DESCRIPTION: Record<FlagKey, string> = {
  late: 'Diajukan setelah batas pelaporan.',
  out_of_scope: 'Unit pengaju tidak termasuk dalam Lingkup Kerja Sama dokumen.',
  conflict: 'Ada mahasiswa yang juga diklaim unit lain; menunggu keputusan tim Mobilitas.',
  late_addition: 'Diverifikasi setelah snapshot periode kegiatan dibekukan.',
};
