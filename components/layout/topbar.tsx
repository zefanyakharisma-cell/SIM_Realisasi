'use client';

import * as React from 'react';
import { LogOut, Menu, RefreshCw, UserCircle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { Sheet, SheetContent, SheetDescription, SheetTitle, SheetTrigger } from '@/components/ui/sheet';
import { NotificationBell } from '@/components/realisasi/notification-bell';
import { SidebarNav } from '@/components/layout/sidebar';
import type { NavSection } from '@/components/layout/nav';
import { logout } from '@/lib/realisasi/actions/session';

export interface TopbarUser {
  displayName: string;
  email: string;
  roleLabel: string;
  unitName: string | null;
  teamsLabel: string | null;
}

export function Topbar({ user, sections, unread }: { user: TopbarUser; sections: NavSection[]; unread: number }) {
  const [menuOpen, setMenuOpen] = React.useState(false);
  const formRef = React.useRef<HTMLFormElement>(null);

  return (
    <header className="sticky top-0 z-40 flex h-14 items-center gap-3 border-b bg-background px-4 lg:px-6">
      <Sheet open={menuOpen} onOpenChange={setMenuOpen}>
        <SheetTrigger asChild>
          <Button variant="ghost" size="icon" className="lg:hidden" aria-label="Buka menu navigasi">
            <Menu aria-hidden="true" />
          </Button>
        </SheetTrigger>
        <SheetContent side="left" className="bg-sidebar p-0 text-sidebar-foreground">
          <SheetTitle className="px-6 pt-5 text-white">SIM Realisasi</SheetTitle>
          <SheetDescription className="sr-only">Menu navigasi</SheetDescription>
          <SidebarNav sections={sections} onNavigate={() => setMenuOpen(false)} />
        </SheetContent>
      </Sheet>
      <span className="font-semibold lg:hidden">SIM Realisasi</span>

      <div className="ml-auto flex items-center gap-1">
        <NotificationBell unread={unread} />
        <form ref={formRef} action={logout} className="hidden" aria-hidden="true" />
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" className="h-10 gap-2 px-2" data-testid="user-menu" aria-label={`Akun: ${user.displayName}, ${user.roleLabel}`}>
              <UserCircle className="!size-6" aria-hidden="true" />
              <span className="hidden flex-col items-start text-left leading-tight sm:flex">
                <span className="text-sm font-medium">{user.displayName}</span>
                <span className="text-xs text-muted-foreground">{user.roleLabel}</span>
              </span>
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-64">
            <DropdownMenuLabel className="font-normal">
              <span className="block text-sm font-semibold">{user.displayName}</span>
              <span className="block text-xs text-muted-foreground">{user.email}</span>
              <span className="mt-1 block text-xs text-muted-foreground">
                {user.roleLabel}
                {user.unitName ? ` · ${user.unitName}` : ''}
                {user.teamsLabel ? ` · Tim ${user.teamsLabel}` : ''}
              </span>
            </DropdownMenuLabel>
            <DropdownMenuSeparator />
            <DropdownMenuItem data-testid="switch-account" onSelect={() => formRef.current?.requestSubmit()}>
              <RefreshCw aria-hidden="true" />
              Ganti akun
            </DropdownMenuItem>
            <DropdownMenuItem data-testid="logout" onSelect={() => formRef.current?.requestSubmit()}>
              <LogOut aria-hidden="true" />
              Keluar
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </header>
  );
}
