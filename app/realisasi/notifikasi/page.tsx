import type { Metadata } from 'next';
import Link from 'next/link';
import { Bell } from 'lucide-react';
import { Card } from '@/components/ui/card';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { EmptyState } from '@/components/realisasi/empty-state';
import { PageHeader } from '@/components/realisasi/page-header';
import { requireUser } from '@/lib/session';
import { listNotifications } from '@/lib/realisasi/actions/notifications';
import { formatDateTime } from '@/lib/realisasi/format';
import { cn } from '@/lib/utils';
import { MarkReadButton } from './mark-read-button';

export const metadata: Metadata = { title: 'Notifikasi' };

export default async function NotificationsPage(props: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  await requireUser();
  const sp = await props.searchParams;
  const unreadOnly = sp.filter === 'belum';
  const res = await listNotifications({ limit: 200, unreadOnly });
  const items = res.ok ? res.data : [];
  const unread = items.filter((n) => !n.read_at).length;

  return (
    <div className="mx-auto max-w-3xl">
      <PageHeader
        title="Notifikasi"
        description="Pemberitahuan untuk akun Anda. Salinan email tercatat di outbox (mockup, tidak dikirim)."
        actions={<MarkReadButton ids={null} label="Tandai semua dibaca" disabled={!unreadOnly && unread === 0} />}
      />
      <nav aria-label="Saring notifikasi" className="mb-4 flex gap-2 text-sm">
        <Link
          href="/realisasi/notifikasi"
          aria-current={!unreadOnly ? 'page' : undefined}
          className={cn('rounded-full border px-3 py-1', !unreadOnly ? 'border-primary bg-primary text-primary-foreground' : 'bg-background hover:bg-accent')}
        >
          Semua
        </Link>
        <Link
          href="/realisasi/notifikasi?filter=belum"
          aria-current={unreadOnly ? 'page' : undefined}
          className={cn('rounded-full border px-3 py-1', unreadOnly ? 'border-primary bg-primary text-primary-foreground' : 'bg-background hover:bg-accent')}
        >
          Belum dibaca
        </Link>
      </nav>

      {!res.ok ? (
        <Alert variant="destructive" role="alert">
          <AlertDescription>{res.message}</AlertDescription>
        </Alert>
      ) : items.length === 0 ? (
        <EmptyState icon={<Bell className="size-8" />} title={unreadOnly ? 'Tidak ada notifikasi yang belum dibaca.' : 'Belum ada notifikasi.'} />
      ) : (
        <Card>
          <ul className="divide-y" data-testid="notification-list">
            {items.map((n) => (
              <li key={n.id} className={cn('flex items-start gap-3 px-4 py-3', !n.read_at && 'bg-blue-50/60')}>
                <span className={cn('mt-2 size-2 shrink-0 rounded-full', n.read_at ? 'bg-transparent' : 'bg-blue-600')} aria-hidden="true" />
                <div className="min-w-0 flex-1">
                  <p className={cn('text-sm', !n.read_at && 'font-semibold')}>
                    {n.link ? (
                      <Link href={n.link} className="underline-offset-4 hover:underline">
                        {n.title}
                      </Link>
                    ) : (
                      n.title
                    )}
                    {!n.read_at ? <span className="sr-only"> (belum dibaca)</span> : null}
                  </p>
                  {n.body ? <p className="mt-0.5 text-sm text-muted-foreground">{n.body}</p> : null}
                  <p className="mt-1 text-xs text-muted-foreground">
                    <time dateTime={n.created_at}>{formatDateTime(n.created_at)}</time>
                  </p>
                </div>
                {!n.read_at ? <MarkReadButton ids={[n.id]} label="Tandai dibaca" /> : null}
              </li>
            ))}
          </ul>
        </Card>
      )}
    </div>
  );
}
