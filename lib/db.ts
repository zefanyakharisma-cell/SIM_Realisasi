/**
 * Database access (CONTRACTS §6.2). SERVER ONLY — never import from a client component.
 *
 * Type parsing (registered on the singleton below):
 *  - 1082 `date`               → 'YYYY-MM-DD' string, returned verbatim from Postgres.
 *                                Never a JS Date: `new Date('2026-09-14')` is UTC midnight and
 *                                renders as 13 Sep in negative offsets / shifts on round-trips.
 *  - 1114 `timestamp`, 1184 `timestamptz` → ISO-8601 string (`2026-09-14T03:42:00.000Z`).
 *                                Postgres text output is parsed once and re-serialised with
 *                                toISOString(), so it is stable regardless of the session TimeZone.
 *  - 20 `int8`, 1700 `numeric` → number (bigserial ids, counts, scores fit in a double).
 *  - 114 `json`, 3802 `jsonb`  → parsed by postgres.js (default). Inside json values, dates are
 *                                whatever `to_jsonb()` produced ('YYYY-MM-DD' / ISO strings).
 *  - Array variants (1182 date[], 1185 timestamptz[], 1016 int8[], 1231 numeric[]) are parsed
 *    element-wise by postgres.js using the same parsers.
 *
 * Parameters: postgres.js serialises JS values; always cast explicitly in SQL (`${x}::date`).
 */
import postgres from 'postgres';

export type Tx = postgres.TransactionSql;

const DEFAULT_DATABASE_URL = 'postgresql://postgres@localhost:54322/sim_realisasi';

function toIso(value: string): string {
  // Postgres text format: '2026-09-14 10:42:00+07' / '2026-09-14 10:42:00.123456+07:00' / no zone for `timestamp`.
  const normalised = value.includes('T') ? value : value.replace(' ', 'T');
  const withZone = /[+-]\d{2}(:?\d{2})?$|Z$/.test(normalised) ? normalised : `${normalised}Z`;
  const fixedZone = withZone.replace(/([+-]\d{2})$/, '$1:00');
  const d = new Date(fixedZone);
  return Number.isNaN(d.getTime()) ? value : d.toISOString();
}

function toNumber(value: string): number {
  return Number(value);
}

const identity = (value: string): string => value;

/**
 * Connections per server instance. On Vercel many instances (production, still-warm old deployments, previews) share
 * one Supavisor pool (15 server connections), and a frozen instance keeps its sockets open, so each instance must stay
 * small: default 3 there, 10 locally; `DB_POOL_MAX` overrides. Use the TRANSACTION pooler (port 6543) for the app.
 */
const ON_VERCEL = Boolean(process.env.VERCEL);

function poolMax(): number {
  const n = Number(process.env.DB_POOL_MAX);
  return Number.isInteger(n) && n > 0 ? n : ON_VERCEL ? 3 : 10;
}

function createSql(): postgres.Sql {
  return postgres(process.env.DATABASE_URL ?? DEFAULT_DATABASE_URL, {
    max: poolMax(),
    // Unnamed statements: survives schema resets under a running server and
    // works behind Supabase's transaction-mode pooler.
    prepare: false,
    // Release idle connections quickly on serverless; recycle long-lived ones.
    idle_timeout: ON_VERCEL ? 5 : 20,
    max_lifetime: 60 * 5,
    connect_timeout: 10,
    onnotice: () => {},
    types: {
      date: {
        to: 1082,
        from: [1082],
        serialize: (x: unknown) => (x instanceof Date ? x.toISOString().slice(0, 10) : String(x)),
        parse: identity,
      },
      timestamptz: {
        to: 1184,
        from: [1114, 1184],
        serialize: (x: unknown) => (x instanceof Date ? x.toISOString() : String(x)),
        parse: toIso,
      },
      bigint: {
        to: 20,
        from: [20],
        serialize: (x: unknown) => String(x),
        parse: toNumber,
      },
      numeric: {
        to: 1700,
        from: [1700],
        serialize: (x: unknown) => String(x),
        parse: toNumber,
      },
    },
  }) as unknown as postgres.Sql;
}

const globalForDb = globalThis as unknown as { __simRealisasiSql?: postgres.Sql };

/** Singleton (cached on globalThis so dev HMR does not leak pools). */
export const sql: postgres.Sql = globalForDb.__simRealisasiSql ?? createSql();
if (process.env.NODE_ENV !== 'production') globalForDb.__simRealisasiSql = sql;

/**
 * Runs `fn` in one transaction as the given profile, under RLS:
 * sets `request.jwt.claims` / `request.jwt.claim.sub` (read by `auth.uid()`) and `role authenticated`.
 */
export async function withUser<T>(profileId: string, fn: (tx: Tx) => Promise<T>): Promise<T> {
  const result = await sql.begin(async (tx) => {
    const claims = JSON.stringify({ sub: profileId, role: 'authenticated' });
    // One round trip: claims + `set local role authenticated` (set_config('role', …, true) is SET LOCAL ROLE).
    await tx`select set_config('request.jwt.claims', ${claims}, true),
                    set_config('request.jwt.claim.sub', ${profileId}, true),
                    set_config('role', 'authenticated', true)`;
    return fn(tx);
  });
  return result as T;
}

/**
 * Transaction WITHOUT a role switch (connection role, bypasses RLS).
 * ONLY for: login account list, session profile load, getToday()/getDemoToday().
 */
export async function withSystem<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
  // No BEGIN/COMMIT: these are single read-only statements, so a transaction only added two round trips.
  return fn(sql as unknown as Tx);
}
