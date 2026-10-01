import type { FullConfig } from '@playwright/test';
import { resetDb } from './helpers';

/** Fresh DB for every run unless E2E_SKIP_DB_RESET=1. */
export default async function globalSetup(_config: FullConfig): Promise<void> {
  if (process.env.E2E_SKIP_DB_RESET === '1') return;
  resetDb();
}
