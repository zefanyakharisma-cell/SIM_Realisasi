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

test('AT-01: unit dashboards count the shared summer program once per unit (12)', async ({ page }) => {
  for (const email of [ACCOUNTS.uaFti, ACCOUNTS.kaprodiInformatika]) {
    await loginAs(page, email);
    await page.goto('/realisasi?period=live');
    const card = page.getByTestId('kpi-card-1.1');
    await expect(card).toContainText('Outbound 12');
  }
});

test('AT-05: live 1.19.24 card shows grace count and drill-down lists doc 901', async ({ page }) => {
  await loginAs(page, ACCOUNTS.kepalaIo);
  await page.goto('/realisasi?period=live');
  const card = page.getByTestId('kpi-card-1.19.24');
  await expect(card).toContainText('dalam masa tenggang');
  await card.getByTestId('kpi-grace-link').click();
  await expect(page).toHaveURL(/report=kpi/);
  await expect(page.locator('table')).toContainText('Masa tenggang');
});

test('AT-09: S8 card shows 2 unreported international activities', async ({ page }) => {
  await loginAs(page, ACCOUNTS.kepalaIo);
  await page.goto('/realisasi?period=live');
  await expect(page.getByTestId('kpi-s8-unmatched')).toContainText('2 kegiatan belum dilaporkan');
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
    expect.arrayContaining(['Info', 'Ringkasan', '1.1', '1.19.S1', '1.19.24', '1.19.S8', 'Tambahan Susulan', 'Perubahan Pasca-Beku']),
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
