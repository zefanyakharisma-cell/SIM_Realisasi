'use client';

import { useEffect, useId, useRef, useState, useTransition, type ReactNode } from 'react';
import { useRouter } from 'next/navigation';
import { AlertCircle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog';
import { toast } from '@/components/ui/toaster';
import { cn } from '@/lib/utils';
import type { ActionResult } from '@/lib/realisasi/types';

type ButtonVariant = 'default' | 'outline' | 'destructive' | 'secondary' | 'ghost';

export interface ActionDialogProps<T> {
  /** Trigger button content. */
  triggerLabel: ReactNode;
  triggerVariant?: ButtonVariant;
  triggerSize?: 'sm' | 'default';
  triggerTestId?: string;
  triggerDisabled?: boolean;
  triggerClassName?: string;
  title: string;
  description?: ReactNode;
  confirmLabel: string;
  confirmVariant?: ButtonVariant;
  /** Form body; receives the field-error map produced by the last `onConfirm`. */
  children?: (state: { errors: Partial<Record<string, string>>; pending: boolean }) => ReactNode;
  /** Client-side validation; a non-empty map blocks the action and renders inline errors. */
  validate?: () => Partial<Record<string, string>>;
  /** The server action. `ok` → toast(successMessage), close, router.refresh(). */
  action: () => Promise<ActionResult<T>>;
  successMessage: string | ((data: T) => string);
  onSuccess?: (data: T) => void;
  /** Reset caller-owned form state when the dialog opens/closes. */
  onOpenChange?: (open: boolean) => void;
  wide?: boolean;
}

/** Maps contract error codes to the field they belong to, so the message renders inline. */
const CODE_FIELD: Record<string, string> = {
  R27_NOTE_REQUIRED: 'note',
  R26_NOTE_REQUIRED: 'note',
  R26_REASON_REQUIRED: 'reason',
  VALIDATION_REQUIRED: 'note',
};

/**
 * Confirmation dialog for one verification action: focus-trapped (Radix), inline field errors
 * (aria-invalid + described-by in the caller's fields), a top-level `role="alert"` summary for
 * server errors, and router refresh on success.
 */
export function ActionDialog<T>({
  triggerLabel,
  triggerVariant = 'default',
  triggerSize = 'sm',
  triggerTestId,
  triggerDisabled,
  triggerClassName,
  title,
  description,
  confirmLabel,
  confirmVariant = 'default',
  children,
  validate,
  action,
  successMessage,
  onSuccess,
  onOpenChange,
  wide,
}: ActionDialogProps<T>) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [errors, setErrors] = useState<Partial<Record<string, string>>>({});
  const [serverError, setServerError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const errorId = useId();
  const formRef = useRef<HTMLFormElement>(null);

  // Move focus to the first invalid field so the inline error is announced (WCAG 3.3.1).
  useEffect(() => {
    if (!Object.values(errors).some(Boolean)) return;
    formRef.current?.querySelector<HTMLElement>('[aria-invalid="true"]')?.focus();
  }, [errors]);

  function handleOpenChange(next: boolean) {
    if (pending) return;
    setOpen(next);
    setErrors({});
    setServerError(null);
    onOpenChange?.(next);
  }

  function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setServerError(null);
    const clientErrors = validate?.() ?? {};
    setErrors(clientErrors);
    if (Object.values(clientErrors).some(Boolean)) return;
    startTransition(async () => {
      const res = await action();
      if (res.ok) {
        toast.success(typeof successMessage === 'function' ? successMessage(res.data) : successMessage);
        setOpen(false);
        onOpenChange?.(false);
        onSuccess?.(res.data);
        router.refresh();
        return;
      }
      const field = CODE_FIELD[res.code];
      if (field) setErrors({ [field]: res.message });
      else setServerError(res.message);
    });
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogTrigger asChild>
        <Button
          type="button"
          variant={triggerVariant}
          size={triggerSize}
          data-testid={triggerTestId}
          disabled={triggerDisabled}
          className={triggerClassName}
        >
          {triggerLabel}
        </Button>
      </DialogTrigger>
      <DialogContent className={cn(wide ? 'sm:max-w-3xl' : 'sm:max-w-lg', 'max-h-[90vh] overflow-y-auto')}>
        <form ref={formRef} onSubmit={handleSubmit} noValidate aria-describedby={serverError ? errorId : undefined}>
          <DialogHeader>
            <DialogTitle>{title}</DialogTitle>
            {description ? <DialogDescription>{description}</DialogDescription> : null}
          </DialogHeader>
          {serverError ? (
            <div
              id={errorId}
              role="alert"
              className="mt-4 flex items-start gap-2 rounded-md border border-red-300 bg-red-50 p-3 text-sm text-red-900 dark:border-red-800 dark:bg-red-950/50 dark:text-red-200"
            >
              <AlertCircle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
              <span>{serverError}</span>
            </div>
          ) : null}
          {children ? <div className="mt-4 space-y-4">{children({ errors, pending })}</div> : null}
          <DialogFooter className="mt-6 gap-2">
            <Button type="button" variant="outline" onClick={() => handleOpenChange(false)} disabled={pending}>
              Batal
            </Button>
            <Button type="submit" variant={confirmVariant} loading={pending} data-testid="action-confirm">
              {confirmLabel}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

/** Labelled textarea with inline error, used inside ActionDialog bodies. */
export function NoteField({
  id,
  label,
  value,
  onChange,
  error,
  required,
  placeholder,
  disabled,
}: {
  id: string;
  label: string;
  value: string;
  onChange: (v: string) => void;
  error?: string;
  required?: boolean;
  placeholder?: string;
  disabled?: boolean;
}) {
  const errId = `${id}-error`;
  return (
    <div className="space-y-1.5">
      <label htmlFor={id} className="text-sm font-medium">
        {label}
        {required ? (
          <span className="text-red-700 dark:text-red-400">
            {' '}*<span className="sr-only"> (wajib)</span>
          </span>
        ) : (
          <span className="font-normal text-muted-foreground"> (opsional)</span>
        )}
      </label>
      <Textarea
        id={id}
        name={id}
        rows={4}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        disabled={disabled}
        aria-invalid={error ? true : undefined}
        aria-describedby={error ? errId : undefined}
        aria-required={required || undefined}
        className={cn('min-h-[96px]', error && 'border-red-600 focus-visible:ring-red-600')}
      />
      {error ? (
        <p id={errId} className="flex items-center gap-1 text-sm text-red-700 dark:text-red-400">
          <AlertCircle className="h-3.5 w-3.5" aria-hidden="true" />
          {error}
        </p>
      ) : null}
    </div>
  );
}
