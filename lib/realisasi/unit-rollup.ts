// Laporan per RENSTRA (Revisi V.2): per-unit numbers rolled up the unit hierarchy.
// Fakultas = its own Kegiatan + the sum of its Program Studi; Program Studi = its own + the sum of its Programs.
// Pure module (no DB), so the page preview and the Excel export share one implementation.

export interface UnitNode {
  id: number;
  name: string;
  parent_id: number | null;
  /** kerjasama.units.kind: 'up' | 'faculty' | 'prodi' | 'program'. */
  kind: string;
}

export type UnitLevel = 'Fakultas' | 'Program Studi' | 'Program' | 'Lainnya';

export interface RollupRow {
  unit_id: number | null;
  name: string;
  level: UnitLevel;
  /** 0 = Fakultas, 1 = Program Studi, 2+ = Program. */
  depth: number;
  /** Ancestor names from Fakultas down to (and including) this unit. */
  path: string[];
  /** Kegiatan attributed to this unit itself. */
  own: number;
  /** own + the totals of every child unit. */
  total: number;
}

const LEVELS: UnitLevel[] = ['Fakultas', 'Program Studi', 'Program'];
const byName = (a: UnitNode, b: UnitNode) => a.name.localeCompare(b.name, 'id') || a.id - b.id;

/**
 * Depth-first rows: each Fakultas, then its Program Studi, then their Programs (each level sorted by name).
 * Every unit of `tree` is listed, zero or not. A university-level root (kind 'up' with children) is only a
 * container and is skipped. Values for unit ids missing from `tree` are kept in one "Lainnya" row so the
 * table never loses a number.
 */
export function buildUnitRollup(tree: UnitNode[], direct: ReadonlyMap<number, number>): RollupRow[] {
  const byId = new Map(tree.map((u) => [u.id, u]));
  const children = new Map<number | null, UnitNode[]>();
  for (const u of tree) {
    const parent = u.parent_id !== null && byId.has(u.parent_id) ? u.parent_id : null;
    const list = children.get(parent) ?? [];
    list.push(u);
    children.set(parent, list);
  }
  for (const list of children.values()) list.sort(byName);

  // Top level: skip containers (a university root above the faculties).
  const roots: UnitNode[] = [];
  const pushRoots = (u: UnitNode) => {
    const kids = children.get(u.id) ?? [];
    if (u.kind === 'up' && kids.length > 0) kids.forEach(pushRoots);
    else roots.push(u);
  };
  (children.get(null) ?? []).forEach(pushRoots);
  roots.sort(byName);

  const rows: RollupRow[] = [];
  const visit = (u: UnitNode, depth: number, path: string[]): number => {
    const own = direct.get(u.id) ?? 0;
    const row: RollupRow = {
      unit_id: u.id,
      name: u.name,
      level: LEVELS[Math.min(depth, LEVELS.length - 1)]!,
      depth,
      path: [...path, u.name],
      own,
      total: own,
    };
    rows.push(row);
    for (const c of children.get(u.id) ?? []) row.total += visit(c, depth + 1, row.path);
    return row.total;
  };
  const seen = new Set<number>();
  for (const r of roots) visit(r, 0, []);
  for (const r of rows) if (r.unit_id !== null) seen.add(r.unit_id);

  // Container units (skipped above) and unknown ids: keep their own numbers visible.
  let other = 0;
  for (const [id, n] of direct) if (!seen.has(id)) other += n;
  if (other > 0) rows.push({ unit_id: null, name: 'Lainnya (unit di luar struktur fakultas)', level: 'Lainnya', depth: 0, path: ['Lainnya'], own: other, total: other });
  return rows;
}

/** Sum of the top-level rows (= every own value counted once). */
export function rollupGrandTotal(rows: RollupRow[]): number {
  return rows.filter((r) => r.depth === 0).reduce((s, r) => s + r.total, 0);
}

/** Subtree of `rootId` (the unit and every descendant), for submitter-scoped reports. */
export function subtreeIds(tree: UnitNode[], rootId: number): number[] {
  const out: number[] = [];
  const stack = [rootId];
  while (stack.length) {
    const id = stack.pop()!;
    if (out.includes(id)) continue;
    out.push(id);
    for (const u of tree) if (u.parent_id === id) stack.push(u.id);
  }
  return out;
}
