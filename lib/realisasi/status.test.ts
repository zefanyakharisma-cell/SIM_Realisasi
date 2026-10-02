import { describe, expect, it } from 'vitest';
import {
  ACTIVITY_STATUS_LABEL,
  ACTIVITY_STATUS_TONE,
  CONFLICT_STATUS_LABEL,
  FLAG_LABEL,
  MOBILITY_CATEGORY_LABEL,
  PERIOD_LABEL,
  PSET_STATUS_LABEL,
  TRACK_LABEL,
  TRACK_STATUS_LABEL,
  TRACK_STATUS_TONE,
  logActionLabel,
} from './status';

describe('status language (Design §2, Revisi V.1)', () => {
  it('labels and tones activity statuses', () => {
    expect(ACTIVITY_STATUS_LABEL).toEqual({
      draft: 'Draf',
      in_verification: 'Dalam Verifikasi',
      revision_requested: 'Perlu Revisi',
      verified: 'Terverifikasi',
    });
    expect(ACTIVITY_STATUS_TONE).toEqual({
      draft: 'neutral',
      in_verification: 'blue',
      revision_requested: 'amber',
      verified: 'green',
    });
  });

  it('labels and tones the Mobility track (the only verification)', () => {
    expect(TRACK_STATUS_LABEL.not_required).toBe('Tidak diperlukan');
    expect(TRACK_STATUS_LABEL.pending).toBe('Menunggu');
    expect(TRACK_STATUS_LABEL.approved).toBe('Disetujui');
    expect(TRACK_STATUS_TONE).toEqual({
      not_required: 'neutral',
      pending: 'blue',
      revision_requested: 'amber',
      approved: 'green',
    });
    expect(TRACK_LABEL).toEqual({ mobility: 'Mobilitas' });
  });

  it('labels other enums per contract', () => {
    expect(PSET_STATUS_LABEL.superseded).toBe('Digantikan');
    expect(PSET_STATUS_LABEL.draft).toBe('Draf');
    expect(CONFLICT_STATUS_LABEL.open).toBe('Menunggu keputusan');
    expect(MOBILITY_CATEGORY_LABEL.jd_dd).toBe('Joint Degree / Double Degree');
    expect(PERIOD_LABEL).toEqual({ ganjil: 'Ganjil', genap: 'Genap', full: 'Setahun (kumulatif)', ytd: 'YTD' });
  });

  it('labels flags', () => {
    expect(FLAG_LABEL.late).toBe('Terlambat');
    expect(FLAG_LABEL.conflict).toBe('Duplikat mahasiswa');
  });

  it('falls back to the raw action for unknown log actions', () => {
    expect(logActionLabel('approve')).toBe('Disetujui');
    expect(logActionLabel('resolve_conflict')).toBe('Keputusan duplikat mahasiswa');
    expect(logActionLabel('something_new')).toBe('something_new');
  });
});
