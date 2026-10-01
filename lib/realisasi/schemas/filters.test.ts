import { describe, expect, it } from 'vitest';
import {
  activityFiltersToSearchParams,
  describeActivityFilters,
  hasActiveFilters,
  parseActivityFilters,
} from './filters';
import { knownFiltersToSearchParams, parseKnownFilters } from './known';

describe('parseActivityFilters', () => {
  it('parses every key from URLSearchParams', () => {
    const f = parseActivityFilters(
      new URLSearchParams(
        'q=summer&status=verified,rejected&type_id=7&unit_id=10&country=jp&ay=1&semester=2&partnership=pending&mobility=approved&late=1&sla=red&from=2026-01-01&to=2026-12-31&preset=mine&queue=partnership&sort=sla',
      ),
    );
    expect(f).toEqual({
      q: 'summer',
      status: ['verified', 'rejected'],
      type_id: 7,
      unit_id: 10,
      country: 'JP',
      ay: 1,
      semester: 2,
      partnership: 'pending',
      mobility: 'approved',
      late: true,
      sla: 'red',
      from: '2026-01-01',
      to: '2026-12-31',
      preset: 'mine',
      queue: 'partnership',
      sort: 'sla',
    });
  });

  it('accepts Next.js searchParams records and drops invalid values', () => {
    const f = parseActivityFilters({ status: ['verified', 'bogus'], ay: 'x', from: '2026-02-30', sla: 'blue', q: '  ' });
    expect(f).toEqual({ status: ['verified'] });
  });

  it('round-trips through activityFiltersToSearchParams', () => {
    const sp = new URLSearchParams('status=verified&ay=1');
    const f = parseActivityFilters(sp);
    expect(activityFiltersToSearchParams(f).toString()).toBe('status=verified&ay=1');
    expect(parseActivityFilters(activityFiltersToSearchParams(f))).toEqual(f);
  });

  it('hasActiveFilters ignores sort and queue', () => {
    expect(hasActiveFilters({ sort: 'code', queue: 'mobility' })).toBe(false);
    expect(hasActiveFilters({ late: true })).toBe(true);
  });

  it('describes filters with resolvers', () => {
    const rows = describeActivityFilters(
      { status: ['verified'], ay: 1, type_id: 7 },
      { typeName: () => 'Summer Program', ayLabel: () => '2025/2026' },
    );
    expect(rows).toEqual([
      ['Status', 'Terverifikasi'],
      ['Jenis Kegiatan', 'Summer Program'],
      ['Tahun Akademik', '2025/2026'],
    ]);
  });
});

describe('known filters', () => {
  it('parses and serializes', () => {
    const f = parseKnownFilters({ status: 'unmatched', intl: '1', unit_id: '20', from: '2026-08-01' });
    expect(f).toEqual({ status: 'unmatched', intl: true, unit_id: 20, from: '2026-08-01' });
    expect(knownFiltersToSearchParams(f).toString()).toBe('status=unmatched&unit_id=20&intl=1&from=2026-08-01');
    expect(parseKnownFilters({ status: 'nope' })).toEqual({});
  });
});
