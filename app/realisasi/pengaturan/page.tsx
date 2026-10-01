// Pengaturan (Design §3.9) — io_admin only (`settings.manage`); the RPCs re-check the role.
import Link from 'next/link';
import { withUser } from '@/lib/db';
import { can, getDemoTimeTravelEnabled, getToday, requireUser } from '@/lib/session';
import { getParam } from '@/lib/realisasi/schemas/report';
import {
  getSettingsMap,
  getSnapshotList,
  listAcademicYears,
  listActivityTypes,
  listHolidays,
  listSemesters,
} from '@/lib/realisasi/queries/reports';
import { GENERAL_SETTING_FIELDS, type GeneralSettingsInput } from '@/lib/realisasi/schemas/settings';
import type { SnapshotListRow } from '@/lib/realisasi/types';
import { PageHeader } from '@/components/realisasi/page-header';
import { Forbidden } from '@/components/realisasi/forbidden';
import { DemoTodayCard, GeneralSettingsForm, LIVE_NOTICE } from '@/components/realisasi/settings/general-settings';
import { CalendarManager } from '@/components/realisasi/settings/calendar-manager';
import { ActivityTypesManager, HolidaysManager } from '@/components/realisasi/settings/types-holidays';
import { cn } from '@/lib/utils';

export const dynamic = 'force-dynamic';

const TABS = [
  { key: 'umum', label: 'Umum' },
  { key: 'kalender', label: 'Kalender Akademik' },
  { key: 'jenis', label: 'Jenis Kegiatan' },
  { key: 'libur', label: 'Hari Libur' },
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
        const types = await listActivityTypes(tx);
        return <ActivityTypesManager types={types} />;
      }
      case 'libur': {
        const holidays = await listHolidays(tx);
        return <HolidaysManager holidays={holidays} />;
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
              t.key === tab ? 'border-primary text-primary' : 'border-transparent text-muted-foreground hover:text-foreground',
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
