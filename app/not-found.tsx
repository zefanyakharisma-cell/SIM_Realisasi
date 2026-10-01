import Link from 'next/link';
import { buttonVariants } from '@/components/ui/button';

export default function NotFound() {
  return (
    <main className="flex min-h-[60vh] flex-col items-center justify-center gap-3 px-4 text-center">
      <p className="text-sm font-semibold text-muted-foreground">404</p>
      <h1 className="text-2xl font-semibold">Halaman tidak ditemukan</h1>
      <p className="max-w-md text-sm text-muted-foreground">Halaman atau data yang Anda cari tidak ada, atau Anda tidak memiliki akses ke data tersebut.</p>
      <Link href="/realisasi" className={buttonVariants({ variant: 'outline' })}>
        Kembali ke Dashboard
      </Link>
    </main>
  );
}
