'use client';
/** "Hapus draf" with confirmation (R-15: drafts only, by their creator or IO Admin; hard delete incl. files). */
import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { Trash2 } from 'lucide-react';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from '@/components/ui/alert-dialog';
import { Button } from '@/components/ui/button';
import { toast } from '@/components/ui/toaster';
import { deleteDraft } from '@/lib/realisasi/actions/submission';

export function DeleteDraftButton({
  activityId,
  code,
  compact = false,
}: {
  activityId: string;
  code: string;
  /** icon-only trigger for list rows; stays on the list after deleting */
  compact?: boolean;
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function onConfirm(e: React.MouseEvent) {
    e.preventDefault();
    setError(null);
    startTransition(async () => {
      const res = await deleteDraft(activityId);
      if (!res.ok) {
        setError(res.message);
        return;
      }
      setOpen(false);
      toast.success(`Draf ${code} dihapus.`);
      if (!compact) router.push('/realisasi/kegiatan');
      router.refresh();
    });
  }

  return (
    <AlertDialog open={open} onOpenChange={setOpen}>
      <AlertDialogTrigger asChild>
        {compact ? (
          <Button variant="ghost" size="icon" className="h-7 w-7" aria-label={`Hapus draf ${code}`} data-testid={`delete-draft-${code}`}>
            <Trash2 aria-hidden />
          </Button>
        ) : (
          <Button variant="outline" size="sm" data-testid="delete-draft">
            <Trash2 aria-hidden /> Hapus draf
          </Button>
        )}
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Hapus draf {code}?</AlertDialogTitle>
          <AlertDialogDescription>
            Draf beserta berkas dan data pesertanya akan dihapus permanen. Tindakan ini tidak dapat dibatalkan.
          </AlertDialogDescription>
        </AlertDialogHeader>
        {error && (
          <p className="text-sm text-destructive" role="alert">
            {error}
          </p>
        )}
        <AlertDialogFooter>
          <AlertDialogCancel disabled={pending}>Batal</AlertDialogCancel>
          <AlertDialogAction asChild>
            <Button variant="destructive" onClick={onConfirm} loading={pending} data-testid="confirm-delete-draft">
              Hapus draf
            </Button>
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
