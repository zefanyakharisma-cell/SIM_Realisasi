import { describe, expect, it } from 'vitest';
import { topRanked } from './awards';

const row = (unit_id: number, total: number) => ({ unit_id, total });

describe('topRanked (International Awards top 3)', () => {
  it('keeps ranks 1–3 only, ordered by total', () => {
    expect(topRanked([row(1, 5), row(2, 9), row(3, 1), row(4, 7), row(5, 3)]).map((r) => r.unit_id)).toEqual([2, 4, 1]);
  });

  it('keeps every unit tied at the cut-off rank', () => {
    expect(topRanked([row(1, 9), row(2, 7), row(3, 5), row(4, 5), row(5, 2)]).map((r) => r.unit_id)).toEqual([1, 2, 3, 4]);
    // 1, 2, 2 → the next unit is rank 4 and is dropped
    expect(topRanked([row(1, 9), row(2, 7), row(3, 7), row(4, 6)]).map((r) => r.unit_id)).toEqual([1, 2, 3]);
  });

  it('drops units with a total of 0', () => {
    expect(topRanked([row(1, 0), row(2, 4), row(3, 0)]).map((r) => r.unit_id)).toEqual([2]);
    expect(topRanked([])).toEqual([]);
  });
});
