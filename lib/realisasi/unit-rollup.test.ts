import { describe, expect, it } from 'vitest';
import { buildUnitRollup, rollupGrandTotal, subtreeIds, type UnitNode } from './unit-rollup';

const tree: UnitNode[] = [
  { id: 10, name: 'Fakultas Teknologi Industri', parent_id: null, kind: 'faculty' },
  { id: 11, name: 'Prodi Informatika', parent_id: 10, kind: 'prodi' },
  { id: 12, name: 'Prodi Teknik Elektro', parent_id: 10, kind: 'prodi' },
  { id: 111, name: 'Program Internasional Informatika', parent_id: 11, kind: 'prodi' },
  { id: 20, name: 'Fakultas Bisnis & Ekonomi', parent_id: null, kind: 'faculty' },
  { id: 21, name: 'Prodi Manajemen', parent_id: 20, kind: 'prodi' },
];

describe('buildUnitRollup', () => {
  it('rolls Program into Program Studi and Program Studi into Fakultas, own values included', () => {
    const rows = buildUnitRollup(tree, new Map([[10, 1], [11, 2], [111, 4], [12, 3]]));
    const get = (id: number) => rows.find((r) => r.unit_id === id)!;
    expect(get(111)).toMatchObject({ level: 'Program', depth: 2, own: 4, total: 4 });
    expect(get(11)).toMatchObject({ level: 'Program Studi', own: 2, total: 6 });
    expect(get(12)).toMatchObject({ own: 3, total: 3 });
    expect(get(10)).toMatchObject({ level: 'Fakultas', own: 1, total: 10 });
    expect(get(111).path).toEqual(['Fakultas Teknologi Industri', 'Prodi Informatika', 'Program Internasional Informatika']);
    expect(rollupGrandTotal(rows)).toBe(10);
  });

  it('lists every unit (zeros too) depth-first, sorted by name', () => {
    const rows = buildUnitRollup(tree, new Map());
    expect(rows.map((r) => r.unit_id)).toEqual([20, 21, 10, 11, 111, 12]);
    expect(rows.every((r) => r.total === 0)).toBe(true);
  });

  it('skips a university container and keeps numbers of unknown units in "Lainnya"', () => {
    const withRoot: UnitNode[] = [
      { id: 1, name: 'Universitas', parent_id: null, kind: 'up' },
      ...tree.map((u) => (u.parent_id === null ? { ...u, parent_id: 1 } : u)),
    ];
    const rows = buildUnitRollup(withRoot, new Map([[21, 2], [999, 5], [1, 1]]));
    expect(rows[0]).toMatchObject({ unit_id: 20, depth: 0, total: 2 });
    expect(rows.at(-1)).toMatchObject({ unit_id: null, level: 'Lainnya', total: 6 });
    expect(rollupGrandTotal(rows)).toBe(8);
  });
});

describe('subtreeIds', () => {
  it('returns the unit and all descendants', () => {
    expect(subtreeIds(tree, 10).sort((a, b) => a - b)).toEqual([10, 11, 12, 111]);
    expect(subtreeIds(tree, 21)).toEqual([21]);
  });
});
