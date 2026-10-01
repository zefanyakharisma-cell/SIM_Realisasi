import { expect, test, type Page } from '@playwright/test';
import { ACCOUNTS, loginAs, resetDb } from './helpers';

/**
 * WP-SUBMIT journeys: draft → submit happy path incl. AT-10 row-level block, and AT-04
 * (Partnership revision changing Jenis resets Mobility to pending).
 */

const PDF = Buffer.from('%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n');

async function uploadPdf(page: Page, dropTestId: string, name: string) {
  const chooser = page.waitForEvent('filechooser');
  await page.getByTestId(dropTestId).getByRole('button', { name: /PDF|versi baru/i }).click();
  await (await chooser).setFiles({ name, mimeType: 'application/pdf', buffer: PDF });
}

test.describe.configure({ mode: 'serial' });

test.beforeAll(() => {
  if (!process.env.E2E_SKIP_RESET) resetDb();
});

test('ua-fti: create draft, AT-10 unknown NRP blocks, upload IA/IR, submit', async ({ page }) => {
  await loginAs(page, ACCOUNTS.uaFti);
  await page.goto('/realisasi/kegiatan/baru');

  await page.getByLabel('Nama kegiatan *').fill('Student Exchange Uji E2E');
  await page.getByLabel('Jenis kegiatan *').selectOption({ label: 'Student Outbound Mobility' });
  await expect(page.getByTestId('type-helper')).toContainText('mobilitas outbound');
  await page.getByLabel('Tanggal mulai *').fill('2026-09-01');
  await page.getByLabel('Tanggal selesai *').fill('2026-09-05');
  await expect(page.getByTestId('derived-period')).toContainText('2026/2027');
  await page.getByLabel('Tempat *').fill('Kampus Mitra');
  await page.getByLabel('Kota *').fill('Osaka');
  await page.getByLabel('Negara *').selectOption('JP');
  await page.getByLabel('Deskripsi *').fill('Pertukaran mahasiswa satu minggu.');

  await page.locator('#f-document_ids').click();
  await page.getByRole('option').first().click();
  await page.keyboard.press('Escape');
  await expect(page.getByTestId('agreement-card')).toHaveCount(1);

  await page.getByTestId('wizard-next').click();
  await page.waitForURL(/step=2/);

  // AT-10: unknown NRP → red row, cannot continue
  await page.getByLabel('Tempel NRP (satu per baris)').fill('D31240187\nZ99999999');
  await page.getByTestId('check-nrp').click();
  await expect(page.locator('[data-testid=student-row][data-status=not_found]')).toContainText('Z99999999');
  await expect(page.getByTestId('participants-blocking')).toBeVisible();
  await expect(page.getByTestId('wizard-next')).toBeDisabled();

  await page.getByRole('button', { name: 'Hapus Z99999999' }).click();
  await expect(page.getByTestId('participants-blocking')).toHaveCount(0);
  await expect(page.getByTestId('draft-version')).toBeVisible();
  await page.getByTestId('wizard-next').click();
  await page.waitForURL(/step=3/);

  await uploadPdf(page, 'drop-ia', 'IA.pdf');
  await expect(page.getByTestId('current-ia')).toContainText('IA.pdf');
  await uploadPdf(page, 'drop-ir', 'IR.pdf');
  await expect(page.getByTestId('current-ir')).toContainText('IR.pdf');
  await page.getByTestId('wizard-next').click();
  await page.waitForURL(/step=4/);

  await expect(page.getByTestId('wizard-submit')).toBeEnabled();
  await page.getByTestId('wizard-submit').click();
  await page.waitForURL(/\/realisasi\/kegiatan\/[0-9a-f-]{36}$/);
  await expect(page.getByTestId('status-badge').first()).toContainText('Dalam Verifikasi');
});

test('AT-04: ua-fbe changes Jenis on S-17 revision → Mobility pending', async ({ page }) => {
  const id = 'a0000000-0000-4000-8000-000000000017';
  await loginAs(page, ACCOUNTS.uaFbe);
  await page.goto(`/realisasi/kegiatan/${id}`);
  await expect(page.getByTestId('revision-banner')).toBeVisible();
  await page.goto(`/realisasi/kegiatan/${id}/revisi`);

  await page.getByLabel('Jenis kegiatan *').selectOption({ label: 'Student Outbound Mobility' });
  await page.getByTestId('save-detail').click();
  await expect(page.getByLabel('Tempel NRP (satu per baris)')).toBeVisible();

  await page.getByLabel('Tempel NRP (satu per baris)').fill('D31240187');
  await page.getByTestId('check-nrp').click();
  await expect(page.getByTestId('draft-version')).toBeVisible();

  await uploadPdf(page, 'drop-ia', 'IA-baru.pdf');
  await expect(page.getByTestId('current-ia')).toContainText('IA-baru.pdf');

  await expect(page.getByTestId('action-resubmit')).toBeEnabled();
  await page.getByTestId('action-resubmit').click();
  await page.waitForURL(new RegExp(`/realisasi/kegiatan/${id}$`));
  await expect(page.getByTestId('status-badge').first()).toContainText('Dalam Verifikasi');
  await expect(page.getByText('Mobilitas').first()).toBeVisible();
});
