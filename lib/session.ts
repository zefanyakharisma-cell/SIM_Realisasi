/**
 * Demo session (CONTRACTS §6.3). SERVER ONLY.
 * The session is a plain `demo_uid` cookie holding a `public.profiles.id` (mockup; no passwords).
 * `can()` is pure and safe to import anywhere (it only mirrors Rules §10 for hiding UI controls —
 * the database stays authoritative).
 */
import { cache } from 'react';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { withSystem, type Tx } from '@/lib/db';

export type Role = 'submitter' | 'io_staff' | 'io_admin' | 'viewer';
export type Team = 'partnership' | 'mobility';

export const SESSION_COOKIE = 'demo_uid';

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
    teams: (r.teams ?? []).filter((t): t is Team => t === 'partnership' || t === 'mobility'),
  };
}

async function selectProfiles(tx: Tx, id: string | null): Promise<ProfileRow[]> {
  return tx<ProfileRow[]>`
    select p.id::text as id, p.email, p.display_name, p.app_role, p.unit_id, u.name as unit_name,
           coalesce((select array_agg(tm.team::text order by tm.team)
                       from realisasi.team_members tm where tm.account_id = p.id), '{}') as teams
      from public.profiles p
      left join public.units u on u.id = p.unit_id
     where ${id}::uuid is null or p.id = ${id}::uuid
     order by p.id`;
}

/** The 8 seed accounts in CONTRACTS §5.3 order (fixed ids sort in that order). */
export async function listDemoAccounts(): Promise<DemoAccount[]> {
  const rows = await withSystem((tx) => selectProfiles(tx, null));
  return rows.map(toSessionUser);
}

/** Loads a profile by id (system access). Exported for the login action's validation. */
export async function findDemoAccount(id: string): Promise<DemoAccount | null> {
  if (!UUID_RE.test(id)) return null;
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
  | 'verify.partnership'
  | 'verify.mobility'
  | 'duplicates.view'
  | 'duplicates.manage'
  | 'known.view'
  | 'known.manage'
  | 'settings.manage'
  | 'reports.view'
  | 'export.participants'
  | 'export.snapshot'
  | 'export.known'
  | 'export.duplicates'
  | 'snapshot.archive';

/** Pure capability check mirroring Rules §10 (io_admin = all). UI hints only. */
export function can(user: SessionUser, cap: Capability): boolean {
  if (user.role === 'io_admin') return true;
  const io = user.role === 'io_staff';
  const partnership = io && user.teams.includes('partnership');
  const mobility = io && user.teams.includes('mobility');
  switch (cap) {
    case 'activity.create':
      return user.role === 'submitter';
    case 'verify.partnership':
    case 'duplicates.manage':
    case 'known.manage':
      return partnership;
    case 'verify.mobility':
      return mobility;
    case 'duplicates.view':
    case 'known.view':
    case 'export.known':
    case 'export.duplicates':
      return io;
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

/** `settings.demo_today` ('YYYY-MM-DD') or null when time travel is off; memoised per request. */
export const getDemoToday: () => Promise<string | null> = cache(async () => {
  const rows = await withSystem(
    (tx) => tx<{ v: string | null }[]>`
      select case when jsonb_typeof(value) = 'string' then value #>> '{}' else null end as v
        from realisasi.settings where key = 'demo_today'`,
  );
  return rows[0]?.v ?? null;
});
