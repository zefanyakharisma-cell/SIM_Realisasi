import { describe, expect, it } from 'vitest';
import {
  activityFiltersToSearchParams,
  describeActivityFilters,
  hasActiveFilters,
  parseActivityFilters,
} from './filters';

describe('parseActivityFilters', () => {
  it('parses every key from URLSearchParams', () => {
    const f = parseActivityFilters(
      new URLSearchParams(
        'q=summer&status=verified,in_verification&agenda_id=23&direction=outbound&unit_id=10&country=jp&ay=1&semester=2&mobility=approved&late=1&from=2026-01-01&to=2026-12-31&preset=mine&queue=mobility&sort=waiting',
      ),
    );
    expect(f).toEqual({
      q: 'summer',
      status: ['verified', 'in_verification'],
      agenda_id: 23,
      direction: 'outbound',
      unit_id: 10,
      country: 'JP',
      ay: 1,
      semester: 2,
      mobility: 'approved',
      late: true,
      from: '2026-01-01',
      to: '2026-12-31',
      preset: 'mine',
      queue: 'mobility',
      sort: 'waiting',
    });
  });

  it('accepts Next.js searchParams records and drops invalid or removed values', () => {
    const f = parseActivityFilters({
      status: ['verified', 'rejected'],
      ay: 'x',
      from: '2026-02-30',
      sla: 'red',
      partnership: 'pending',
      queue: 'partnership',
      direction: 'none',
      q: '  ',
    });
    expect(f).toEqual({ status: ['verified'] });
  });

  it('round-trips through activityFiltersToSearchParams', () => {
    const sp = new URLSearchParams('status=verified&agenda_id=2&direction=inbound&ay=1');
    const f = parseActivityFilters(sp);
    expect(activityFiltersToSearchParams(f).toString()).toBe('status=verified&agenda_id=2&direction=inbound&ay=1');
    expect(parseActivityFilters(activityFiltersToSearchParams(f))).toEqual(f);
  });

  it('hasActiveFilters ignores sort and queue', () => {
    expect(hasActiveFilters({ sort: 'code', queue: 'mobility' })).toBe(false);
    expect(hasActiveFilters({ late: true })).toBe(true);
  });

  it('describes filters with resolvers', () => {
    const rows = describeActivityFilters(
      { status: ['verified'], ay: 1, agenda_id: 23, direction: 'outbound' },
      { agendaName: () => 'Short Program', ayLabel: () => '2025/2026' },
    );
    expect(rows).toEqual([
      ['Status', 'Terverifikasi'],
      ['Jenis Kegiatan', 'Short Program'],
      ['Inbound/Outbound', 'Outbound'],
      ['Tahun Akademik', '2025/2026'],
    ]);
  });
});
