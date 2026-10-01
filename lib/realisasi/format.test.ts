import { describe, expect, it } from 'vitest';
import {
  daysBetween,
  durationDays,
  exportFilename,
  formatBytes,
  formatDate,
  formatDateNumeric,
  formatDateTime,
  formatNumber,
  formatPct,
  formatTime,
} from './format';

describe('dates (Asia/Jakarta)', () => {
  it('formats date-only strings without any time-zone shift', () => {
    expect(formatDate('2026-09-14')).toBe('14 Sep 2026');
    expect(formatDate('2026-03-02')).toBe('2 Mar 2026');
    expect(formatDate('2026-05-01')).toBe('1 Mei 2026');
    expect(formatDate('2026-12-31')).toBe('31 Des 2026');
    expect(formatDateNumeric('2026-09-14')).toBe('14-09-2026');
  });

  it('converts timestamps to WIB', () => {
    // 2026-09-30T20:30Z = 2026-10-01 03:30 WIB
    expect(formatDate('2026-09-30T20:30:00.000Z')).toBe('1 Okt 2026');
    expect(formatDateTime('2026-09-30T20:30:00.000Z')).toBe('1 Okt 2026 03:30');
    expect(formatDateTime('2026-09-14T10:42:00+07:00')).toBe('14 Sep 2026 10:42');
    expect(formatTime('2026-09-14T03:42:00Z')).toBe('10:42');
    expect(formatDateNumeric('2026-08-29T18:00:00Z')).toBe('30-08-2026');
  });

  it('renders an en dash for missing or invalid values', () => {
    expect(formatDate(null)).toBe('–');
    expect(formatDate(undefined)).toBe('–');
    expect(formatDate('not a date')).toBe('–');
    expect(formatDateTime(null)).toBe('–');
    expect(formatDateNumeric('')).toBe('–');
  });

  it('formatDateTime of a date-only string is the date', () => {
    expect(formatDateTime('2026-09-14')).toBe('14 Sep 2026');
  });

  it('computes inclusive durations and day differences', () => {
    expect(durationDays('2026-08-03', '2026-08-21')).toBe(19);
    expect(durationDays('2026-09-07', '2026-09-07')).toBe(1);
    expect(durationDays('2026-02-27', '2026-03-01')).toBe(3);
    expect(daysBetween('2026-10-01', '2026-09-13')).toBe(-18);
    expect(() => durationDays('x', '2026-01-01')).toThrow(RangeError);
  });
});

describe('numbers', () => {
  it('groups thousands with dots', () => {
    expect(formatNumber(1234)).toBe('1.234');
    expect(formatNumber(1234567)).toBe('1.234.567');
    expect(formatNumber(0)).toBe('0');
    expect(formatNumber(-1500)).toBe('-1.500');
    expect(formatNumber(2.5)).toBe('2,5');
    expect(formatNumber(null)).toBe('–');
  });

  it('formats percentages with one decimal and comma', () => {
    expect(formatPct(62.3)).toBe('62,3%');
    expect(formatPct(40)).toBe('40,0%');
    expect(formatPct(81.85)).toMatch(/^81,(8|9)%$/);
    expect(formatPct(100)).toBe('100,0%');
    expect(formatPct(null)).toBe('–');
  });

  it('formats byte sizes', () => {
    expect(formatBytes(512)).toBe('512 B');
    expect(formatBytes(1024)).toBe('1 KB');
    expect(formatBytes(1_258_291)).toBe('1,2 MB');
    expect(formatBytes(340 * 1024)).toBe('340 KB');
    expect(formatBytes(10 * 1024 * 1024)).toBe('10 MB');
  });
});

describe('exportFilename', () => {
  it('sanitizes the period and stamps WIB time', () => {
    const at = new Date('2026-10-01T02:05:00Z'); // 09:05 WIB
    expect(exportFilename('kpi-summary', 'Ganjil 2025/2026 (YTD)', at)).toBe(
      'SIM-Realisasi_kpi-summary_Ganjil-2025-2026-(YTD)_20261001-0905.xlsx',
    );
    expect(exportFilename('activities', 'Live 2026/2027', new Date('2026-09-30T18:30:00Z'))).toBe(
      'SIM-Realisasi_activities_Live-2026-2027_20261001-0130.xlsx',
    );
  });

  it('never yields an empty period segment', () => {
    expect(exportFilename('duplicates', '  ', new Date('2026-10-01T00:00:00Z'))).toBe(
      'SIM-Realisasi_duplicates_semua_20261001-0700.xlsx',
    );
  });
});

describe('formatNumber float noise (frontend review L-17)', () => {
  it('formats non-integers in fixed point', async () => {
    const { formatNumber } = await import('./format');
    expect(formatNumber(0.1 + 0.2)).toBe('0,3');
    expect(formatNumber(1e21)).toBe('1.000.000.000.000.000.000.000');
    expect(formatNumber(2.5)).toBe('2,5');
    expect(formatNumber(-1234.5)).toBe('-1.234,5');
    expect(formatNumber(1000)).toBe('1.000');
  });
});
