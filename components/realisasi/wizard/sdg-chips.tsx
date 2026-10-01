'use client';
/** 17 SDG toggle chips in the official colours (Design §3.3). Toggle state via aria-pressed. */
import { Check } from 'lucide-react';
import { SDGS } from '@/components/realisasi/activity/sdg';
import { cn } from '@/lib/utils';

export function SdgChips({
  value,
  onChange,
  names,
  labelId,
  disabled,
}: {
  value: number[];
  onChange: (ids: number[]) => void;
  /** Names from `realisasi.sdgs` (fall back to the built-in list). */
  names?: Record<number, string>;
  labelId: string;
  disabled?: boolean;
}) {
  const toggle = (id: number) =>
    onChange(value.includes(id) ? value.filter((x) => x !== id) : [...value, id].sort((a, b) => a - b));
  return (
    <div role="group" aria-labelledby={labelId} className="flex flex-wrap gap-2">
      {SDGS.map((s) => {
        const on = value.includes(s.id);
        const name = names?.[s.id] ?? s.name;
        return (
          <button
            key={s.id}
            type="button"
            aria-pressed={on}
            disabled={disabled}
            onClick={() => toggle(s.id)}
            title={name}
            className={cn(
              'inline-flex min-h-8 items-center gap-1 rounded-full border-2 px-3 py-1 text-xs font-medium transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:opacity-50',
              !on && 'bg-background text-foreground hover:bg-muted',
            )}
            style={on ? { backgroundColor: s.color, borderColor: s.color, color: s.text } : { borderColor: s.color }}
          >
            {on && <Check className="h-3 w-3" aria-hidden />}
            <span className="font-semibold">{s.id}</span>
            <span>{name}</span>
          </button>
        );
      })}
    </div>
  );
}
