// Laporan per RENSTRA (Revisi V.2): one read model for the Laporan page and its Excel export (preview = workbook).
// Numbers come from the SQL read RPCs (dashboard by_unit, kpi_drilldown); this module only arranges the
// per-unit values along the unit hierarchy (see unit-rollup.ts).
import type { Tx } from '@/lib/db';
import type { SessionUser } from '@/lib/session';
import type { ActivityKpiRow, ChainKpiRow, DrilldownResult, KpiScope, KpiTriple, PeriodInfo, UnitKpiValues } from '@/lib/realisasi/types';
import { RENSTRA_DEF, type PeriodParams, type RenstraDef, type RenstraKey, type RenstraMetric } from '@/lib/realisasi/schemas/report';
import { buildUnitRollup, rollupGrandTotal, subtreeIds, type RollupRow, type UnitNode } from '@/lib/realisasi/unit-rollup';
import { getDashboard, getDrilldown, listUnitTree } from '@/lib/realisasi/queries/reports';

type KpiBlocks = Pick<UnitKpiValues, 'kpi_1_1' | 'kpi_1_19_s1' | 'kpi_1_19_24'>;

export interface RenstraReport {
  def: RenstraDef;
  period: PeriodInfo;
  scope: KpiScope;
  /** Per-unit table (null for 1.19.S4, which is reported as one overall number). */
  rollup: RollupRow[] | null;
  /** Official value of the scope (university or the selected unit), deduplicated by the KPI engine. */
  scopeValue: number;
  /** 1.19.S4 only: overall terlaksana / penyebut / masa tenggang. */
  overall: KpiTriple | null;
  activityRows: ActivityKpiRow[];
  chainRows: ChainKpiRow[];
  /** Unit name → Fakultas name, for the data sheet. */
  facultyOf: Map<string, string>;
}

export function metricValue(metric: Exclude<RenstraMetric, null>, v: KpiBlocks): number {
  switch (metric) {
    case 'k11_total':
      return v.kpi_1_1.total;
    case 'k11_inbound':
      return v.kpi_1_1.inbound;
    case 'k11_outbound':
      return v.kpi_1_1.outbound;
    case 's1_international':
      return v.kpi_1_19_s1.international;
  }
}

export async function getRenstraReport(tx: Tx, user: SessionUser, p: PeriodParams, key: RenstraKey): Promise<RenstraReport> {
  const def = RENSTRA_DEF[key];
  const isSubmitter = user.role === 'submitter';
  // A unit picked by a non-submitter means that unit and its whole subtree: read university-wide, filter here.
  // 1.19.S4 has no per-unit table; it keeps the SQL's own unit scope (document scope units).
  const subtreeScope = !isSubmitter && p.unit !== undefined && def.metric !== null;
  const ddParams = subtreeScope ? { ...p, unit: undefined } : p;
  const [dash, dd, tree] = await Promise.all([
    getDashboard(tx, p),
    getDrilldown(tx, { ...ddParams, kpi: def.kpi, bucket: def.bucket }),
    listUnitTree(tx),
  ]);
  const scopeIds = subtreeScope ? subtreeIds(tree, p.unit!) : null;
  const scopeNames = scopeIds ? new Set(tree.filter((u) => scopeIds.includes(u.id)).map((u) => u.name)) : null;

  const facultyOf = new Map<string, string>();
  for (const r of buildUnitRollup(tree, new Map())) facultyOf.set(r.name, r.path[0]!);

  let rollup: RollupRow[] | null = null;
  let scopeValue = 0;
  if (def.metric) {
    const metric = def.metric;
    scopeValue = metricValue(metric, dash.values);
    const direct = new Map<number, number>();
    let scoped: UnitNode[] = tree;
    if (isSubmitter || p.unit !== undefined) {
      // Submitters only ever see their own unit (the SQL forces the scope); others may pick one unit + its subtree.
      const root = isSubmitter ? dash.scope.unit_id : (p.unit ?? null);
      const ids = root === null ? [] : (scopeIds ?? [root]);
      scoped = tree.filter((u) => ids.includes(u.id)).map((u) => (u.id === root ? { ...u, parent_id: null } : u));
      if (isSubmitter && root !== null) {
        direct.set(root, scopeValue);
        if (!scoped.length) scoped = [{ id: root, name: dash.scope.unit_name ?? String(root), parent_id: null, kind: 'prodi' }];
      } else {
        const uni = await getDashboard(tx, { ...p, unit: undefined });
        for (const u of uni.values.by_unit ?? []) if (ids.includes(u.unit_id)) direct.set(u.unit_id, metricValue(metric, u));
      }
    } else {
      for (const u of dash.values.by_unit ?? []) direct.set(u.unit_id, metricValue(metric, u));
    }
    rollup = buildUnitRollup(scoped, direct);
    if (subtreeScope) scopeValue = rollupGrandTotal(rollup);
  }

  const inScope = (names: string[]) => !scopeNames || names.some((n) => scopeNames.has(n));
  const rows = ((dd.rows ?? []) as DrilldownResult['rows']).filter((r) =>
    r.row_type === 'activity' ? inScope(r.unit_names) : true,
  );
  return {
    def,
    period: dash.period,
    scope: dash.scope,
    rollup,
    scopeValue,
    overall: def.metric ? null : dash.values.kpi_1_19_24.all,
    activityRows: rows.filter((r): r is ActivityKpiRow => r.row_type === 'activity'),
    chainRows: rows.filter((r): r is ChainKpiRow => r.row_type === 'chain'),
    facultyOf,
  };
}
