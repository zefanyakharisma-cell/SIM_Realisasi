// Pengaturan (Design §3.9) — io_admin only (`settings.manage`); the RPCs re-check the role.
import Link from 'next/link';
import { withUser } from '@/lib/db';
import { can, getDemoTimeTravelEnabled, getToday, requireUser } from '@/lib/session';
import { getParam, parseRenstraKey } from '@/lib/realisasi/schemas/report';
import {
  getRenstraTargets,
  getSettingsMap,
  getSnapshotList,
  listAcademicYears,
  listAgendaRules,
  listSemesters,
  listUnitTree,
} from '@/lib/realisasi/queries/reports';
import { buildUnitRollup } from '@/lib/realisasi/unit-rollup';
import { GENERAL_SETTING_FIELDS, type GeneralSettingsInput } from '@/lib/realisasi/schemas/settings';
import type { SnapshotListRow } from '@/lib/realisasi/types';
import { PageHeader } from '@/components/realisasi/page-header';
import { Forbidden } from '@/components/realisasi/forbidden';
import { DemoTodayCard, GeneralSettingsForm, LIVE_NOTICE } from '@/components/realisasi/settings/general-settings';
import { CalendarManager } from '@/components/realisasi/settings/calendar-manager';
import { AgendaRulesManager } from '@/components/realisasi/settings/agenda-rules';
import { RenstraTargetsManager } from '@/components/realisasi/settings/renstra-targets';
import { cn } from '@/lib/utils';

export const dynamic = 'force-dynamic';

const TABS = [
  { key: 'umum', label: 'Umum' },
  { key: 'kalender', label: 'Kalender Akademik' },
  { key: 'jenis', label: 'Jenis Kegiatan' },
  { key: 'target', label: 'Target RENSTRA' },
] as const;
type TabKey = (typeof TABS)[number]['key'];

export default async function PengaturanPage(props: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const user = await requireUser();
  if (!can(user, 'settings.manage')) return <Forbidden />;
  const sp = await props.searchParams;
  const tabRaw = getParam(sp, 'tab');
  const tab: TabKey = TABS.some((t) => t.key === tabRaw) ? (tabRaw as TabKey) : 'umum';
  const [today, timeTravel] = await Promise.all([getToday(), getDemoTimeTravelEnabled()]);

  const content = await withUser(user.id, async (tx) => {
    switch (tab) {
      case 'umum': {
        const s = await getSettingsMap(tx);
        const initial = Object.fromEntries(GENERAL_SETTING_FIELDS.map((f) => [f.key, Number(s[f.key] ?? 0)])) as GeneralSettingsInput;
        const demo = typeof s.demo_today === 'string' ? s.demo_today : null;
        return (
          <div className="space-y-6">
            {/* WP-DB amendment 29: the demo-date control exists only where time travel is enabled. */}
            {timeTravel ? <DemoTodayCard demoToday={demo} today={today} /> : null}
            <GeneralSettingsForm initial={initial} />
          </div>
        );
      }
      case 'kalender': {
        const [years, semesters] = await Promise.all([listAcademicYears(tx), listSemesters(tx)]);
        const snapshots: SnapshotListRow[] = (await Promise.all(years.map((y) => getSnapshotList(tx, y.id)))).flat();
        return <CalendarManager years={years} semesters={semesters} snapshots={snapshots} today={today} />;
      }
      case 'jenis': {
        const rules = await listAgendaRules(tx);
        return <AgendaRulesManager rules={rules} />;
      }
      case 'target': {
        const [years, tree] = await Promise.all([listAcademicYears(tx), listUnitTree(tx)]);
        if (years.length === 0) return <p className="text-sm text-muted-foreground">Belum ada tahun akademik.</p>;
        const ayParam = Number(getParam(sp, 'ay'));
        // default: the academic year containing today, else the latest one
        const ay =
          years.find((y) => y.id === ayParam)?.id ??
          years.find((y) => y.start_date <= today && today <= y.end_date)?.id ??
          years[years.length - 1]!.id;
        const renstra = parseRenstraKey(getParam(sp, 'renstra')) ?? '1.1';
        const targets = await getRenstraTargets(tx, ay, renstra);
        const units = [
          { unit_id: 0, name: 'Universitas', level: 'Universitas', depth: 0 },
          ...buildUnitRollup(tree, new Map())
            .filter((r) => r.unit_id !== null)
            .map((r) => ({ unit_id: r.unit_id!, name: r.name, level: r.level, depth: r.depth })),
        ];
        return (
          <RenstraTargetsManager
            key={`${ay}-${renstra}`}
            years={years}
            ay={ay}
            renstra={renstra}
            units={units}
            initial={Object.fromEntries(targets)}
          />
        );
      }
    }
  });

  return (
    <div>
      <PageHeader title="Pengaturan" description={LIVE_NOTICE} />
      <nav aria-label="Tab pengaturan" className="mb-4 flex flex-wrap gap-1 border-b">
        {TABS.map((t) => (
          <Link
            key={t.key}
            href={`/realisasi/pengaturan?tab=${t.key}`}
            aria-current={t.key === tab ? 'page' : undefined}
            data-testid={`settings-tab-${t.key}`}
            className={cn(
              '-mb-px border-b-2 px-4 py-2 text-sm font-medium',
              t.key === tab ? 'border-primary font-semibold text-primary' : 'border-transparent text-text-secondary hover:text-foreground',
            )}
          >
            {t.label}
          </Link>
        ))}
      </nav>
      {content}
    </div>
  );
}
