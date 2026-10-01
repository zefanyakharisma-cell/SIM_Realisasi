'use client';

/**
 * Searchable single/multi select on Popover + Command (cmdk).
 * Trigger is a button with role="combobox", aria-expanded and aria-controls; selected values are
 * announced in its accessible name. Values are strings — convert numeric ids at the call site.
 */
import * as React from 'react';
import { Check, ChevronsUpDown, X } from 'lucide-react';
import { cn } from '@/lib/utils';
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from '@/components/ui/command';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';

export interface ComboboxOption {
  value: string;
  /** Plain text used for search and for the selected chip. */
  label: string;
  /** Rich content shown in the list instead of `label`. */
  content?: React.ReactNode;
  keywords?: string[];
  disabled?: boolean;
}

export interface ComboboxProps {
  options: ComboboxOption[];
  value: string[];
  onChange: (value: string[]) => void;
  multiple?: boolean;
  placeholder?: string;
  searchPlaceholder?: string;
  emptyText?: string;
  disabled?: boolean;
  id?: string;
  className?: string;
  'aria-invalid'?: boolean;
  'aria-describedby'?: string;
  'aria-labelledby'?: string;
  /** Hide selected chips under the trigger (caller renders the selection itself). */
  hideChips?: boolean;
}

export function Combobox({
  options,
  value,
  onChange,
  multiple = true,
  placeholder = 'Pilih…',
  searchPlaceholder = 'Cari…',
  emptyText = 'Tidak ada hasil.',
  disabled,
  id,
  className,
  hideChips,
  ...aria
}: ComboboxProps) {
  const [open, setOpen] = React.useState(false);
  const listId = React.useId();
  const byValue = React.useMemo(() => new Map(options.map((o) => [o.value, o])), [options]);
  const selected = value.map((v) => byValue.get(v)).filter((o): o is ComboboxOption => Boolean(o));

  const toggle = (v: string) => {
    if (multiple) {
      onChange(value.includes(v) ? value.filter((x) => x !== v) : [...value, v]);
    } else {
      onChange(value.includes(v) ? [] : [v]);
      setOpen(false);
    }
  };

  const summary =
    selected.length === 0 ? placeholder : multiple ? `${selected.length} dipilih` : (selected[0]?.label ?? placeholder);

  return (
    <div className={cn('space-y-2', className)}>
      <Popover open={open} onOpenChange={setOpen}>
        <PopoverTrigger asChild>
          <button
            type="button"
            id={id}
            role="combobox"
            aria-expanded={open}
            aria-controls={listId}
            aria-haspopup="listbox"
            disabled={disabled}
            className="flex h-9 w-full items-center justify-between rounded-md border border-input bg-background px-3 py-2 text-left text-sm shadow-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-50 aria-[invalid=true]:border-destructive"
            {...aria}
          >
            <span className={cn('truncate', selected.length === 0 && 'text-muted-foreground')}>{summary}</span>
            <ChevronsUpDown className="ml-2 size-4 shrink-0 opacity-60" aria-hidden="true" />
          </button>
        </PopoverTrigger>
        <PopoverContent className="w-[var(--radix-popover-trigger-width)] min-w-[18rem] p-0" align="start">
          <Command>
            <CommandInput placeholder={searchPlaceholder} />
            <CommandList id={listId} aria-multiselectable={multiple || undefined}>
              <CommandEmpty>{emptyText}</CommandEmpty>
              <CommandGroup>
                {options.map((o) => {
                  const isSelected = value.includes(o.value);
                  return (
                    <CommandItem
                      key={o.value}
                      value={`${o.label} ${o.value}`}
                      keywords={o.keywords}
                      disabled={o.disabled}
                      aria-selected={isSelected}
                      onSelect={() => toggle(o.value)}
                    >
                      <Check className={cn('mt-0.5 self-start', isSelected ? 'opacity-100' : 'opacity-0')} aria-hidden="true" />
                      <div className="min-w-0 flex-1">{o.content ?? o.label}</div>
                    </CommandItem>
                  );
                })}
              </CommandGroup>
            </CommandList>
          </Command>
        </PopoverContent>
      </Popover>
      {multiple && !hideChips && selected.length > 0 ? (
        <ul className="flex flex-wrap gap-1.5" aria-label="Pilihan terpilih">
          {selected.map((o) => (
            <li key={o.value} className="inline-flex items-center gap-1 rounded-full border bg-secondary px-2 py-0.5 text-xs">
              <span>{o.label}</span>
              <button
                type="button"
                disabled={disabled}
                onClick={() => toggle(o.value)}
                className="rounded-full p-0.5 hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                aria-label={`Hapus ${o.label}`}
              >
                <X className="size-3" aria-hidden="true" />
              </button>
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}
