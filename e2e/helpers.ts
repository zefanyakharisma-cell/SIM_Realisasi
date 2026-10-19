import { execFileSync } from 'node:child_process';
import { expect, type Page } from '@playwright/test';

/** Seed accounts (CONTRACTS §5.3). */
export const ACCOUNTS = {
  kepalaIo: 'kepala.io@demo.petra.ac.id',
  ioStaff: 'io.partnership@demo.petra.ac.id',
  ioMobility: 'io.mobility@demo.petra.ac.id',
  uaFti: 'ua-fti@demo.petra.ac.id',
  uaFbe: 'ua-fbe@demo.petra.ac.id',
  kaprodiInformatika: 'kaprodi-informatika@demo.petra.ac.id',
  uaFsd: 'ua-fsd@demo.petra.ac.id',
  rektorat: 'rektorat@demo.petra.ac.id',
} as const;

export type AccountEmail = (typeof ACCOUNTS)[keyof typeof ACCOUNTS];

/** Logs in through the /login role switcher and waits for the dashboard. */
export async function loginAs(page: Page, email: AccountEmail | string): Promise<void> {
  await page.context().clearCookies();
  await page.goto('/login');
  await page.getByTestId(`login-${email}`).click();
  await page.waitForURL(/\/realisasi(\?.*)?$/);
  await expect(page.getByTestId('user-menu')).toBeVisible();
}

/** Rebuilds the database from migrations + the scenario seeds (scripts/db-reset.sh, without the bulk Kegiatan). */
export function resetDb(): void {
  execFileSync('bash', ['scripts/db-reset.sh'], { stdio: 'inherit', env: { ...process.env, SEED_BULK: '0' } });
}
