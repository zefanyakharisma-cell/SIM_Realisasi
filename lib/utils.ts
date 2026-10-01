import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

/** Merges Tailwind class names (shadcn convention). */
export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs));
}

/** Builds a query string from a record/URLSearchParams, dropping empty values. Returns '' or '?a=b'. */
export function toQueryString(params?: URLSearchParams | Record<string, string | number | boolean | null | undefined>): string {
  if (!params) return '';
  const sp = new URLSearchParams();
  const entries: Array<[string, unknown]> =
    params instanceof URLSearchParams ? Array.from(params.entries()) : Object.entries(params);
  for (const [k, v] of entries) {
    if (v === undefined || v === null || v === '') continue;
    sp.append(k, String(v));
  }
  const s = sp.toString();
  return s ? `?${s}` : '';
}
