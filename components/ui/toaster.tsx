'use client';

/** Sonner wrapper. Mount <Toaster /> once (root layout); call `toast.success(...)` anywhere on the client. */
import { Toaster as Sonner, toast } from 'sonner';

export function Toaster(props: React.ComponentProps<typeof Sonner>) {
  return (
    <Sonner
      position="top-right"
      closeButton
      richColors
      toastOptions={{ classNames: { toast: 'text-sm' } }}
      containerAriaLabel="Notifikasi"
      {...props}
    />
  );
}

export { toast };
