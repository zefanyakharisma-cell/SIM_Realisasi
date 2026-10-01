import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: './e2e', testMatch: 'submit.spec.ts', workers: 1, timeout: 120_000, expect: { timeout: 15_000 },
  outputDir: process.env.PW_OUT,
  use: { baseURL: 'http://localhost:3101', locale: 'id-ID', timezoneId: 'Asia/Jakarta', trace: 'retain-on-failure', screenshot: 'only-on-failure',
    launchOptions: { executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' } },
});
