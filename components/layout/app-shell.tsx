import * as React from 'react';
import type { SessionUser } from '@/lib/session';
import { can } from '@/lib/session';
import type { NavCounts } from '@/lib/realisasi/types';
import { ROLE_LABEL, TRACK_LABEL } from '@/lib/realisasi/status';
import { buildNav } from '@/components/layout/nav';
import { Sidebar } from '@/components/layout/sidebar';
import { Topbar } from '@/components/layout/topbar';
import { DemoTodayBanner } from '@/components/realisasi/demo-today-banner';

/** Authenticated application frame (server component): skip link, sidebar, top bar, banner, <main>. */
export function AppShell({
  user,
  navCounts,
  demoToday,
  children,
}: {
  user: SessionUser;
  navCounts: NavCounts;
  demoToday: string | null;
  children: React.ReactNode;
}) {
  const sections = buildNav(user, navCounts);
  const topbarUser = {
    displayName: user.displayName,
    email: user.email,
    roleLabel: ROLE_LABEL[user.role],
    unitName: user.unitName,
    teamsLabel: user.teams.length > 0 ? user.teams.map((t) => TRACK_LABEL[t]).join(' & ') : null,
  };
  return (
    <div className="flex min-h-screen">
      <a
        href="#main-content"
        className="sr-only focus:not-sr-only focus:fixed focus:left-4 focus:top-4 focus:z-[100] focus:rounded-md focus:bg-background focus:px-4 focus:py-2 focus:shadow-lg"
      >
        Lewati ke konten utama
      </a>
      <Sidebar sections={sections} />
      <div className="flex min-w-0 flex-1 flex-col">
        <Topbar user={topbarUser} sections={sections} unread={navCounts.unread_notifications} />
        <DemoTodayBanner demoToday={demoToday} canManage={can(user, 'settings.manage')} />
        <main id="main-content" tabIndex={-1} className="flex-1 px-4 py-6 focus:outline-none lg:px-8">
          {children}
        </main>
      </div>
    </div>
  );
}
