import { expect, test } from '@playwright/test';
import { ACCOUNTS, loginAs } from './helpers';

test.describe('foundation: login, shell, navigation per role', () => {
  test('unauthenticated users are redirected to /login; API returns 401', async ({ page, request }) => {
    await page.context().clearCookies();
    await page.goto('/realisasi');
    await expect(page).toHaveURL(/\/login$/);
    const res = await request.get('/api/export/activities', { headers: { cookie: '' } });
    expect(res.status()).toBe(401);
    expect(await res.json()).toMatchObject({ code: 'AUTH_REQUIRED' });
  });

  test('login page lists the 8 demo accounts in contract order', async ({ page }) => {
    await page.goto('/login');
    const buttons = page.locator('[data-testid^="login-"]');
    await expect(buttons).toHaveCount(8);
    const ids = await buttons.evaluateAll((els) => els.map((e) => e.getAttribute('data-testid')));
    expect(ids).toEqual(Object.values(ACCOUNTS).map((e) => `login-${e}`));
  });

  test('io_admin sees every nav item', async ({ page }) => {
    await loginAs(page, ACCOUNTS.kepalaIo);
    for (const id of ['nav-realisasi', 'nav-kegiatan', 'nav-baru', 'nav-mobilitas', 'nav-laporan', 'nav-pengaturan', 'nav-dokumen']) {
      await expect(page.getByTestId(id).first()).toBeVisible();
    }
    // Revisi V.1: no Verifikasi Kemitraan, no separate Duplikat page, no Kegiatan Diketahui.
    for (const id of ['nav-kemitraan', 'nav-duplikat', 'nav-kegiatan-diketahui']) {
      await expect(page.getByTestId(id)).toHaveCount(0);
    }
  });

  test('submitter nav (Design §1)', async ({ page }) => {
    await loginAs(page, ACCOUNTS.uaFti);
    await expect(page.getByTestId('nav-baru').first()).toBeVisible();
    for (const id of ['nav-mobilitas', 'nav-pengaturan']) {
      await expect(page.getByTestId(id)).toHaveCount(0);
    }
  });

  test('IO staff (Mobility team) nav', async ({ page }) => {
    for (const email of [ACCOUNTS.ioStaff, ACCOUNTS.ioMobility]) {
      await loginAs(page, email);
      await expect(page.getByTestId('nav-mobilitas').first()).toBeVisible();
      await expect(page.getByTestId('nav-kemitraan')).toHaveCount(0);
      await expect(page.getByTestId('nav-baru')).toHaveCount(0);
      await expect(page.getByTestId('nav-pengaturan')).toHaveCount(0);
    }
  });

  test('viewer nav is read-only', async ({ page }) => {
    await loginAs(page, ACCOUNTS.rektorat);
    await expect(page.getByTestId('nav-laporan').first()).toBeVisible();
    for (const id of ['nav-baru', 'nav-mobilitas', 'nav-pengaturan']) {
      await expect(page.getByTestId(id)).toHaveCount(0);
    }
  });

  test('notifications page and switch account', async ({ page }) => {
    await loginAs(page, ACCOUNTS.ioStaff);
    await page.goto('/realisasi/notifikasi');
    await expect(page.getByRole('heading', { level: 1, name: 'Notifikasi' })).toBeVisible();
    await page.getByTestId('user-menu').click();
    await page.getByTestId('switch-account').click();
    await expect(page).toHaveURL(/\/login$/);
  });

  test('Mode Demo: step-by-step guide on /login, Panduan sheet in the app', async ({ page }) => {
    await page.goto('/login');
    await expect(page.getByTestId('demo-guide')).toHaveCount(0);
    await page.getByTestId('demo-mode-toggle').click();
    await expect(page.getByTestId('guide-progress')).toHaveText(/Langkah 1 dari \d+/);
    await page.getByTestId('guide-next').click();
    await expect(page.getByTestId('guide-progress')).toHaveText(/Langkah 2 dari/);
    // The choice and the current step survive a reload (per-browser preference).
    await page.reload();
    await expect(page.getByTestId('guide-progress')).toHaveText(/Langkah 2 dari/);
    // Role chapters offer the matching demo accounts; sign in from the guide.
    await page.getByTestId('guide-chapter-lapor-kegiatan').click();
    await page.getByTestId('guide-accounts').getByRole('button', { name: /Fakultas Teknologi Industri/ }).click();
    await page.waitForURL(/\/realisasi$/);
    await page.getByTestId('demo-guide-open').click();
    await expect(page.getByTestId('page-guide')).toContainText('Dashboard');
    await page.getByTestId('demo-mode-toggle-app').click();
    await expect(page.getByTestId('demo-guide-open')).toHaveCount(0);
  });
});
