// SIM Kerjasama section shares the app shell with SIM Realisasi (same session, sidebar, banner).
import type { ReactNode } from 'react';
import { withUser } from '@/lib/db';
import { getDemoToday, requireUser } from '@/lib/session';
import type { NavCounts } from '@/lib/realisasi/types';
import { AppShell } from '@/components/layout/app-shell';

const ZERO_COUNTS: NavCounts = { partnership_queue: 0, mobility_queue: 0, duplicates_open: 0, revision_inbox: 0, unread_notifications: 0 };

export const dynamic = 'force-dynamic';

export default async function KerjasamaLayout({ children }: { children: ReactNode }) {
  const user = await requireUser();
  const [navCounts, demoToday] = await Promise.all([
    withUser(user.id, async (tx) => {
      const [row] = await tx`select realisasi.nav_counts() as r`;
      return { ...ZERO_COUNTS, ...((row?.r as NavCounts | undefined) ?? {}) };
    }).catch(() => ZERO_COUNTS),
    getDemoToday().catch(() => null),
  ]);
  return (
    <AppShell user={user} navCounts={navCounts} demoToday={demoToday}>
      {children}
    </AppShell>
  );
}
