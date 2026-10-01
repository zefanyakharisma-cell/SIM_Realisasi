/**
 * Cross-origin write check for `/api/*` route handlers (security review L-1). Edge-safe and pure
 * (used by `middleware.ts`; unit-tested in `origin-check.test.ts`).
 *
 * A state-changing request is refused when the browser says it came from another site or another
 * subdomain of the same site (`Sec-Fetch-Site: cross-site | same-site`), or when its `Origin`
 * differs from the app's own origin. Requests without either header (curl, server-to-server) are
 * allowed: they cannot carry a victim's cookies by accident.
 */
const SAFE_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);

export function isCrossOriginWrite(
  method: string,
  headers: { get(name: string): string | null },
  appHost: string,
): boolean {
  if (SAFE_METHODS.has(method.toUpperCase())) return false;
  const site = headers.get('sec-fetch-site');
  if (site === 'cross-site' || site === 'same-site') return true;
  const origin = headers.get('origin');
  if (!origin) return false;
  if (origin === 'null') return true;
  try {
    return new URL(origin).host.toLowerCase() !== appHost.toLowerCase();
  } catch {
    return true;
  }
}
