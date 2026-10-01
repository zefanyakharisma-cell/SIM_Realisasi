import { describe, expect, it } from 'vitest';
import {
  ACTIVITY_STATUS_LABEL,
  ACTIVITY_STATUS_TONE,
  DUP_STATUS_LABEL,
  FLAG_LABEL,
  KNOWN_SOURCE_LABEL,
  KNOWN_STATUS_LABEL,
  PSET_STATUS_LABEL,
  REJECT_REASON_LABEL,
  SLA_TONE,
  TRACK_LABEL,
  TRACK_STATUS_LABEL,
  TRACK_STATUS_TONE,
  logActionLabel,
  slaText,
} from './status';

describe('status language (Design §2)', () => {
  it('labels and tones activity statuses', () => {
    expect(ACTIVITY_STATUS_LABEL).toEqual({
      draft: 'Draf',
      in_verification: 'Dalam Verifikasi',
      revision_requested: 'Perlu Revisi',
      verified: 'Terverifikasi',
      rejected: 'Ditolak',
    });
    expect(ACTIVITY_STATUS_TONE).toEqual({
      draft: 'neutral',
      in_verification: 'blue',
      revision_requested: 'amber',
      verified: 'green',
      rejected: 'red',
    });
  });

  it('labels and tones track statuses', () => {
    expect(TRACK_STATUS_LABEL.not_required).toBe('Tidak diperlukan');
    expect(TRACK_STATUS_LABEL.pending).toBe('Menunggu');
    expect(TRACK_STATUS_LABEL.approved).toBe('Disetujui');
    expect(TRACK_STATUS_TONE).toEqual({
      not_required: 'neutral',
      pending: 'blue',
      revision_requested: 'amber',
      approved: 'green',
      rejected: 'red',
    });
    expect(TRACK_LABEL).toEqual({ partnership: 'Kemitraan', mobility: 'Mobilitas' });
  });

  it('labels other enums per contract', () => {
    expect(PSET_STATUS_LABEL.superseded).toBe('Digantikan');
    expect(PSET_STATUS_LABEL.draft).toBe('Draf');
    expect(KNOWN_STATUS_LABEL.unmatched).toBe('Belum dilaporkan');
    expect(KNOWN_SOURCE_LABEL.loa_visa_letter).toBe('LoA/Surat Visa');
    expect(DUP_STATUS_LABEL.dismissed).toBe('Bukan duplikat');
    expect(REJECT_REASON_LABEL.not_partnership).toBe('Bukan kegiatan kerja sama');
  });

  it('formats SLA and flags', () => {
    expect(slaText(4)).toBe('SLA 4 hari');
    expect(SLA_TONE).toEqual({ ok: 'neutral', yellow: 'yellow', red: 'red' });
    expect(FLAG_LABEL.late).toBe('Terlambat');
    expect(FLAG_LABEL.duplicate).toBe('Duplikat?');
  });

  it('falls back to the raw action for unknown log actions', () => {
    expect(logActionLabel('approve')).toBe('Disetujui');
    expect(logActionLabel('something_new')).toBe('something_new');
  });
});
