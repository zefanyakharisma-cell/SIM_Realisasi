'use server';

/** Demo login / logout (CONTRACTS §6.3). */
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { SESSION_COOKIE, findDemoAccount, isDemoAuthEnabled, sessionCookieSecure } from '@/lib/session';

const SEVEN_DAYS_S = 7 * 24 * 60 * 60;

export async function loginAs(profileId: string): Promise<void> {
  // I-1: the role switcher only exists while DEMO_AUTH is on (default for the mockup).
  if (!isDemoAuthEnabled()) redirect('/login?error=nonaktif');
  const account = typeof profileId === 'string' ? await findDemoAccount(profileId) : null;
  if (!account) redirect('/login?error=akun');
  const store = await cookies();
  store.set(SESSION_COOKIE, account.id, {
    httpOnly: true,
    secure: sessionCookieSecure(),
    sameSite: 'lax',
    path: '/',
    maxAge: SEVEN_DAYS_S,
  });
  redirect('/realisasi');
}

export async function logout(): Promise<void> {
  const store = await cookies();
  store.delete(SESSION_COOKIE);
  redirect('/login');
}
