/** URL-driven tab navigation for the activity detail page (`?tab=`). Server-safe. */
import Link from 'next/link';
import { cn } from '@/lib/utils';

export type ActivityTab = 'detail' | 'peserta' | 'berkas' | 'riwayat';

export function ActivityTabs({ activityId, current, tabs }: { activityId: string; current: ActivityTab; tabs: Array<{ id: ActivityTab; label: string }> }) {
  return (
    <nav aria-label="Bagian kegiatan" className="border-b">
      <ul className="-mb-px flex flex-wrap gap-1">
        {tabs.map((t) => (
          <li key={t.id}>
            <Link
              href={`/realisasi/kegiatan/${activityId}?tab=${t.id}`}
              aria-current={t.id === current ? 'page' : undefined}
              data-testid={`tab-${t.id}`}
              className={cn(
                'inline-block border-b-2 px-4 py-2 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                t.id === current ? 'border-primary text-foreground' : 'border-transparent text-muted-foreground hover:text-foreground',
              )}
            >
              {t.label}
            </Link>
          </li>
        ))}
      </ul>
    </nav>
  );
}
