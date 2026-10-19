import { describe, expect, it } from 'vitest';
import { ALL_TOURS, LOGIN_TOUR, SHELL_TOUR, tourFor } from './tours';

describe('demo tours', () => {
  it('have unique ids and non-empty, well-formed steps', () => {
    const ids = ALL_TOURS.map((t) => t.id);
    expect(new Set(ids).size).toBe(ids.length);
    for (const t of ALL_TOURS) {
      expect(t.title.trim()).not.toBe('');
      expect(t.steps.length).toBeGreaterThan(0);
      for (const s of t.steps) {
        expect(s.title.trim(), `${t.id}: title`).not.toBe('');
        expect(s.body.trim(), `${t.id}/${s.title}: body`).not.toBe('');
        for (const sel of [s.target, s.unless]) {
          if (sel === undefined) continue;
          // Plain CSS selectors only (ids, attribute selectors, tag names, descendant combinators).
          expect(sel, `${t.id}/${s.title}`).toMatch(/^[a-z#[][\w\-#[\]="^. :]*$/i);
          expect(sel.split('[').length, `${t.id}/${s.title}: brackets`).toBe(sel.split(']').length);
        }
      }
    }
  });

  it('start the login and app-frame tours with a centered welcome step', () => {
    expect(LOGIN_TOUR.steps[0]?.target).toBeUndefined();
    expect(SHELL_TOUR.steps[0]?.target).toBeUndefined();
  });
});

describe('tourFor', () => {
  it.each([
    ['/realisasi', null, 'dashboard'],
    ['/realisasi/', null, 'dashboard'],
    ['/realisasi', 'awards', 'dashboard-awards'],
    ['/realisasi/kegiatan', null, 'kegiatan'],
    ['/realisasi/kegiatan/baru', null, 'kegiatan-baru'],
    ['/realisasi/kegiatan/1f0c/revisi', null, 'kegiatan-revisi'],
    ['/realisasi/kegiatan/1f0c', null, 'kegiatan-detail'],
    ['/realisasi/verifikasi/mobilitas', null, 'verifikasi'],
    ['/realisasi/laporan', null, 'laporan'],
    ['/realisasi/pengaturan', null, 'pengaturan-umum'],
    ['/realisasi/pengaturan', 'umum', 'pengaturan-umum'],
    ['/realisasi/pengaturan', 'kalender', 'pengaturan-kalender'],
    ['/realisasi/pengaturan', 'jenis', 'pengaturan-jenis'],
    ['/realisasi/notifikasi', null, 'notifikasi'],
    ['/kerjasama/dokumen', null, 'dokumen'],
    ['/kerjasama/dokumen/12', null, 'dokumen-detail'],
    ['/kerjasama/dokumen/12/evaluasi', null, 'dokumen-detail'],
  ])('%s (tab=%s) → %s', (path, tab, id) => {
    expect(tourFor(path, tab)?.id).toBe(id);
  });

  it('returns null for routes without a tour', () => {
    expect(tourFor('/login')).toBeNull();
    expect(tourFor('/realisasi/kegiatan/1f0c/edit')).toBeNull();
  });
});
