import { expect, test } from '@playwright/test';
import { ACCOUNTS, loginAs } from './helpers';

/** Security review fixes (H-1, M-1, M-2, L-1, L-4) checked against the running app. */

test('M-2: security headers are set and X-Powered-By is gone', async ({ request }) => {
  const res = await request.get('/login');
  const h = res.headers();
  expect(h['x-powered-by']).toBeUndefined();
  expect(h['content-security-policy']).toContain("frame-ancestors 'self'");
  expect(h['content-security-policy']).toContain("object-src 'none'");
  expect(h['x-frame-options']).toBe('SAMEORIGIN');
  expect(h['x-content-type-options']).toBe('nosniff');
  expect(h['referrer-policy']).toBe('strict-origin-when-cross-origin');
  expect(h['permissions-policy']).toContain('camera=()');
});

test('H-1: the viewer cannot query the registries; a submitter can', async ({ page }) => {
  const body = { nrps: ['D31240187'], section: 'internal' };
  await loginAs(page, ACCOUNTS.rektorat);
  expect((await page.request.post('/api/lookup/students', { data: body })).status()).toBe(403);
  expect((await page.request.post('/api/lookup/employees', { data: { ids: ['PG204517'] } })).status()).toBe(403);

  await loginAs(page, ACCOUNTS.uaFti);
  const ok = await page.request.post('/api/lookup/students', { data: body });
  expect(ok.status()).toBe(200);
  const json = (await ok.json()) as { results: Array<{ student: Record<string, unknown> | null }> };
  expect(json.results[0]?.student?.full_name).toBeTruthy();
  expect(json.results[0]?.student).not.toHaveProperty('intake_year'); // minimal fields only
  const tooMany = await page.request.post('/api/lookup/students', {
    data: { nrps: Array.from({ length: 201 }, (_, i) => `A${String(i).padStart(8, '0')}`), section: 'internal' },
  });
  expect(tooMany.status()).toBe(400);
});

test('L-1: cross-site writes to /api are refused', async ({ page }) => {
  await loginAs(page, ACCOUNTS.uaFti);
  const res = await page.request.post('/api/lookup/students', {
    data: { nrps: ['D31240187'], section: 'internal' },
    headers: { Origin: 'https://evil.petra.ac.id' },
  });
  expect(res.status()).toBe(403);
});

test('L-4: /api/files rejects keys outside the storage grammar before any I/O', async ({ page }) => {
  await loginAs(page, ACCOUNTS.uaFbe);
  expect((await page.request.get('/api/files/realisasi-files/..%2F..%2Fetc/passwd')).status()).toBe(404);
  expect(
    (await page.request.get('/api/files/realisasi-transcripts/a0000000-0000-4000-8000-000000000002/mobility_bundle/0b7c1f0e-1d2a-4c3b-9e8f-000000000001.pdf%00')).status(),
  ).toBe(404);
});

test('M-1: an xlsx that inflates past the limit is rejected with an Indonesian message', async ({ page }) => {
  await loginAs(page, ACCOUNTS.uaFti);
  const { deflateRawSync } = await import('node:zlib');
  // Single-entry zip whose entry inflates to 6 MB of 'A' (well over the 5 MB budget).
  const data = Buffer.alloc(6 * 1024 * 1024, 'A');
  const comp = deflateRawSync(data);
  const name = Buffer.from('xl/worksheets/sheet1.xml');
  const loc = Buffer.alloc(30);
  loc.writeUInt32LE(0x04034b50, 0);
  loc.writeUInt16LE(20, 4);
  loc.writeUInt16LE(8, 8);
  loc.writeUInt32LE(comp.length, 18);
  loc.writeUInt32LE(data.length, 22);
  loc.writeUInt16LE(name.length, 26);
  const cen = Buffer.alloc(46);
  cen.writeUInt32LE(0x02014b50, 0);
  cen.writeUInt16LE(8, 10);
  cen.writeUInt32LE(comp.length, 20);
  cen.writeUInt32LE(data.length, 24);
  cen.writeUInt16LE(name.length, 28);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(1, 8);
  eocd.writeUInt16LE(1, 10);
  eocd.writeUInt32LE(cen.length + name.length, 12);
  eocd.writeUInt32LE(loc.length + name.length + comp.length, 16);
  const bomb = Buffer.concat([loc, name, comp, cen, name, eocd]);

  const res = await page.request.post('/api/template/peserta', {
    multipart: { kind: 'students', file: { name: 'bom.xlsx', mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', buffer: bomb } },
  });
  expect(res.status()).toBe(413);
  expect(((await res.json()) as { message: string }).message).toContain('terlalu besar');
});
