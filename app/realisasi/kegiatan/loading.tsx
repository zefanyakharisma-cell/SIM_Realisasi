import { Skeleton } from '@/components/ui/skeleton';

export default function Loading() {
  return (
    <div className="space-y-4" role="status" aria-label="Memuat kegiatan">
      <Skeleton className="h-8 w-48" />
      <Skeleton className="h-8 w-full max-w-xl" />
      <div className="space-y-2 rounded-lg border p-4">
        {Array.from({ length: 8 }, (_, i) => (
          <Skeleton key={i} className="h-9 w-full" />
        ))}
      </div>
      <span className="sr-only">Memuat…</span>
    </div>
  );
}
