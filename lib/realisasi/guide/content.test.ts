import { describe, expect, it } from 'vitest';
import { GUIDE_STEPS, guideStepIndex, pageGuideFor } from './content';

describe('demo guide content', () => {
  it('has unique step ids and non-empty content', () => {
    const ids = GUIDE_STEPS.map((s) => s.id);
    expect(new Set(ids).size).toBe(ids.length);
    for (const s of GUIDE_STEPS) {
      expect(s.title.trim()).not.toBe('');
      expect(s.intro.trim()).not.toBe('');
      expect(s.points.length).toBeGreaterThan(0);
    }
  });

  it('covers every role somewhere in the guide', () => {
    const roles = new Set(GUIDE_STEPS.flatMap((s) => s.roles ?? []));
    expect([...roles].sort()).toEqual(['io_admin', 'io_staff', 'submitter', 'viewer']);
  });

  it('guideStepIndex returns -1 for unknown ids', () => {
    expect(guideStepIndex('selamat-datang')).toBe(0);
    expect(guideStepIndex('nope')).toBe(-1);
  });
});

describe('pageGuideFor', () => {
  it.each([
    ['/realisasi', 'Dashboard'],
    ['/realisasi/', 'Dashboard'],
    ['/realisasi/kegiatan', 'Daftar kegiatan'],
    ['/realisasi/kegiatan/baru', 'Kegiatan Baru'],
    ['/realisasi/kegiatan/1f0c/revisi', 'Ruang revisi'],
    ['/realisasi/kegiatan/1f0c/edit', 'Ubah kegiatan'],
    ['/realisasi/kegiatan/1f0c/peserta-edit', 'Ubah kegiatan'],
    ['/realisasi/kegiatan/1f0c', 'Detail kegiatan'],
    ['/realisasi/verifikasi/mobilitas', 'Verifikasi Mobilitas'],
    ['/realisasi/laporan', 'Laporan & Ekspor'],
    ['/realisasi/pengaturan', 'Pengaturan'],
    ['/realisasi/notifikasi', 'Notifikasi'],
    ['/kerjasama/dokumen', 'Dokumen kerja sama'],
    ['/kerjasama/dokumen/12', 'Detail dokumen kerja sama'],
    ['/kerjasama/dokumen/12/evaluasi', 'Detail dokumen kerja sama'],
  ])('%s → %s', (path, title) => {
    expect(pageGuideFor(path)?.title).toBe(title);
  });

  it('returns null for routes without tips', () => {
    expect(pageGuideFor('/login')).toBeNull();
    expect(pageGuideFor('/realisasi/kegiatan/1f0c/unknown')).toBeNull();
  });

  it('links every page guide to an existing step', () => {
    for (const path of ['/realisasi', '/realisasi/kegiatan/baru', '/realisasi/verifikasi/mobilitas', '/kerjasama/dokumen']) {
      const g = pageGuideFor(path)!;
      expect(guideStepIndex(g.stepId)).toBeGreaterThanOrEqual(0);
    }
  });
});
