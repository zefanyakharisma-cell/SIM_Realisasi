import { expect, test, type Route } from '@playwright/test';
import { ACCOUNTS, loginAs, resetDb } from './helpers';

/**
 * Frontend review H-1 / H-2: concurrent edits while a save (or lookup) is in flight must not be
 * lost or reported as saved. Uses ua-fsd's seeded draft RL-2026-0023.
 */

const DRAFT = 'a0000000-0000-4000-8000-000000000023';

test.describe.configure({ mode: 'serial' });

test.afterAll(() => {
  if (process.env.E2E_SKIP_DB_RESET !== '1') resetDb();
});

/** A gate the test opens explicitly. */
function gate() {
  let open!: () => void;
  const opened = new Promise<void>((r) => (open = r));
  return { open, opened };
}

test('H-1: an edit made during an in-flight autosave is saved, not dropped as "Tersimpan"', async ({ page }) => {
  await loginAs(page, ACCOUNTS.uaFsd);
  await page.goto(`/realisasi/kegiatan/baru?draft=${DRAFT}`);
  const name = page.getByLabel('Nama kegiatan *');
  const description = page.getByLabel('Deskripsi *');
  await expect(name).toBeVisible();

  // Hold the first autosave (server action POST) until the test releases it.
  const release = gate();
  let actionPosts = 0;
  const firstSeen = gate();
  await page.route(/\/realisasi\/kegiatan\/baru/, async (route: Route) => {
    const req = route.request();
    if (req.method() === 'POST' && req.headers()['next-action']) {
      actionPosts++;
      if (actionPosts === 1) {
        firstSeen.open();
        await release.opened;
      }
    }
    await route.continue();
  });

  await name.fill('Kunjungan FSD — autosave A');
  await firstSeen.opened; // autosave #1 is in flight (held)

  await description.fill('Deskripsi ditulis saat penyimpanan pertama berjalan.');
  // Let the 1.5 s debounce of the second edit fire while save #1 is still pending.
  await page.waitForTimeout(2200);
  expect(actionPosts).toBe(1); // serialized: the second save waits instead of racing
  await expect(page.getByTestId('autosave-status')).not.toContainText('Tersimpan');

  release.open();
  await expect.poll(() => actionPosts, { timeout: 10_000 }).toBeGreaterThanOrEqual(2);
  await expect(page.getByTestId('autosave-status')).toContainText('Tersimpan', { timeout: 10_000 });

  await page.unroute(/\/realisasi\/kegiatan\/baru/);
  await page.reload();
  await expect(page.getByLabel('Nama kegiatan *')).toHaveValue('Kunjungan FSD — autosave A');
  await expect(page.getByLabel('Deskripsi *')).toHaveValue('Deskripsi ditulis saat penyimpanan pertama berjalan.');
});

test('H-2: a slow NRP lookup does not restore a staff row removed meanwhile', async ({ page }) => {
  await loginAs(page, ACCOUNTS.uaFsd);
  await page.goto(`/realisasi/kegiatan/baru?draft=${DRAFT}`);
  // S-23 is a guest lecture (no participants); make it a mobility kegiatan so the Peserta section unlocks.
  await expect(page.getByTestId('participants-not-needed')).toBeVisible();
  await page.getByLabel('Jenis kegiatan *').selectOption({ label: 'Student Exchange' });
  await page.getByLabel('Inbound / Outbound *').selectOption('outbound');
  await page.getByTestId('wizard-save-draft').click();
  await expect(page.getByLabel('Tempel ID pegawai (satu per baris)')).toBeVisible();

  await page.getByLabel('Tempel ID pegawai (satu per baris)').fill('PG204517');
  await page.getByTestId('check-employee').click();
  await expect(page.getByTestId('staff-row')).toHaveCount(1);
  await expect(page.getByTestId('autosave-status')).toContainText('Tersimpan');

  // Make the student lookup slow, start it, and remove the staff row while it is pending.
  const release = gate();
  await page.route('**/api/lookup/students', async (route) => {
    await release.opened;
    await route.continue();
  });
  await page.getByLabel('Tempel NRP (satu per baris)').first().fill('D31240187');
  await page.getByTestId('check-nrp').click();
  await page.getByRole('button', { name: 'Hapus PG204517' }).click();
  await expect(page.getByTestId('staff-row')).toHaveCount(0);
  release.open();

  await expect(page.getByTestId('student-row')).toHaveCount(1);
  await expect(page.getByTestId('staff-row')).toHaveCount(0); // not restored from a stale closure
  await expect(page.getByTestId('autosave-status')).toContainText('Tersimpan');

  await page.unroute('**/api/lookup/students');
  await page.reload();
  await expect(page.getByTestId('student-row')).toHaveCount(1);
  await expect(page.getByTestId('staff-row')).toHaveCount(0);
});

test('M-1: a debounced edit is saved before the page is left', async ({ page }) => {
  await loginAs(page, ACCOUNTS.uaFsd);
  await page.goto(`/realisasi/kegiatan/baru?draft=${DRAFT}`);
  // S-23 is an online activity: the venue field is the platform name.
  await page.getByLabel('Nama platform *').fill('Zoom Webinar (diubah)');
  // Jump to another section of the same page inside the 1.5 s debounce window.
  await page.getByRole('navigation', { name: 'Bagian formulir' }).getByRole('link', { name: /Berkas/ }).click();
  await expect(page.getByTestId('autosave-status')).toContainText('Tersimpan', { timeout: 10_000 });
  await page.reload();
  await expect(page.getByLabel('Nama platform *')).toHaveValue('Zoom Webinar (diubah)');
});
