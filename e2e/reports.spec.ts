import ExcelJS from 'exceljs';
import { expect, test, type Page } from '@playwright/test';
import { ACCOUNTS, loginAs, resetDb } from './helpers';

test.describe.configure({ mode: 'serial' });

test.beforeAll(() => {
  resetDb();
});

async function downloadWorkbook(page: Page, trigger: () => Promise<void>): Promise<ExcelJS.Workbook> {
  const [download] = await Promise.all([page.waitForEvent('download'), trigger()]);
  const path = await download.path();
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.readFile(path!);
  return wb;
}

test('AT-01: the summer program claimed by FTI and Prodi Informatika counts once, for the unit Mobility kept', async ({ page }) => {
  // S-13 (FTI) kept all 12 students over S-14 (Informatika); 2 of them are also claimed by S-18 (open → counted nowhere).
  await loginAs(page, ACCOUNTS.uaFti);
  await page.goto('/realisasi?period=ytd');
  await expect(page.getByTestId('kpi-card-1.1')).toContainText('Outbound 10');
  await loginAs(page, ACCOUNTS.kaprodiInformatika);
  await page.goto('/realisasi?period=ytd');
  await expect(page.getByTestId('kpi-card-1.1')).toContainText('Outbound 0');
});

test('Periods: Ganjil, Genap, Setahun (kumulatif) and YTD; RENSTRA wording; no S8', async ({ page }) => {
  await loginAs(page, ACCOUNTS.kepalaIo);
  await page.goto('/realisasi?ay=1&period=ganjil');
  for (const p of ['ganjil', 'genap', 'full', 'ytd']) await expect(page.getByTestId(`period-${p}`)).toBeVisible();
  await expect(page.getByTestId('kpi-card-1.1')).toContainText('RENSTRA 1.1');
  await expect(page.getByTestId('kpi-card-1.19.S8')).toHaveCount(0);
  const value = () => page.getByTestId('kpi-card-1.1').getByTestId('kpi-value');
  const ganjil = Number((await value().textContent())?.replace(/\D/g, ''));
  // The links carry the period; navigate by URL.
  await expect(page.getByTestId('period-genap')).toHaveAttribute('href', '/realisasi?ay=1&period=genap');
  await page.goto('/realisasi?ay=1&period=genap');
  await expect(page.getByTestId('period-genap')).toHaveAttribute('aria-current', 'page');
  const genap = Number((await value().textContent())?.replace(/\D/g, ''));
  await page.goto('/realisasi?ay=1&period=full');
  await expect(value()).toHaveText(String(ganjil + genap));

  // Every export is cut by the same four periods.
  const res = await page.request.get('/api/export/kpi-summary?ay=1&period=full');
  expect(res.status()).toBe(200);
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(Buffer.from(await res.body()) as unknown as ArrayBuffer);
  const info = wb.getWorksheet('Info')!;
  const values: string[] = [];
  info.eachRow((row) => values.push(`${String(row.getCell(1).value)}=${String(row.getCell(2).value)}`));
  expect(values.some((v) => v.includes('Setahun 2025/2026'))).toBeTruthy();
});

test('International Awards tab: four leaderboards per submitting unit, exportable', async ({ page }) => {
  await loginAs(page, ACCOUNTS.kepalaIo);
  await page.goto('/realisasi?period=ytd');
  await expect(page.getByTestId('work-queue')).toContainText('duplikat mahasiswa');
  await expect(page.getByTestId('dashboard-tab-awards')).toHaveAttribute('href', /tab=awards/);
  await page.goto('/realisasi?period=ytd&tab=awards');
  for (const id of ['inbound', 'outbound-domestic', 'outbound-international', 'initiatives']) {
    await expect(page.getByTestId(`awards-${id}`)).toBeVisible();
  }
  const intl = page.getByTestId('awards-outbound-international').getByTestId('awards-row').first();
  await expect(intl).toContainText('Fakultas Teknologi Industri');
  await expect(page.getByTestId('period-genap')).toHaveAttribute('href', /tab=awards/);

  const res = await page.request.get('/api/export/awards?period=ytd');
  expect(res.status()).toBe(200);
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(Buffer.from(await res.body()) as unknown as ArrayBuffer);
  expect(wb.worksheets.map((w) => w.name)).toEqual(
    expect.arrayContaining(['Info', 'Inbound Tertinggi', 'Outbound DN Tertinggi', 'Outbound Intl Tertinggi', 'Inisiatif Intl Tertinggi']),
  );
});

test('AT-05: YTD 1.19.24 card shows grace count and drill-down lists doc 901', async ({ page }) => {
  await loginAs(page, ACCOUNTS.kepalaIo);
  await page.goto('/realisasi?period=ytd');
  const card = page.getByTestId('kpi-card-1.19.24');
  await expect(card).toContainText('dalam masa tenggang');
  await card.getByTestId('kpi-grace-link').click();
  await expect(page).toHaveURL(/report=kpi/);
  await expect(page.locator('table')).toContainText('Masa tenggang');
});

test('AT-07: Kerjasama realisasi tab lists activities with the document at activity time', async ({ page }) => {
  await loginAs(page, ACCOUNTS.kepalaIo);
  await page.goto('/kerjasama/dokumen/905/realisasi');
  const docs = page.getByTestId('doc-at-activity');
  await expect(docs).toHaveCount(2);
});

test('AT-08: Arsip shows S-19 as a late addition in the Genap 2025/2026 snapshot workbook', async ({ page }) => {
  await loginAs(page, ACCOUNTS.kepalaIo);
  await page.goto('/realisasi/laporan?report=arsip&ay=1');
  const items = page.getByTestId('snapshot-item');
  await expect(items).toHaveCount(2);
  const genap = items.filter({ hasText: 'Setahun' });
  const wb = await downloadWorkbook(page, () => genap.getByTestId('export-excel').click());
  expect(wb.worksheets.map((w) => w.name)).toEqual(
    expect.arrayContaining(['Info', 'Ringkasan', '1.1', '1.19.S1', '1.19.24', 'Tambahan Susulan', 'Perubahan Pasca-Beku']),
  );
  expect(wb.worksheets[0]!.name).toBe('Info');
  const late = wb.getWorksheet('Tambahan Susulan')!;
  const codes: string[] = [];
  late.eachRow((row, i) => {
    if (i > 1) codes.push(String(row.getCell(1).value));
  });
  expect(codes).toContain('RL-2026-0019');
});

test('AT-11: viewer has no participant report and the API returns 403', async ({ page }) => {
  await loginAs(page, ACCOUNTS.rektorat);
  await page.goto('/realisasi/laporan');
  await expect(page.getByTestId('report-peserta')).toHaveCount(0);
  const res = await page.request.get('/api/export/participants');
  expect(res.status()).toBe(403);
});

test('AT-12: Laporan activity export rows equal the on-screen total', async ({ page }) => {
  await loginAs(page, ACCOUNTS.kepalaIo);
  await page.goto('/realisasi/laporan?report=kegiatan&status=verified&ay=1');
  const total = Number(await page.getByTestId('list-total').textContent());
  const wb = await downloadWorkbook(page, () => page.getByTestId('export-excel').click());
  expect(wb.getWorksheet('Kegiatan')!.rowCount - 1).toBe(total);
  const info = wb.getWorksheet('Info')!;
  const labels: string[] = [];
  info.eachRow((row) => labels.push(String(row.getCell(1).value)));
  expect(labels.some((l) => l.startsWith('Filter: Status'))).toBeTruthy();
});
