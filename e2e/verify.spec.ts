import { expect, test } from '@playwright/test';
import { ACCOUNTS, loginAs } from './helpers';

/**
 * WP-VERIFY journeys: queues (SLA order, approve / revise / reject), Mobilitas diff + row notes,
 * Kegiatan list filters vs export link (AT-12 precondition), duplicates, known activities.
 * Seed facts per CONTRACTS §5.3. Expects a freshly reset DB (e2e/global-setup.ts). It does not
 * reset itself: dropping/recreating views under a running server invalidates postgres.js' cached
 * prepared statements ("cached plan must not change result type").
 */
test.describe.configure({ mode: 'serial' });

test('Kemitraan queue is SLA-sorted (red first) and rows expand with Enter', async ({ page }) => {
  await loginAs(page, ACCOUNTS.ioPartnership);
  await page.goto('/realisasi/verifikasi/kemitraan');
  const rows = page.getByTestId('queue-row');
  await expect(rows.first()).toHaveAttribute('data-code', 'RL-2026-0027'); // S-27, 7 business days (red)
  const total = Number(await page.getByTestId('list-total').textContent());
  await expect(rows).toHaveCount(total);

  const toggle = rows.first().getByTestId('queue-toggle');
  await toggle.focus();
  await page.keyboard.press('Enter');
  await expect(toggle).toHaveAttribute('aria-expanded', 'true');
  await expect(page.getByTestId('queue-panel').first()).toBeVisible();
  await expect(page.getByRole('tab', { name: /IA · Implementation Arrangement/ }).first()).toBeVisible();
});

test('Partnership revision requires a note, then leaves the queue (S-25)', async ({ page }) => {
  await loginAs(page, ACCOUNTS.ioPartnership);
  await page.goto('/realisasi/verifikasi/kemitraan');
  const row = page.locator('[data-testid=queue-row][data-code="RL-2026-0025"]');
  await row.getByTestId('queue-toggle').click();
  const panel = page.locator('#queue-panel-a0000000-0000-4000-8000-000000000025');
  await panel.getByTestId('action-request-revision').click();
  const dialog = page.getByRole('dialog');
  await dialog.getByTestId('action-confirm').click();
  await expect(dialog.getByText('Catatan revisi wajib diisi.')).toBeVisible();
  await dialog.getByLabel(/Catatan revisi/).fill('Mohon unggah IR yang sudah ditandatangani.');
  await dialog.getByTestId('action-confirm').click();
  await expect(dialog).toBeHidden();
  await expect(row).toHaveCount(0);
});

test('Partnership reject needs reason + note (S-26)', async ({ page }) => {
  await loginAs(page, ACCOUNTS.kepalaIo);
  await page.goto('/realisasi/verifikasi/kemitraan');
  await page.locator('[data-testid=queue-row][data-code="RL-2026-0026"]').getByTestId('queue-toggle').click();
  const panel = page.locator('#queue-panel-a0000000-0000-4000-8000-000000000026');
  await panel.getByTestId('action-reject').click();
  const dialog = page.getByRole('dialog');
  await dialog.getByTestId('action-confirm').click();
  await expect(dialog.getByText('Pilih alasan penolakan.')).toBeVisible();
  await dialog.getByTestId('reject-reason').selectOption('not_partnership');
  await dialog.getByLabel(/Catatan penolakan/).fill('Bukan kegiatan kerja sama.');
  await dialog.getByTestId('action-confirm').click();
  await expect(dialog).toBeHidden();
  await page.goto('/realisasi/kegiatan?status=rejected');
  await expect(page.getByRole('link', { name: 'RL-2026-0026' })).toBeVisible();
});

test('Partnership approve (S-27) moves it out of the queue', async ({ page }) => {
  await loginAs(page, ACCOUNTS.ioPartnership);
  await page.goto('/realisasi/verifikasi/kemitraan');
  await page.locator('[data-testid=queue-row][data-code="RL-2026-0027"]').getByTestId('queue-toggle').click();
  await page.locator('#queue-panel-a0000000-0000-4000-8000-000000000027').getByTestId('action-approve').click();
  await page.getByRole('dialog').getByTestId('action-confirm').click();
  await expect(page.locator('[data-testid=queue-row][data-code="RL-2026-0027"]')).toHaveCount(0);
});

test('Mobilitas: revision with a per-row note (S-29), approve (S-28)', async ({ page }) => {
  await loginAs(page, ACCOUNTS.ioMobility);
  await page.goto('/realisasi/verifikasi/mobilitas');
  await expect(page.getByTestId('queue-row').first()).toHaveAttribute('data-code', 'RL-2026-0029'); // red

  await page.locator('[data-testid=queue-row][data-code="RL-2026-0029"]').getByTestId('queue-toggle').click();
  const p29 = page.locator('#queue-panel-a0000000-0000-4000-8000-000000000029');
  await expect(p29.getByText(/Peserta v\d/)).toBeVisible();
  await p29.getByTestId('action-request-revision').click();
  const dialog = page.getByRole('dialog');
  await dialog.getByLabel(/Catatan revisi/).fill('Transkrip salah satu peserta tidak terbaca.');
  await dialog.locator('tbody input').first().fill('Unggah ulang transkrip.');
  await dialog.getByTestId('action-confirm').click();
  await expect(dialog).toBeHidden();
  await expect(page.locator('[data-testid=queue-row][data-code="RL-2026-0029"]')).toHaveCount(0);

  await page.locator('[data-testid=queue-row][data-code="RL-2026-0028"]').getByTestId('queue-toggle').click();
  await page.locator('#queue-panel-a0000000-0000-4000-8000-000000000028').getByTestId('action-approve').click();
  await page.getByRole('dialog').getByTestId('action-confirm').click();
  await expect(page.locator('[data-testid=queue-row][data-code="RL-2026-0028"]')).toHaveCount(0);
});

test('Kegiatan list: URL filters, list-total and export link share the same params (AT-12)', async ({ page }) => {
  await loginAs(page, ACCOUNTS.kepalaIo);
  await page.goto('/realisasi/kegiatan?status=verified&ay=1');
  const total = Number(await page.getByTestId('list-total').textContent());
  expect(total).toBeGreaterThan(0);
  await expect(page.getByTestId('activity-row')).toHaveCount(total);
  await expect(page.getByTestId('export-excel')).toHaveAttribute('href', '/api/export/activities?status=verified&ay=1');

  await page.getByTestId('preset-late').click();
  await expect(page).toHaveURL(/preset=late/);
  await expect(page.getByTestId('export-excel')).toHaveAttribute('href', /preset=late/);
});

test('Viewer cannot open verification pages', async ({ page }) => {
  await loginAs(page, ACCOUNTS.rektorat);
  for (const path of ['/realisasi/verifikasi/kemitraan', '/realisasi/verifikasi/mobilitas', '/realisasi/verifikasi/duplikat', '/realisasi/kegiatan-diketahui']) {
    await page.goto(path);
    await expect(page.getByTestId('forbidden')).toBeVisible();
  }
});

test('Duplikat: linked S-13/S-14 card is listed', async ({ page }) => {
  await loginAs(page, ACCOUNTS.ioPartnership);
  await page.goto('/realisasi/verifikasi/duplikat?status=linked');
  const card = page.getByTestId('dup-card').filter({ hasText: 'RL-2026-0013' });
  await expect(card).toContainText('RL-2026-0014');
  await expect(card.getByTestId('dup-unlink')).toHaveCount(0); // io_staff cannot unlink (R-34)
});

test('Kegiatan Diketahui: unmatched filter, nudge disables the button', async ({ page }) => {
  await loginAs(page, ACCOUNTS.ioPartnership);
  await page.goto('/realisasi/kegiatan-diketahui?status=unmatched');
  await expect(page.getByTestId('list-total')).toHaveText('2');
  const row = page.getByTestId('known-row').first();
  const nudge = row.getByTestId('known-nudge');
  await expect(nudge).toBeEnabled();
  await nudge.click();
  await expect(row.getByTestId('known-nudge')).toBeDisabled();
  await expect(row.getByText(/Diingatkan/)).toBeVisible();
});

test('Kegiatan Diketahui: record a new entry and match a suggestion', async ({ page }) => {
  await loginAs(page, ACCOUNTS.ioPartnership);
  await page.goto('/realisasi/kegiatan-diketahui');
  await page.getByTestId('known-create').click();
  const form = page.getByTestId('known-form');
  await form.getByTestId('known-submit').click();
  await expect(form.getByRole('alert')).toBeVisible();
  // Name/date close to S-22 (2026-08-17) so known_match_suggestions returns it.
  await form.getByLabel(/Judul kegiatan/).fill('Pengabdian Masyarakat Literasi Keuangan');
  await form.getByLabel(/Tanggal kegiatan/).fill('2026-08-18');
  await form.getByLabel(/Sumber informasi/).selectOption('news');
  await form.getByTestId('known-submit').click();
  await expect(form).toBeHidden();
  const row = page.getByTestId('known-row').filter({ hasText: 'Pengabdian Masyarakat Literasi Keuangan' });
  await expect(row.getByTestId('known-suggestion').first()).toContainText('RL-2026-0022');
  await row.getByTestId('known-match').first().click();
  await page.getByRole('dialog').getByTestId('action-confirm').click();
  await expect(row.getByText('Cocok', { exact: true })).toBeVisible();
  await expect(row.getByRole('link', { name: /RL-2026-0022/ })).toBeVisible();
});

test('Duplikat: link the open S-28/S-30 candidate; Kepala IO can unlink it again', async ({ page }) => {
  await loginAs(page, ACCOUNTS.ioPartnership);
  await page.goto('/realisasi/verifikasi/duplikat');
  const card = page.getByTestId('dup-card').filter({ hasText: 'RL-2026-0030' });
  await expect(card).toContainText('RL-2026-0028');
  await card.getByTestId('dup-link').click();
  await page.getByRole('dialog').getByTestId('action-confirm').click();
  await expect(card).toHaveCount(0);

  await loginAs(page, ACCOUNTS.kepalaIo);
  await page.goto('/realisasi/verifikasi/duplikat?status=linked');
  const linked = page.getByTestId('dup-card').filter({ hasText: 'RL-2026-0030' });
  await linked.getByTestId('dup-unlink').click();
  const dialog = page.getByRole('dialog');
  await dialog.getByTestId('action-confirm').click();
  await expect(dialog.getByText('Catatan wajib diisi.')).toBeVisible();
  await dialog.getByLabel(/Alasan/).fill('Ternyata dua kegiatan berbeda.');
  await dialog.getByTestId('action-confirm').click();
  await expect(dialog).toBeHidden();
  await page.goto('/realisasi/verifikasi/duplikat?status=dismissed');
  await expect(page.getByTestId('dup-card').filter({ hasText: 'RL-2026-0030' })).toBeVisible();
});
