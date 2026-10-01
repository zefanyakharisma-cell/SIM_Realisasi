import { describe, expect, it } from 'vitest';
import { isCrossOriginWrite } from './origin-check';

const h = (o: Record<string, string>) => ({ get: (k: string) => o[k.toLowerCase()] ?? null });

describe('isCrossOriginWrite (security review L-1)', () => {
  it('allows reads and same-origin writes', () => {
    expect(isCrossOriginWrite('GET', h({ origin: 'https://evil.example' }), 'app.petra.ac.id')).toBe(false);
    expect(isCrossOriginWrite('POST', h({ origin: 'https://app.petra.ac.id', 'sec-fetch-site': 'same-origin' }), 'app.petra.ac.id')).toBe(false);
    expect(isCrossOriginWrite('POST', h({}), 'app.petra.ac.id')).toBe(false);
  });
  it('refuses cross-site and same-site (sibling subdomain) writes', () => {
    expect(isCrossOriginWrite('POST', h({ origin: 'https://evil.petra.ac.id', 'sec-fetch-site': 'same-site' }), 'app.petra.ac.id')).toBe(true);
    expect(isCrossOriginWrite('POST', h({ 'sec-fetch-site': 'cross-site' }), 'app.petra.ac.id')).toBe(true);
    expect(isCrossOriginWrite('DELETE', h({ origin: 'https://evil.example' }), 'app.petra.ac.id')).toBe(true);
    expect(isCrossOriginWrite('POST', h({ origin: 'null' }), 'app.petra.ac.id')).toBe(true);
  });
});
