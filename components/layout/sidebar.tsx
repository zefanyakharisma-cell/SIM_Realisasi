'use client';

import Image from 'next/image';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import {
  ClipboardList,
  LayoutDashboard,
  PlusCircle,
  BarChart3,
  Settings,
  Users,
  type LucideIcon,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import type { NavIcon, NavSection } from '@/components/layout/nav';

const ICONS: Record<NavIcon, LucideIcon> = {
  dashboard: LayoutDashboard,
  list: ClipboardList,
  plus: PlusCircle,
  users: Users,
  report: BarChart3,
  settings: Settings,
};

function isActive(pathname: string, href: string, exact?: boolean): boolean {
  if (exact) {
    // "Kegiatan" stays active on activity detail pages, but not on /kegiatan/baru.
    if (href === '/realisasi/kegiatan') return pathname === href || (pathname.startsWith(`${href}/`) && !pathname.startsWith(`${href}/baru`));
    return pathname === href;
  }
  return pathname === href || pathname.startsWith(`${href}/`);
}

export function SidebarNav({ sections, onNavigate }: { sections: NavSection[]; onNavigate?: () => void }) {
  const pathname = usePathname() ?? '';
  return (
    <nav aria-label="Navigasi utama" className="flex flex-col gap-6 px-3 py-4">
      {sections.map((section) => (
        <div key={section.title}>
          <h2 className="mb-2 px-3 text-[11px] font-semibold uppercase tracking-[0.12em] text-white/70">{section.title}</h2>
          <ul className="space-y-0.5">
            {section.items.map((it) => {
              const Icon = ICONS[it.icon];
              const active = isActive(pathname, it.href, it.exact);
              return (
                <li key={it.href}>
                  <Link
                    href={it.href}
                    data-testid={it.testId}
                    aria-current={active ? 'page' : undefined}
                    onClick={onNavigate}
                    className={cn(
                      'flex min-h-9 items-center gap-3 rounded-lg px-3 py-2 text-sm text-sidebar-foreground/90 transition-colors hover:bg-white/10 hover:text-sidebar-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white focus-visible:ring-offset-0',
                      active && 'bg-white/[.14] font-medium text-white',
                    )}
                  >
                    <Icon className="size-5 shrink-0" strokeWidth={1.75} aria-hidden="true" />
                    <span className="flex-1 truncate">{it.label}</span>
                    {it.badge !== undefined && it.badge > 0 ? (
                      <>
                        <span
                          aria-hidden="true"
                          className="rounded-full bg-warning px-1.5 py-0.5 text-[11px] font-semibold leading-none text-midnight"
                          data-testid={`${it.testId}-badge`}
                        >
                          {it.badge}
                        </span>
                        <span className="sr-only">, {it.badgeLabel ?? it.badge}</span>
                      </>
                    ) : null}
                  </Link>
                </li>
              );
            })}
          </ul>
        </div>
      ))}
    </nav>
  );
}

/** The seal, cropped from the approved logomaster file (never redrawn), on a 90% white chip. */
export function BrandMark() {
  return (
    <span className="block size-[34px] shrink-0 overflow-hidden rounded bg-white/90" aria-hidden="true">
      <Image src="/brand/logo-petra.png" alt="" width={97} height={34} className="h-[34px] w-auto max-w-none" priority />
    </span>
  );
}

/** PCU SidebarNav: midnight rail, seal + app name, one 20px stroke icon per route; white focus rings. */
export function Sidebar({ sections }: { sections: NavSection[] }) {
  return (
    <aside className="hidden w-64 shrink-0 flex-col bg-sidebar text-sidebar-foreground lg:flex">
      <Link
        href="/realisasi"
        className="flex h-16 items-center gap-2.5 px-5 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-white"
      >
        <BrandMark />
        <span className="min-w-0">
          <span className="block text-sm font-semibold uppercase leading-tight tracking-wide">SIM Realisasi</span>
          <span className="block text-[11px] text-white/80">Universitas Kristen Petra</span>
        </span>
      </Link>
      <div className="flex-1 overflow-y-auto">
        <SidebarNav sections={sections} />
      </div>
      <p className="border-t border-white/10 px-5 py-3 text-xs text-white/70">Mockup v1.0 · Petra Christian University</p>
    </aside>
  );
}
