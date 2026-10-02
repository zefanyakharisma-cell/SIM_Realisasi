'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import {
  ClipboardList,
  FileText,
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
  file: FileText,
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
          <h2 className="mb-2 px-3 text-xs font-semibold uppercase tracking-wider text-slate-400">{section.title}</h2>
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
                      'flex min-h-9 items-center gap-3 rounded-md px-3 py-2 text-sm font-medium text-sidebar-foreground/85 transition-colors hover:bg-sidebar-accent hover:text-sidebar-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/70',
                      active && 'bg-sidebar-accent text-white',
                    )}
                  >
                    <Icon className="size-4 shrink-0" aria-hidden="true" />
                    <span className="flex-1 truncate">{it.label}</span>
                    {it.badge !== undefined && it.badge > 0 ? (
                      <>
                        <span
                          aria-hidden="true"
                          className="rounded-full bg-amber-400 px-1.5 py-0.5 text-[11px] font-semibold leading-none text-slate-900"
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

export function Sidebar({ sections }: { sections: NavSection[] }) {
  return (
    <aside className="hidden w-64 shrink-0 flex-col bg-sidebar text-sidebar-foreground lg:flex">
      <div className="flex h-14 items-center gap-2 border-b border-white/10 px-6">
        <span className="flex size-7 items-center justify-center rounded-md bg-white/10 text-xs font-bold" aria-hidden="true">
          SR
        </span>
        <Link href="/realisasi" className="font-semibold tracking-tight focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/70">
          SIM Realisasi
        </Link>
      </div>
      <div className="flex-1 overflow-y-auto">
        <SidebarNav sections={sections} />
      </div>
      <p className="border-t border-white/10 px-6 py-3 text-xs text-slate-400">Mockup v1.0 · Petra Christian University</p>
    </aside>
  );
}
