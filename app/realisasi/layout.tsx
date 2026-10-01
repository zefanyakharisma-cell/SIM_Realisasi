import { AppShell } from '@/components/layout/app-shell';
import { withUser } from '@/lib/db';
import { getDemoToday, requireUser } from '@/lib/session';
import type { NavCounts } from '@/lib/realisasi/types';

const ZERO_COUNTS: NavCounts = { partnership_queue: 0, mobility_queue: 0, duplicates_open: 0, revision_inbox: 0, unread_notifications: 0 };

export const dynamic = 'force-dynamic';

export default async function RealisasiLayout({ children }: { children: React.ReactNode }) {
  const user = await requireUser();
  const [navCounts, demoToday] = await Promise.all([
    withUser(user.id, async (tx) => {
      const [row] = await tx<{ c: NavCounts }[]>`select realisasi.nav_counts() as c`;
      return { ...ZERO_COUNTS, ...(row?.c ?? {}) };
    }).catch((e: unknown) => {
      console.error('[layout] nav_counts failed', e);
      return ZERO_COUNTS;
    }),
    getDemoToday().catch(() => null),
  ]);
  return (
    <AppShell user={user} navCounts={navCounts} demoToday={demoToday}>
      {children}
    </AppShell>
  );
}
