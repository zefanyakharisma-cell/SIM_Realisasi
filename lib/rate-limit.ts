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
  /** Records `cost` units (default 1) for `key`; refused (nothing recorded) when over the limit. */
  hit(key: string, now?: number, cost?: number): RateLimitResult;
  reset(key?: string): void;
}

export function createRateLimiter(opts: { limit: number; windowMs: number }): RateLimiter {
  const hits = new Map<string, number[]>();
  return {
    hit(key, now = Date.now(), cost = 1) {
      const since = now - opts.windowMs;
      const recent = (hits.get(key) ?? []).filter((t) => t > since);
      const units = Math.max(1, Math.floor(cost));
      if (recent.length + units > opts.limit) {
        hits.set(key, recent);
        // Wait until enough old units leave the window for this request to fit.
        const freeAt = recent[Math.min(recent.length - 1, recent.length + units - opts.limit - 1)] ?? now;
        return {
          ok: false,
          remaining: Math.max(0, opts.limit - recent.length),
          retryAfter: Math.max(1, Math.ceil((freeAt + opts.windowMs - now) / 1000)),
        };
      }
      for (let i = 0; i < units; i++) recent.push(now);
      hits.set(key, recent);
      return { ok: true, remaining: opts.limit - recent.length, retryAfter: 0 };
    },
    reset(key) {
      if (key === undefined) hits.clear();
      else hits.delete(key);
    },
  };
}

const globalForLimiter = globalThis as unknown as {
  __simLookupLimiter?: RateLimiter;
  __simLookupIdLimiter?: RateLimiter;
  __simTemplateLimiter?: RateLimiter;
  __simUploadLimiter?: RateLimiter;
  __simExportLimiter?: RateLimiter;
}

function shared(key: keyof typeof globalForLimiter, make: () => RateLimiter): RateLimiter {
  const existing = globalForLimiter[key];
  if (existing) return existing;
  const created = make();
  globalForLimiter[key] = created;
  return created;
}

/** Lookup routes: 60 requests per minute per user (CONTRACTS §8.1). */
export const lookupLimiter: RateLimiter = shared('__simLookupLimiter', () => createRateLimiter({ limit: 60, windowMs: 60_000 }));

/**
 * Registry lookups are also budgeted by **ids** (security review H-1): 600 NRP / employee ids per
 * 10 minutes per user — enough for several 200-participant activities, far below scraping volume
 * (previously 60 × 200 = 12,000 records per minute).
 */
export const LOOKUP_ID_BUDGET = { limit: 600, windowMs: 10 * 60_000 } as const;
export const lookupIdLimiter: RateLimiter = shared('__simLookupIdLimiter', () => createRateLimiter(LOOKUP_ID_BUDGET));

/** Participant template parsing: 20 files per 10 minutes per user (security review M-1 / L-5). */
export const templateLimiter: RateLimiter = shared('__simTemplateLimiter', () => createRateLimiter({ limit: 20, windowMs: 10 * 60_000 }));

/** Uploads: 60 files per 10 minutes per user (security review L-5). */
export const uploadLimiter: RateLimiter = shared('__simUploadLimiter', () => createRateLimiter({ limit: 60, windowMs: 10 * 60_000 }));

/** Excel exports: 40 per 10 minutes per user (security review L-5). */
export const exportLimiter: RateLimiter = shared('__simExportLimiter', () => createRateLimiter({ limit: 40, windowMs: 10 * 60_000 }));
