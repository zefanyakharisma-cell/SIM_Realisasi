'use client';

/**
 * Top-bar bell: unread count from `nav_counts().unread_notifications`; the latest notifications are
 * loaded when the menu opens (listNotifications) and marked read via `mark_notifications_read`.
 */
import * as React from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { Bell, CheckCheck, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { toast } from '@/components/ui/toaster';
import { cn } from '@/lib/utils';
import { formatDateTime } from '@/lib/realisasi/format';
import { listNotifications, markNotificationsRead } from '@/lib/realisasi/actions/notifications';
import type { NotificationRow } from '@/lib/realisasi/types';

export function NotificationBell({ unread }: { unread: number }) {
  const router = useRouter();
  const [open, setOpen] = React.useState(false);
  const [items, setItems] = React.useState<NotificationRow[] | null>(null);
  const [count, setCount] = React.useState(unread);
  const [loading, setLoading] = React.useState(false);
  const [pending, startTransition] = React.useTransition();

  React.useEffect(() => setCount(unread), [unread]);

  const load = React.useCallback(async () => {
    setLoading(true);
    const res = await listNotifications({ limit: 8 });
    setLoading(false);
    if (res.ok) setItems(res.data);
    else toast.error(res.message);
  }, []);

  const onOpenChange = (next: boolean) => {
    setOpen(next);
    if (next) void load();
  };

  const markAll = () =>
    startTransition(async () => {
      const res = await markNotificationsRead(null);
      if (!res.ok) {
        toast.error(res.message);
        return;
      }
      setCount(0);
      setItems((prev) => prev?.map((n) => (n.read_at ? n : { ...n, read_at: new Date().toISOString() })) ?? prev);
      router.refresh();
    });

  const openItem = (n: NotificationRow) => {
    setOpen(false);
    if (!n.read_at) {
      setCount((c) => Math.max(0, c - 1));
      void markNotificationsRead([n.id]).then((res) => {
        if (!res.ok) toast.error(res.message);
      });
    }
  };

  const label = count > 0 ? `Notifikasi, ${count} belum dibaca` : 'Notifikasi';

  return (
    <Popover open={open} onOpenChange={onOpenChange}>
      <PopoverTrigger asChild>
        <Button variant="ghost" size="icon" className="relative" aria-label={label} data-testid="notification-bell">
          <Bell aria-hidden="true" />
          {count > 0 ? (
            <span
              aria-hidden="true"
              className="absolute -right-0.5 -top-0.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-red-600 px-1 text-[10px] font-semibold text-white"
              data-testid="notification-count"
            >
              {count > 99 ? '99+' : count}
            </span>
          ) : null}
        </Button>
      </PopoverTrigger>
      <PopoverContent align="end" className="w-96 max-w-[calc(100vw-1rem)] p-0">
        <div className="flex items-center justify-between border-b px-4 py-2.5">
          <h2 className="text-sm font-semibold">Notifikasi</h2>
          <Button variant="ghost" size="sm" onClick={markAll} loading={pending} disabled={count === 0}>
            {!pending ? <CheckCheck aria-hidden="true" /> : null}
            Tandai semua dibaca
          </Button>
        </div>
        <div className="max-h-96 overflow-y-auto" aria-busy={loading}>
          {loading && !items ? (
            <p className="flex items-center gap-2 px-4 py-6 text-sm text-muted-foreground">
              <Loader2 className="size-4 animate-spin" aria-hidden="true" /> Memuat…
            </p>
          ) : items && items.length > 0 ? (
            <ul className="divide-y">
              {items.map((n) => (
                <li key={n.id}>
                  <Link
                    href={n.link ?? '/realisasi/notifikasi'}
                    onClick={() => openItem(n)}
                    className={cn('block px-4 py-3 text-sm hover:bg-muted focus-visible:bg-muted focus-visible:outline-none', !n.read_at && 'bg-blue-50/60')}
                  >
                    <span className="flex items-start gap-2">
                      {!n.read_at ? <span className="mt-1.5 size-2 shrink-0 rounded-full bg-blue-600" aria-hidden="true" /> : null}
                      <span className="min-w-0">
                        <span className={cn('block', !n.read_at && 'font-semibold')}>
                          {n.title}
                          {!n.read_at ? <span className="sr-only"> (belum dibaca)</span> : null}
                        </span>
                        {n.body ? <span className="mt-0.5 line-clamp-2 block text-xs text-muted-foreground">{n.body}</span> : null}
                        <span className="mt-1 block text-xs text-muted-foreground">{formatDateTime(n.created_at)}</span>
                      </span>
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
          ) : (
            <p className="px-4 py-6 text-sm text-muted-foreground">Belum ada notifikasi.</p>
          )}
        </div>
        <div className="border-t px-4 py-2 text-right">
          <Link href="/realisasi/notifikasi" onClick={() => setOpen(false)} className="text-sm font-medium text-primary underline-offset-4 hover:underline">
            Lihat semua notifikasi
          </Link>
        </div>
      </PopoverContent>
    </Popover>
  );
}
