/**
 * Demo session (CONTRACTS §6.3). SERVER ONLY.
 * The session is a plain `demo_uid` cookie holding a `kerjasama.profiles.id` (mockup; no passwords).
 * Accounts are SIM Kerjasama accounts (`public.akun`, read through the `kerjasama.profiles` adapter view) that have a
 * Realisasi role in `realisasi.account_roles`; inactive SIMKS accounts (app_role null) cannot sign in.
 * `can()` is pure and safe to import anywhere (it only mirrors Rules §10 for hiding UI controls —
 * the database stays authoritative).
 */
import { cache } from 'react';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { withSystem, type Tx } from '@/lib/db';

export type Role = 'submitter' | 'io_staff' | 'io_admin' | 'viewer';
/** Revisi V.1: one verification team (Mobility). */
export type Team = 'mobility';

export const SESSION_COOKIE = 'demo_uid';

/**
 * Security review I-1: the cookie role switcher (`/login`, `demo_uid` = a profile id) is an
 * UNAUTHENTICATED mockup feature. It is on by default for the demo and switched off with
 * `DEMO_AUTH=0`; then nobody can sign in (no accounts listed, `loginAs` refused, `demo_uid`
 * ignored) until real SSO (Supabase Auth / SAML-OIDC with verified JWTs) replaces it.
 * Never deploy beyond the demo with `DEMO_AUTH` enabled.
 */
export function isDemoAuthEnabled(): boolean {
  return process.env.DEMO_AUTH !== '0';
}

/**
 * Security review L-2: `Secure` in production (served over HTTPS). `SESSION_COOKIE_SECURE=0`
 * opts out for a plain-HTTP demo host; localhost works either way in modern browsers.
 */
export function sessionCookieSecure(): boolean {
  return process.env.NODE_ENV === 'production' && process.env.SESSION_COOKIE_SECURE !== '0';
}

export interface SessionUser {
  id: string;
  email: string;
  displayName: string;
  role: Role;
  unitId: number | null;
  unitName: string | null;
  teams: Team[];
}

// eslint-disable-next-line @typescript-eslint/no-empty-object-type
export interface DemoAccount extends SessionUser {}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

interface ProfileRow {
  id: string;
  email: string;
  display_name: string;
  app_role: Role;
  unit_id: number | null;
  unit_name: string | null;
  teams: Team[] | null;
}

function toSessionUser(r: ProfileRow): SessionUser {
  return {
    id: r.id,
    email: r.email,
    displayName: r.display_name,
    role: r.app_role,
    unitId: r.unit_id,
    unitName: r.unit_name,
    teams: (r.teams ?? []).filter((t): t is Team => t === 'mobility'),
  };
}

async function selectProfiles(tx: Tx, id: string | null): Promise<ProfileRow[]> {
  return tx<ProfileRow[]>`
    select p.id::text as id, p.email, p.display_name, p.app_role, p.unit_id, u.name as unit_name,
           coalesce((select array_agg(tm.team::text order by tm.team)
                       from realisasi.team_members tm where tm.account_id = p.id), '{}') as teams
      from kerjasama.profiles p
      left join kerjasama.units u on u.id = p.unit_id
     where p.app_role is not null
       and (${id}::uuid is null or p.id = ${id}::uuid)
     order by array_position(array['io_admin','io_staff','submitter','viewer'], p.app_role), p.akun_id`;
}

/** Realisasi accounts by role (admin, IO staff, submitters, viewers), then SIMKS akun id = CONTRACTS §5.3 order locally. */
export async function listDemoAccounts(): Promise<DemoAccount[]> {
  if (!isDemoAuthEnabled()) return [];
  const rows = await withSystem((tx) => selectProfiles(tx, null));
  return rows.map(toSessionUser);
}

/** Loads a profile by id (system access). Exported for the login action's validation. */
export async function findDemoAccount(id: string): Promise<DemoAccount | null> {
  if (!isDemoAuthEnabled() || !UUID_RE.test(id)) return null;
  const rows = await withSystem((tx) => selectProfiles(tx, id));
  const row = rows[0];
  return row ? toSessionUser(row) : null;
}

/** Current user from the `demo_uid` cookie; memoised per request. */
export const getSessionUser: () => Promise<SessionUser | null> = cache(async () => {
  const store = await cookies();
  const id = store.get(SESSION_COOKIE)?.value;
  if (!id) return null;
  try {
    return await findDemoAccount(id);
  } catch (e) {
    console.error('[session] failed to load profile', e);
    return null;
  }
});

/** Returns the current user or redirects to /login. */
export async function requireUser(): Promise<SessionUser> {
  const user = await getSessionUser();
  if (!user) redirect('/login');
  return user;
}

export type Capability =
  | 'activity.create'
  | 'verify.mobility'
  /** Revisi V.1 item 7: submitters follow their own mobility kegiatan (Menunggu / Revisi) on Verifikasi Mobilitas. */
  | 'verify.mobility.status'
  | 'edit.verified'
  | 'settings.manage'
  | 'reports.view'
  | 'export.participants'
  | 'export.snapshot'
  | 'export.conflicts'
  | 'snapshot.archive';

/** Pure capability check mirroring Rules §10 (io_admin = all). UI hints only. */
export function can(user: SessionUser, cap: Capability): boolean {
  if (user.role === 'io_admin') return true;
  const io = user.role === 'io_staff';
  const mobility = io && user.teams.includes('mobility');
  switch (cap) {
    case 'activity.create':
    case 'verify.mobility.status':
      return user.role === 'submitter';
    case 'verify.mobility':
    case 'export.conflicts':
      return mobility;
    case 'edit.verified':
    case 'settings.manage':
      return false;
    case 'reports.view':
      return true;
    case 'export.participants':
      return user.role === 'submitter' || mobility;
    case 'export.snapshot':
    case 'snapshot.archive':
      return io || user.role === 'viewer';
    default: {
      const _exhaustive: never = cap;
      return _exhaustive;
    }
  }
}

/** `realisasi.today()` as 'YYYY-MM-DD' (honours `demo_today`); memoised per request. */
export const getToday: () => Promise<string> = cache(async () => {
  const rows = await withSystem((tx) => tx<{ today: string }[]>`select realisasi.today()::text as today`);
  const today = rows[0]?.today;
  if (!today) throw new Error('realisasi.today() returned no row');
  return today;
});

/**
 * Whether demo time travel is enabled for this deployment (`realisasi.demo_time_travel_enabled()`,
 * WP-DB amendment 29). Off in production (no seeds); memoised per request.
 */
export const getDemoTimeTravelEnabled: () => Promise<boolean> = cache(async () => {
  try {
    const rows = await withSystem((tx) => tx<{ on: boolean }[]>`select realisasi.demo_time_travel_enabled() as on`);
    return rows[0]?.on === true;
  } catch (e) {
    console.error('[session] demo_time_travel_enabled() failed', e);
    return false;
  }
});

/**
 * `settings.demo_today` ('YYYY-MM-DD') or null when time travel is off — either no date is set or
 * the deployment flag is disabled (then the DB ignores the setting too); memoised per request.
 */
export const getDemoToday: () => Promise<string | null> = cache(async () => {
  // One round trip: the flag check and the setting together (realisasi._demo_today() applies both).
  try {
    const rows = await withSystem((tx) => tx<{ v: string | null }[]>`select realisasi._demo_today()::text as v`);
    return rows[0]?.v ?? null;
  } catch (e) {
    console.error('[session] demo_today lookup failed', e);
    return null;
  }
});
