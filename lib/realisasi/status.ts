/**
 * Status language (Design.md §2, CONTRACTS §6.6). Pure; client-safe.
 */
import type {
  ActivityMode,
  ActivityStatus,
  Direction,
  DupStatus,
  FileKind,
  FundingSource,
  KnownSource,
  KnownStatus,
  LogKind,
  Period,
  PersonRole,
  PsetStatus,
  RejectReason,
  Role,
  SlaLevel,
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
  rejected: 'Ditolak',
};

export const ACTIVITY_STATUS_TONE: Record<ActivityStatus, Tone> = {
  draft: 'neutral',
  in_verification: 'blue',
  revision_requested: 'amber',
  verified: 'green',
  rejected: 'red',
};

/** Tooltip text so status is never conveyed by colour alone (Design §6). */
export const ACTIVITY_STATUS_DESCRIPTION: Record<ActivityStatus, string> = {
  draft: 'Belum diajukan ke International Office.',
  in_verification: 'Sedang diverifikasi oleh International Office.',
  revision_requested: 'International Office meminta perbaikan dari unit.',
  verified: 'Disetujui pada semua jalur verifikasi.',
  rejected: 'Ditolak oleh tim Kemitraan.',
};

export const TRACK_STATUS_LABEL: Record<TrackStatus, string> = {
  not_required: 'Tidak diperlukan',
  pending: 'Menunggu',
  revision_requested: 'Perlu Revisi',
  approved: 'Disetujui',
  rejected: 'Ditolak',
};

export const TRACK_STATUS_TONE: Record<TrackStatus, Tone> = {
  not_required: 'neutral',
  pending: 'blue',
  revision_requested: 'amber',
  approved: 'green',
  rejected: 'red',
};

export const TRACK_LABEL: Record<Team, string> = {
  partnership: 'Kemitraan',
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

export const KNOWN_STATUS_LABEL: Record<KnownStatus, string> = {
  unmatched: 'Belum dilaporkan',
  matched: 'Cocok',
  dismissed: 'Diabaikan',
};

export const KNOWN_STATUS_TONE: Record<KnownStatus, Tone> = {
  unmatched: 'amber',
  matched: 'green',
  dismissed: 'neutral',
};

export const KNOWN_SOURCE_LABEL: Record<KnownSource, string> = {
  surat_tugas: 'Surat Tugas',
  news: 'Berita',
  faculty_report: 'Laporan Fakultas',
  loa_visa_letter: 'LoA/Surat Visa',
  email: 'Email',
  other: 'Lainnya',
};

export const DUP_STATUS_LABEL: Record<DupStatus, string> = {
  open: 'Terbuka',
  linked: 'Ditautkan',
  dismissed: 'Bukan duplikat',
};

export const DUP_STATUS_TONE: Record<DupStatus, Tone> = {
  open: 'purple',
  linked: 'green',
  dismissed: 'neutral',
};

export const REJECT_REASON_LABEL: Record<RejectReason, string> = {
  duplicate: 'Duplikat',
  not_partnership: 'Bukan kegiatan kerja sama',
  wrong_agreement: 'Kerja sama salah',
  other: 'Lainnya',
};

export const DIRECTION_LABEL: Record<Direction, string> = {
  inbound: 'Inbound',
  outbound: 'Outbound',
  none: 'Tidak berlaku',
};

export const MODE_LABEL: Record<ActivityMode, string> = {
  offline: 'Luring',
  online: 'Daring',
  hybrid: 'Hibrida',
};

export const FUNDING_LABEL: Record<FundingSource, string> = {
  pcu: 'Universitas (PCU)',
  partner: 'Mitra',
  government: 'Pemerintah',
  participant: 'Mandiri (peserta)',
  mixed: 'Campuran',
  none: 'Tanpa pendanaan',
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
  evidence: 'Bukti',
};

export const SECTION_LABEL: Record<StudentSection, string> = {
  internal: 'Mahasiswa PETRA',
  inbound: 'Mahasiswa Inbound',
};

export const SNAPSHOT_KIND_LABEL: Record<SnapshotKind, string> = {
  ganjil_ytd: 'Ganjil (YTD)',
  genap_full_year: 'Setahun',
};

export const PERIOD_LABEL: Record<Period, string> = {
  ganjil: 'Ganjil (YTD)',
  full: 'Setahun',
  live: 'Live',
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
  reject: 'Ditolak',
  edit: 'Diubah',
  edit_detail: 'Detail diperbaiki',
  file_upload: 'Berkas diunggah',
  file_remove: 'Berkas dihapus',
  link_duplicate: 'Ditautkan sebagai duplikat',
  unlink_duplicate: 'Tautan duplikat dibatalkan',
  dismiss_duplicate: 'Ditandai bukan duplikat',
};

export function logActionLabel(action: string): string {
  return LOG_ACTION_LABEL[action] ?? action;
}

export const SLA_TONE: Record<SlaLevel, Tone> = {
  ok: 'neutral',
  yellow: 'yellow',
  red: 'red',
};

export const SLA_LEVEL_LABEL: Record<SlaLevel, string> = {
  ok: 'Normal',
  yellow: 'Kuning',
  red: 'Merah',
};

/** 'SLA 4 hari' (business days). */
export function slaText(days: number): string {
  return `SLA ${days} hari`;
}

export const FLAG_LABEL = {
  late: 'Terlambat',
  out_of_scope: 'Di luar lingkup',
  duplicate: 'Duplikat?',
  late_addition: 'Tambahan susulan',
} as const;

export type FlagKey = keyof typeof FLAG_LABEL;

/** Outline colour per flag (Design §2). */
export const FLAG_TONE: Record<FlagKey, Tone> = {
  late: 'amber',
  out_of_scope: 'neutral',
  duplicate: 'purple',
  late_addition: 'blue',
};

export const FLAG_DESCRIPTION: Record<FlagKey, string> = {
  late: 'Diajukan setelah batas pelaporan.',
  out_of_scope: 'Unit pengaju tidak termasuk dalam Lingkup Kerja Sama dokumen.',
  duplicate: 'Ada kandidat duplikat yang belum ditinjau.',
  late_addition: 'Diverifikasi setelah snapshot periode kegiatan dibekukan.',
};
