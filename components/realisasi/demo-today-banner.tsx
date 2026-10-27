import { Clock } from 'lucide-react';
import { formatDate } from '@/lib/realisasi/format';

/** Shown across the app while `settings.demo_today` is set (time travel, R-62). */
export function DemoTodayBanner({ demoToday, canManage = false }: { demoToday: string | null; canManage?: boolean }) {
  if (!demoToday) return null;
  return (
    <div role="status" className="flex flex-wrap items-center gap-2 border-b border-warning-line bg-warning-subtle px-4 py-2 text-sm text-warning-fg" data-testid="demo-today-banner">
      <Clock className="size-4 shrink-0" aria-hidden="true" />
      <span>
        Mode simulasi tanggal aktif — sistem menganggap hari ini <strong>{formatDate(demoToday)}</strong>.
      </span>
      {canManage ? (
        <a href="/realisasi/pengaturan?tab=umum" className="font-medium underline underline-offset-2">
          Ubah di Pengaturan
        </a>
      ) : null}
    </div>
  );
}
