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
    for (const id of ['nav-realisasi', 'nav-kegiatan', 'nav-baru', 'nav-kemitraan', 'nav-mobilitas', 'nav-duplikat', 'nav-kegiatan-diketahui', 'nav-laporan', 'nav-pengaturan', 'nav-dokumen']) {
      await expect(page.getByTestId(id).first()).toBeVisible();
    }
  });

  test('submitter nav (Design §1)', async ({ page }) => {
    await loginAs(page, ACCOUNTS.uaFti);
    await expect(page.getByTestId('nav-baru').first()).toBeVisible();
    for (const id of ['nav-kemitraan', 'nav-mobilitas', 'nav-duplikat', 'nav-kegiatan-diketahui', 'nav-pengaturan']) {
      await expect(page.getByTestId(id)).toHaveCount(0);
    }
  });

  test('io partnership vs mobility nav', async ({ page }) => {
    await loginAs(page, ACCOUNTS.ioPartnership);
    await expect(page.getByTestId('nav-kemitraan').first()).toBeVisible();
    await expect(page.getByTestId('nav-duplikat').first()).toBeVisible();
    await expect(page.getByTestId('nav-mobilitas')).toHaveCount(0);
    await loginAs(page, ACCOUNTS.ioMobility);
    await expect(page.getByTestId('nav-mobilitas').first()).toBeVisible();
    await expect(page.getByTestId('nav-kemitraan')).toHaveCount(0);
    await expect(page.getByTestId('nav-baru')).toHaveCount(0);
  });

  test('viewer nav is read-only', async ({ page }) => {
    await loginAs(page, ACCOUNTS.rektorat);
    await expect(page.getByTestId('nav-laporan').first()).toBeVisible();
    for (const id of ['nav-baru', 'nav-kemitraan', 'nav-mobilitas', 'nav-pengaturan']) {
      await expect(page.getByTestId(id)).toHaveCount(0);
    }
  });

  test('notifications page and switch account', async ({ page }) => {
    await loginAs(page, ACCOUNTS.ioPartnership);
    await page.goto('/realisasi/notifikasi');
    await expect(page.getByRole('heading', { level: 1, name: 'Notifikasi' })).toBeVisible();
    await page.getByTestId('user-menu').click();
    await page.getByTestId('switch-account').click();
    await expect(page).toHaveURL(/\/login$/);
  });
});
