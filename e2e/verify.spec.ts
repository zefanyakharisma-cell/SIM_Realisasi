import { expect, test, type Page } from '@playwright/test';
import { ACCOUNTS, loginAs } from './helpers';

/**
 * WP-VERIFY journeys after Revisi V.1: one verification track (Mobilitas, oldest first), revision with a
 * general note only, duplicate students (rule 2.1) decided inside Verifikasi Mobilitas, and the Kegiatan
 * list filters vs export link (AT-12 precondition). Seed facts per supabase/seed/03_activities.sql.
 * Expects a freshly reset DB (e2e/global-setup.ts). It does not reset itself: dropping/recreating views
 * under a running server invalidates postgres.js' cached prepared statements.
 */
test.describe.configure({ mode: 'serial' });

const S18 = 'a0000000-0000-4000-8000-000000000018';

/** Expands a queue row unless it already is (a queue with a single row starts expanded). */
async function openRow(page: Page, code: string) {
  const toggle = page.locator(`[data-testid=queue-row][data-code="${code}"]`).getByTestId('queue-toggle');
  if ((await toggle.getAttribute('aria-expanded')) !== 'true') await toggle.click();
  await expect(toggle).toHaveAttribute('aria-expanded', 'true');
}

test('Mobilitas queue lists the oldest submission first and rows expand with Enter', async ({ page }) => {
  await loginAs(page, ACCOUNTS.ioMobility);
  await page.goto('/realisasi/verifikasi/mobilitas');
  const rows = page.getByTestId('queue-row');
  await expect(rows.first()).toHaveAttribute('data-code', 'RL-2026-0029'); // waiting 10 days
  const total = Number(await page.getByTestId('list-total').textContent());
  await expect(rows).toHaveCount(total);
  await expect(page.getByText(/SLA/)).toHaveCount(0);

  const toggle = rows.first().getByTestId('queue-toggle');
  // Production pages render before hydration; a key press before then is lost.
  await page.waitForLoadState('networkidle');
  await toggle.focus();
  await page.keyboard.press('Enter');
  await expect(toggle).toHaveAttribute('aria-expanded', 'true');
  await expect(page.getByTestId('queue-panel').first()).toBeVisible();
  await expect(page.getByTestId('queue-panel').first().getByText(/PDF transkrip, poster/)).toBeVisible();
});

test('Mobilitas revision needs a note and has no per-row notes (S-29); approve S-30', async ({ page }) => {
  await loginAs(page, ACCOUNTS.ioStaff);
  await page.goto('/realisasi/verifikasi/mobilitas');
  await page.waitForLoadState('networkidle');
  await openRow(page, 'RL-2026-0029');
  const p29 = page.locator('#queue-panel-a0000000-0000-4000-8000-000000000029');
  await expect(p29.getByText(/Peserta v\d/)).toBeVisible();
  await p29.getByTestId('action-request-revision').click();
  const dialog = page.getByRole('dialog');
  await expect(dialog.getByText(/Catatan per baris/)).toHaveCount(0);
  await expect(dialog.locator('tbody input')).toHaveCount(0);
  await dialog.getByTestId('action-confirm').click();
  await expect(dialog.getByText('Catatan revisi wajib diisi.')).toBeVisible();
  await dialog.getByLabel(/Catatan revisi/).fill('Transkrip salah satu peserta tidak terbaca di PDF.');
  await dialog.getByTestId('action-confirm').click();
  await expect(dialog).toBeHidden();
  await expect(page.locator('[data-testid=queue-row][data-code="RL-2026-0029"]')).toHaveCount(0);

  await openRow(page, 'RL-2026-0030');
  await page.locator('#queue-panel-a0000000-0000-4000-8000-000000000030').getByTestId('action-approve').click();
  await page.getByRole('dialog').getByTestId('action-confirm').click();
  await expect(page.locator('[data-testid=queue-row][data-code="RL-2026-0030"]')).toHaveCount(0);
});

test('Rule 2.1: S-18 cannot be approved while its duplicate students are open; Mobility picks a kegiatan', async ({ page }) => {
  await loginAs(page, ACCOUNTS.ioMobility);
  await page.goto('/realisasi/verifikasi/mobilitas');
  await page.waitForLoadState('networkidle');
  const section = page.locator('#duplikat');
  await expect(section.getByTestId('conflicts-total')).toContainText('2 menunggu keputusan');
  await expect(section.getByTestId('conflict-row')).toHaveCount(2);

  await openRow(page, 'RL-2026-0018');
  const panel = page.locator(`#queue-panel-${S18}`);
  await expect(panel.getByTestId('action-approve')).toBeDisabled();
  await expect(panel.getByTestId('approve-blocked-conflicts')).toBeVisible();

  // Keep both students on S-13 (FTI): each decision is one row.
  for (let i = 0; i < 2; i++) {
    const row = section.getByTestId('conflict-row').first();
    const fti = row.getByTestId('conflict-side').filter({ hasText: 'RL-2026-0013' });
    await fti.getByTestId('conflict-keep').click();
    const dialog = page.getByRole('dialog');
    await dialog.getByLabel('Catatan').fill('Transkrip diterbitkan FTI.');
    await dialog.getByTestId('action-confirm').click();
    await expect(dialog).toBeHidden();
  }
  await expect(section.getByTestId('conflicts-total')).toContainText('0 menunggu keputusan');

  await openRow(page, 'RL-2026-0018');
  await expect(panel.getByTestId('action-approve')).toBeEnabled();
  await panel.getByTestId('action-approve').click();
  await page.getByRole('dialog').getByTestId('action-confirm').click();
  await expect(page.locator('[data-testid=queue-row][data-code="RL-2026-0018"]')).toHaveCount(0);

  // The decision is visible on the activity page as well.
  await page.goto(`/realisasi/kegiatan/${S18}`);
  await expect(page.locator('#duplikat').getByText('Tidak dihitung').first()).toBeVisible();
});

test('Kegiatan list: URL filters, list-total and export link share the same params (AT-12)', async ({ page }) => {
  await loginAs(page, ACCOUNTS.kepalaIo);
  await page.goto('/realisasi/kegiatan?status=verified&ay=1');
  const total = Number(await page.getByTestId('list-total').textContent());
  expect(total).toBeGreaterThan(0);
  await expect(page.getByTestId('activity-row')).toHaveCount(total);
  await expect(page.getByTestId('export-excel')).toHaveAttribute('href', '/api/export/activities?status=verified&ay=1');

  await page.locator('#flt-direction').selectOption('inbound');
  await expect(page).toHaveURL(/direction=inbound/);
  await expect(page.getByTestId('export-excel')).toHaveAttribute('href', /direction=inbound/);

  await page.getByTestId('preset-late').click();
  await expect(page).toHaveURL(/preset=late/);
  await expect(page.getByTestId('export-excel')).toHaveAttribute('href', /preset=late/);
});

test('Viewer cannot open the verification page; removed pages are gone', async ({ page }) => {
  await loginAs(page, ACCOUNTS.rektorat);
  await page.goto('/realisasi/verifikasi/mobilitas');
  await expect(page.getByTestId('forbidden')).toBeVisible();
  await loginAs(page, ACCOUNTS.kepalaIo);
  for (const path of ['/realisasi/verifikasi/kemitraan', '/realisasi/verifikasi/duplikat', '/realisasi/kegiatan-diketahui']) {
    const res = await page.goto(path);
    expect(res?.status()).toBe(404);
  }
});

test('Pengaturan: Jenis Kegiatan comes from SIM Kerjasama agendas with a mobility category', async ({ page }) => {
  await loginAs(page, ACCOUNTS.kepalaIo);
  await page.goto('/realisasi/pengaturan?tab=jenis');
  const rules = page.getByTestId('agenda-rules');
  await expect(rules.getByTestId('agenda-rule-row').filter({ hasText: 'Student Exchange' }).first()).toBeVisible();
  await expect(rules.getByLabel('Student Exchange', { exact: true })).toHaveValue('student_exchange');
  await expect(page.getByTestId('settings-tab-libur')).toHaveCount(0);
});
