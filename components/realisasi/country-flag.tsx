import { cn } from '@/lib/utils';

/** Regional-indicator emoji for an ISO-3166 alpha-2 code ('JP' → 🇯🇵); '' for invalid codes. */
export function flagEmoji(code: string | null | undefined): string {
  if (!code || !/^[A-Za-z]{2}$/.test(code)) return '';
  const base = 0x1f1e6;
  return String.fromCodePoint(...code.toUpperCase().split('').map((c) => base + c.charCodeAt(0) - 65));
}

/** Emoji flag + code. The emoji is decorative; the code (and `name` as title/sr text) carries meaning. */
export function CountryFlag({ code, name, className }: { code: string | null | undefined; name?: string | null; className?: string }) {
  if (!code) return <span className={cn('text-muted-foreground', className)}>–</span>;
  return (
    <span className={cn('inline-flex items-center gap-1 whitespace-nowrap', className)} title={name ?? undefined}>
      <span aria-hidden="true">{flagEmoji(code)}</span>
      <span>{code.toUpperCase()}</span>
      {name ? <span className="sr-only"> ({name})</span> : null}
    </span>
  );
}
