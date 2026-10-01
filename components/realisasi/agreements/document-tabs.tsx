// Tabs of a SIM Kerjasama document page (Design §3.10). Server-safe.
import Link from 'next/link';
import { cn } from '@/lib/utils';

export function DocumentTabs({ id, current }: { id: number; current: 'realisasi' | 'evaluasi' }) {
  const tab = (key: 'realisasi' | 'evaluasi', label: string) => (
    <Link
      href={`/kerjasama/dokumen/${id}/${key}`}
      aria-current={current === key ? 'page' : undefined}
      data-testid={`doc-tab-${key}`}
      className={cn(
        '-mb-px border-b-2 px-4 py-2 text-sm',
        current === key ? 'border-primary font-medium text-primary' : 'border-transparent text-muted-foreground hover:text-foreground',
      )}
    >
      {label}
    </Link>
  );
  return (
    <nav aria-label="Tab dokumen" className="flex gap-1 border-b">
      <span className="-mb-px cursor-not-allowed border-b-2 border-transparent px-4 py-2 text-sm text-muted-foreground" aria-disabled="true" title="Tersedia di SIM Kerjasama">
        Detail
      </span>
      {tab('realisasi', 'Realisasi')}
      {tab('evaluasi', 'Evaluasi perpanjangan')}
    </nav>
  );
}
