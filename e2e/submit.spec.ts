import { expect, test, type Page } from '@playwright/test';
import { ACCOUNTS, loginAs, resetDb } from './helpers';

/**
 * WP-SUBMIT journeys on the single-page Kegiatan Baru form (Revisi V.1): a mobility kegiatan (participants,
 * one PDF bundle, AT-10 row-level block → Mobility queue) and a non-mobility kegiatan (verified on submit),
 * plus a unit revision of a mobility kegiatan (S-16).
 */

const PDF = Buffer.from('%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n');

async function uploadPdf(page: Page, dropTestId: string, name: string) {
  const chooser = page.waitForEvent('filechooser');
  await page.getByTestId(dropTestId).getByRole('button', { name: /PDF|versi baru/i }).click();
  await (await chooser).setFiles({ name, mimeType: 'application/pdf', buffer: PDF });
}

async function fillDetail(page: Page, o: { name: string; agenda: string; direction: 'inbound' | 'outbound'; country: string }) {
  await page.getByLabel('Nama kegiatan *').fill(o.name);
  await page.getByLabel('Jenis kegiatan *').selectOption({ label: o.agenda });
  await page.getByLabel('Inbound / Outbound *').selectOption(o.direction);
  await page.getByLabel('Tanggal mulai *').fill('2026-09-01');
  await page.getByLabel('Tanggal selesai *').fill('2026-09-05');
  await expect(page.getByTestId('derived-period')).toContainText('2026/2027');
  await page.getByLabel('Tempat *').fill('Kampus Mitra');
  await page.getByLabel('Negara *').selectOption(o.country);
  await page.getByLabel('Deskripsi *').fill('Kegiatan uji end-to-end.');
  await expect(page.getByLabel('Kota *')).toHaveCount(0);
  await expect(page.getByLabel(/Sumber dana/)).toHaveCount(0);

  await expect(page.locator('#f-document_id-hint')).toContainText('berlaku pada tanggal kegiatan');
  await page.locator('#f-document_id').click();
  await page.locator('[cmdk-item]').first().click();
  await expect(page.getByTestId('agreement-card')).toHaveCount(1);
}

test.describe.configure({ mode: 'serial' });

test.beforeAll(() => {
  if (process.env.E2E_SKIP_DB_RESET !== '1') resetDb();
});

test('ua-fti: one-page mobility kegiatan, AT-10 unknown NRP blocks, PDF bundle, submit → Mobility queue', async ({ page }) => {
  await loginAs(page, ACCOUNTS.uaFti);
  await page.goto('/realisasi/kegiatan/baru');
  await expect(page.getByText('Pratinjau: bagian ini dapat diisi setelah Detail disimpan sebagai draf.').first()).toBeVisible();
  await expect(page.getByTestId('wizard-submit')).toBeDisabled();

  await fillDetail(page, { name: 'Student Exchange Uji E2E', agenda: 'Student Exchange', direction: 'outbound', country: 'JP' });
  await expect(page.getByTestId('type-helper')).toContainText('Kegiatan mobilitas');
  await expect(page.getByTestId('sks-field')).toBeVisible();
  await expect(page.getByText('Unit Lain yang Terlibat', { exact: true })).toBeVisible();

  await page.getByTestId('wizard-save-draft').click();
  await page.waitForURL(/\/realisasi\/kegiatan\/baru\?draft=[0-9a-f-]{36}$/);

  // Same page: Peserta unlocks in place. AT-10: unknown NRP → red row, blocking.
  await page.getByLabel('Tempel NRP (satu per baris)').fill('D31240187\nZ99999999');
  await page.getByTestId('check-nrp').click();
  await expect(page.locator('[data-testid=student-row][data-status=not_found]')).toContainText('Z99999999');
  await expect(page.getByTestId('participants-blocking')).toBeVisible();
  await page.getByRole('button', { name: 'Hapus Z99999999' }).click();
  await expect(page.getByTestId('participants-blocking')).toHaveCount(0);
  await expect(page.getByTestId('draft-version')).toBeVisible();

  await expect(page.getByTestId('mobility-bundle-notice')).toContainText('satu file PDF');
  await uploadPdf(page, 'drop-ia', 'IA.pdf');
  await expect(page.getByTestId('current-ia')).toContainText('IA.pdf');
  await uploadPdf(page, 'drop-ir', 'IR.pdf');
  await expect(page.getByTestId('current-ir')).toContainText('IR.pdf');
  await expect(page.getByTestId('wizard-submit')).toBeDisabled(); // bundle still missing
  await uploadPdf(page, 'drop-mobility_bundle', 'Transkrip-Poster-Dokumentasi.pdf');
  await expect(page.getByTestId('current-mobility_bundle')).toContainText('Transkrip-Poster-Dokumentasi.pdf');

  await expect(page.getByTestId('wizard-submit')).toBeEnabled();
  await page.getByTestId('wizard-submit').click();
  await page.waitForURL(/\/realisasi\/kegiatan\/[0-9a-f-]{36}$/);
  await expect(page.getByTestId('status-badge').first()).toContainText('Dalam Verifikasi');
  await page.getByRole('link', { name: 'Berkas' }).click();
  await expect(page.getByTestId('file-mobility_bundle')).toContainText('Transkrip-Poster-Dokumentasi.pdf');
});

test('ua-fti: non-mobility kegiatan needs no participants and is verified on submit', async ({ page }) => {
  await loginAs(page, ACCOUNTS.uaFti);
  await page.goto('/realisasi/kegiatan/baru');
  await fillDetail(page, {
    name: 'Seminar Internasional Uji E2E',
    agenda: 'Joint Projects (Konferensi/Seminar/Workshop/Lomba/pameran)',
    direction: 'inbound',
    country: 'JP',
  });
  await expect(page.getByTestId('type-helper')).toContainText('Bukan kegiatan mobilitas');
  await expect(page.getByTestId('sks-field')).toHaveCount(0);
  await page.getByTestId('wizard-save-draft').click();
  await page.waitForURL(/draft=/);

  await expect(page.getByTestId('participants-not-needed')).toBeVisible();
  await expect(page.getByTestId('drop-mobility_bundle')).toHaveCount(0);
  await uploadPdf(page, 'drop-ia', 'IA.pdf');
  await expect(page.getByTestId('current-ia')).toContainText('IA.pdf');
  await uploadPdf(page, 'drop-ir', 'IR.pdf');
  await expect(page.getByTestId('current-ir')).toContainText('IR.pdf');

  await page.getByTestId('wizard-submit').click();
  await page.waitForURL(/\/realisasi\/kegiatan\/[0-9a-f-]{36}$/);
  await expect(page.getByTestId('status-badge').first()).toContainText('Terverifikasi');
});

test('S-16: unit fixes a mobility revision and resubmits → back in the Mobility queue', async ({ page }) => {
  const id = 'a0000000-0000-4000-8000-000000000016';
  await loginAs(page, ACCOUNTS.uaFti);
  await page.goto(`/realisasi/kegiatan/${id}`);
  await expect(page.getByTestId('revision-banner')).toContainText('Mobilitas');
  await page.goto(`/realisasi/kegiatan/${id}/revisi`);

  await page.getByLabel('Tempel NRP (satu per baris)').fill('D31240187');
  await page.getByTestId('check-nrp').click();
  await expect(page.getByTestId('draft-version')).toBeVisible();

  await expect(page.getByTestId('action-resubmit')).toBeEnabled();
  await page.getByTestId('action-resubmit').click();
  await page.waitForURL(new RegExp(`/realisasi/kegiatan/${id}$`));
  await expect(page.getByTestId('status-badge').first()).toContainText('Dalam Verifikasi');
});
