/**
 * Tiny in-memory sliding-window rate limiter (WP-SUBMIT; used by /api/lookup/*).
 * Mockup scope: one Node process, state cached on globalThis so dev HMR keeps counters.
 */
export interface RateLimitResult {
  ok: boolean;
  remaining: number;
  /** Seconds until the oldest hit leaves the window (for `Retry-After`). */
  retryAfter: number;
}

export interface RateLimiter {
  hit(key: string, now?: number): RateLimitResult;
  reset(key?: string): void;
}

export function createRateLimiter(opts: { limit: number; windowMs: number }): RateLimiter {
  const hits = new Map<string, number[]>();
  return {
    hit(key, now = Date.now()) {
      const since = now - opts.windowMs;
      const recent = (hits.get(key) ?? []).filter((t) => t > since);
      if (recent.length >= opts.limit) {
        hits.set(key, recent);
        const oldest = recent[0] ?? now;
        return { ok: false, remaining: 0, retryAfter: Math.max(1, Math.ceil((oldest + opts.windowMs - now) / 1000)) };
      }
      recent.push(now);
      hits.set(key, recent);
      return { ok: true, remaining: opts.limit - recent.length, retryAfter: 0 };
    },
    reset(key) {
      if (key === undefined) hits.clear();
      else hits.delete(key);
    },
  };
}

const globalForLimiter = globalThis as unknown as { __simLookupLimiter?: RateLimiter };

/** Lookup routes: 60 requests per minute per user (CONTRACTS §8.1). */
export const lookupLimiter: RateLimiter =
  globalForLimiter.__simLookupLimiter ?? createRateLimiter({ limit: 60, windowMs: 60_000 });
globalForLimiter.__simLookupLimiter = lookupLimiter;
