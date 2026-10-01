/**
 * Formatting helpers (CONTRACTS §6.6) — Asia/Jakarta, Bahasa Indonesia. Pure; client-safe.
 *
 * Deterministic on purpose (no Intl date formatting): server and browser must render identical
 * strings to avoid hydration mismatches, whatever the host time zone / ICU data.
 * - 'YYYY-MM-DD' strings are calendar dates: never shifted by a time zone.
 * - Timestamps are converted to WIB (UTC+7; Indonesia has no DST).
 */
import type { DateString, Timestamp } from '@/lib/realisasi/types';

const MONTHS_SHORT = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'] as const;
const WIB_OFFSET_MS = 7 * 60 * 60 * 1000;
const DATE_ONLY_RE = /^(\d{4})-(\d{2})-(\d{2})$/;
const EMPTY = '–';

interface Parts {
  year: number;
  month: number; // 1-12
  day: number;
  hour: number;
  minute: number;
}

function pad2(n: number): string {
  return String(n).padStart(2, '0');
}

/** Splits a date or timestamp into WIB calendar parts; null when unparseable. */
function toParts(value: DateString | Timestamp | Date): Parts | null {
  if (typeof value === 'string') {
    const m = DATE_ONLY_RE.exec(value);
    if (m) return { year: Number(m[1]), month: Number(m[2]), day: Number(m[3]), hour: 0, minute: 0 };
  }
  const d = value instanceof Date ? value : new Date(value);
  const t = d.getTime();
  if (Number.isNaN(t)) return null;
  const wib = new Date(t + WIB_OFFSET_MS);
  return {
    year: wib.getUTCFullYear(),
    month: wib.getUTCMonth() + 1,
    day: wib.getUTCDate(),
    hour: wib.getUTCHours(),
    minute: wib.getUTCMinutes(),
  };
}

/** '14 Sep 2026'; '–' for null/invalid. */
export function formatDate(d: DateString | Timestamp | null | undefined): string {
  if (!d) return EMPTY;
  const p = toParts(d);
  if (!p) return EMPTY;
  return `${p.day} ${MONTHS_SHORT[p.month - 1]} ${p.year}`;
}

/** '14-09-2026'; '–' for null/invalid. */
export function formatDateNumeric(d: DateString | Timestamp | null | undefined): string {
  if (!d) return EMPTY;
  const p = toParts(d);
  if (!p) return EMPTY;
  return `${pad2(p.day)}-${pad2(p.month)}-${p.year}`;
}

/** '14 Sep 2026 10:42' (WIB); a date-only string renders as formatDate. */
export function formatDateTime(ts: Timestamp | null | undefined): string {
  if (!ts) return EMPTY;
  if (DATE_ONLY_RE.test(ts)) return formatDate(ts);
  const p = toParts(ts);
  if (!p) return EMPTY;
  return `${p.day} ${MONTHS_SHORT[p.month - 1]} ${p.year} ${pad2(p.hour)}:${pad2(p.minute)}`;
}

/** '10:42' (WIB). */
export function formatTime(ts: Timestamp | null | undefined): string {
  if (!ts) return EMPTY;
  const p = toParts(ts);
  if (!p) return EMPTY;
  return `${pad2(p.hour)}:${pad2(p.minute)}`;
}

function groupThousands(intPart: string): string {
  return intPart.replace(/\B(?=(\d{3})+(?!\d))/g, '.');
}

/** '1.234' (id-ID grouping; decimals with comma). */
export function formatNumber(n: number | null | undefined): string {
  if (n === null || n === undefined || !Number.isFinite(n)) return EMPTY;
  const negative = n < 0;
  const [intPart = '0', frac] = String(Math.abs(n)).split('.');
  const body = groupThousands(intPart) + (frac ? `,${frac}` : '');
  return negative ? `-${body}` : body;
}

/** One-decimal percentage, input already in percent: 62.3 → '62,3%'; '–' for null. */
export function formatPct(n: number | null | undefined): string {
  if (n === null || n === undefined || !Number.isFinite(n)) return EMPTY;
  const fixed = Math.abs(n).toFixed(1);
  const [intPart = '0', frac = '0'] = fixed.split('.');
  const sign = n < 0 && Number(fixed) !== 0 ? '-' : '';
  return `${sign}${groupThousands(intPart)},${frac}%`;
}

/** '1,2 MB' / '340 KB' / '512 B'. */
export function formatBytes(n: number): string {
  if (!Number.isFinite(n) || n < 0) return EMPTY;
  if (n < 1024) return `${n} B`;
  const units = ['KB', 'MB', 'GB'] as const;
  let value = n / 1024;
  let i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i += 1;
  }
  const text = value >= 100 ? String(Math.round(value)) : value.toFixed(1).replace(/\.0$/, '').replace('.', ',');
  return `${text} ${units[i]}`;
}

function dayNumber(d: DateString): number {
  const m = DATE_ONLY_RE.exec(d);
  if (!m) throw new RangeError(`Invalid DateString: ${d}`);
  return Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])) / 86_400_000;
}

/** Inclusive number of calendar days: same day → 1. */
export function durationDays(start: DateString, end: DateString): number {
  return dayNumber(end) - dayNumber(start) + 1;
}

/** Calendar-day difference `to - from` (negative when `to` is earlier). */
export function daysBetween(from: DateString, to: DateString): number {
  return dayNumber(to) - dayNumber(from);
}

function sanitizeSegment(s: string): string {
  return s
    .trim()
    .replace(/[\s/\\]+/g, '-')
    .replace(/[^A-Za-z0-9._()-]/g, '')
    .replace(/-{2,}/g, '-')
    .replace(/^-|-$/g, '');
}

/** SIM-Realisasi_{kind}_{period}_{yyyyMMdd-HHmm}.xlsx (timestamp in WIB). */
export function exportFilename(kind: string, periodLabel: string, at: Date = new Date()): string {
  const p = toParts(at);
  const stamp = p ? `${p.year}${pad2(p.month)}${pad2(p.day)}-${pad2(p.hour)}${pad2(p.minute)}` : 'unknown';
  const period = sanitizeSegment(periodLabel) || 'semua';
  return `SIM-Realisasi_${sanitizeSegment(kind)}_${period}_${stamp}.xlsx`;
}
