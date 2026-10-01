import base from './playwright.config';
import { defineConfig } from '@playwright/test';
export default defineConfig({
  ...base,
  globalSetup: undefined,
  reporter: [['list']],
  outputDir: '/tmp/claude-0/-home-user-SIM-Realisasi/ad392ca2-8324-5a2e-b2ea-71c99568f14e/scratchpad/pw-results',
  use: { ...base.use, baseURL: 'http://localhost:3102', launchOptions: { executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' } },
  webServer: undefined,
});
