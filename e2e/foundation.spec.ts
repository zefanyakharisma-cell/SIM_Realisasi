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
    // Revisi V.1 item 7: units follow their own mobility kegiatan on Verifikasi Mobilitas (read-only)
    await expect(page.getByTestId('nav-mobilitas').first()).toBeVisible();
    await expect(page.getByTestId('nav-pengaturan')).toHaveCount(0);
  });

  test('every KUI account is admin (Revisi V.1): all features unlocked', async ({ page }) => {
    for (const email of [ACCOUNTS.kepalaIo, ACCOUNTS.ioStaff, ACCOUNTS.ioMobility]) {
      await loginAs(page, email);
      for (const id of ['nav-mobilitas', 'nav-laporan', 'nav-pengaturan']) {
        await expect(page.getByTestId(id).first()).toBeVisible();
      }
      await expect(page.getByTestId('nav-kemitraan')).toHaveCount(0);
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

  test('Mode Demo: pop-up tours on /login and on first visit to each page', async ({ page }) => {
    // Walks the open tour to its end with "Berikutnya" / "Selesai".
    const finishTour = async () => {
      for (let i = 0; i < 40 && (await page.getByTestId('tour-card').count()) > 0; i++) await page.getByTestId('tour-next').click();
      await expect(page.getByTestId('tour-card')).toHaveCount(0);
    };
    await page.goto('/login');
    await expect(page.getByTestId('tour-card')).toHaveCount(0);
    await page.getByTestId('demo-mode-toggle').click();
    await expect(page.getByTestId('tour-progress')).toContainText('1 /');
    await page.getByTestId('tour-next').click();
    await expect(page.getByTestId('tour-progress')).toContainText('2 /');
    await page.keyboard.press('ArrowLeft');
    await expect(page.getByTestId('tour-progress')).toContainText('1 /');
    // Skipping marks the login tour seen: a reload doesn't start it again.
    await page.keyboard.press('Escape');
    await expect(page.getByTestId('tour-card')).toHaveCount(0);
    await page.reload();
    await expect(page.getByTestId('demo-mode-toggle')).toBeChecked();
    await page.waitForTimeout(1000);
    await expect(page.getByTestId('tour-card')).toHaveCount(0);

    // After login: the app-frame tour, then the dashboard tour, each spotlighting a real element.
    await page.getByTestId(`login-${ACCOUNTS.kepalaIo}`).click();
    await page.waitForURL(/\/realisasi$/);
    await expect(page.getByTestId('tour-progress')).toContainText('Tur dasar aplikasi');
    await page.getByTestId('tour-next').click();
    await expect(page.getByTestId('tour-title')).toHaveText('Dashboard');
    await expect(page.getByTestId('tour-spotlight')).toBeVisible();
    await finishTour();
    await expect(page.getByTestId('tour-progress')).toContainText('Dashboard');
    await finishTour();

    // Seen tours don't repeat; the Panduan menu replays them.
    await page.reload();
    await page.waitForTimeout(1000);
    await expect(page.getByTestId('tour-card')).toHaveCount(0);
    await page.getByTestId('demo-guide-open').click();
    await page.getByTestId('demo-replay-page').click();
    await expect(page.getByTestId('tour-progress')).toContainText('Dashboard · 1 /');
    await page.getByTestId('tour-skip').click();

    // Another page starts its own tour on first visit.
    await page.getByTestId('nav-laporan').first().click();
    await expect(page.getByTestId('tour-progress')).toContainText('Laporan & Ekspor');
    await page.getByTestId('tour-skip').click();

    await page.getByTestId('demo-guide-open').click();
    await page.getByTestId('demo-mode-off').click();
    await expect(page.getByTestId('demo-guide-open')).toHaveCount(0);
  });
});
