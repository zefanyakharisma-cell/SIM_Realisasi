/** International Awards (Revisi V.1 item 8): each leaderboard lists only the top 3. Pure, safe anywhere. */

export const AWARDS_TOP_N = 3;

/**
 * Competition ranking (1, 2, 2, 4) on `total` (sorted desc first), units with total 0 dropped, then only ranks ≤ `n`.
 * Ties at the cut-off are all kept, so a board can hold more than `n` rows.
 */
export function topRanked<T extends { total: number }>(rows: readonly T[], n: number = AWARDS_TOP_N): T[] {
  const sorted = rows.filter((r) => r.total > 0).sort((a, b) => b.total - a.total);
  const out: T[] = [];
  let rank = 0;
  sorted.forEach((r, i) => {
    if (i === 0 || sorted[i - 1]!.total !== r.total) rank = i + 1;
    if (rank <= n) out.push(r);
  });
  return out;
}
