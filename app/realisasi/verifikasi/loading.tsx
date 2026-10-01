import { Skeleton } from '@/components/ui/skeleton';

export default function Loading() {
  return (
    <div className="space-y-4" role="status" aria-label="Memuat antrean">
      <Skeleton className="h-8 w-64" />
      <div className="space-y-2 rounded-lg border p-4">
        {Array.from({ length: 6 }, (_, i) => (
          <Skeleton key={i} className="h-10 w-full" />
        ))}
      </div>
      <span className="sr-only">Memuat…</span>
    </div>
  );
}
