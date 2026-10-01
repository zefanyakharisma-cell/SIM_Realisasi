import { describe, expect, it } from 'vitest';
import { formatDiffLines } from './diff-format';

describe('formatDiffLines (requirements review L-2, WP-DB amendment 26)', () => {
  it('uses human field labels', () => {
    expect(formatDiffLines({ venue: ['Auditorium PCU', 'Gedung P'], sks_recognized: [null, 2] })).toEqual([
      'Tempat / platform: Auditorium PCU → Gedung P',
      'SKS diakui: – → 2',
    ]);
  });
  it('renders id lists and masked counts', () => {
    expect(formatDiffLines({ students: { added: ['B1'], removed: ['B2'] } })).toEqual(['Mahasiswa: +B1 ; −B2']);
    expect(formatDiffLines({ students: { added: 2, removed: 0 }, row_notes: 3 })).toEqual(['Mahasiswa: +2 baris', 'Catatan per baris: 3 catatan']);
    expect(formatDiffLines(null)).toEqual([]);
  });
});
