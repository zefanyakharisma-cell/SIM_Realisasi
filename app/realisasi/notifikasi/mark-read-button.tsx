'use client';

import * as React from 'react';
import { useRouter } from 'next/navigation';
import { CheckCheck } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { toast } from '@/components/ui/toaster';
import { markNotificationsRead } from '@/lib/realisasi/actions/notifications';

/** ids = null → mark all unread. */
export function MarkReadButton({ ids, label, disabled }: { ids: number[] | null; label: string; disabled?: boolean }) {
  const router = useRouter();
  const [pending, start] = React.useTransition();
  return (
    <Button
      variant={ids === null ? 'outline' : 'ghost'}
      size="sm"
      disabled={disabled}
      loading={pending}
      onClick={() =>
        start(async () => {
          const res = await markNotificationsRead(ids);
          if (!res.ok) {
            toast.error(res.message);
            return;
          }
          if (ids === null) toast.success(`${res.data} notifikasi ditandai dibaca`);
          router.refresh();
        })
      }
    >
      {!pending && ids === null ? <CheckCheck aria-hidden="true" /> : null}
      {label}
    </Button>
  );
}
