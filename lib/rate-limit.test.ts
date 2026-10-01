import { describe, expect, it } from 'vitest';
import { createRateLimiter } from './rate-limit';

describe('createRateLimiter', () => {
  it('allows `limit` hits per window then blocks with retryAfter', () => {
    const rl = createRateLimiter({ limit: 3, windowMs: 60_000 });
    expect([1, 2, 3].map((i) => rl.hit('u', i).ok)).toEqual([true, true, true]);
    const blocked = rl.hit('u', 1000);
    expect(blocked.ok).toBe(false);
    expect(blocked.retryAfter).toBe(60);
    expect(rl.hit('other', 1000).ok).toBe(true);
    expect(rl.hit('u', 60_002).ok).toBe(true);
  });
});

describe('weighted hits (security review H-1: count ids, not requests)', () => {
  it('charges `cost` units and refuses a request that would exceed the budget', () => {
    const rl = createRateLimiter({ limit: 600, windowMs: 600_000 });
    expect(rl.hit('u', 0, 200).ok).toBe(true);
    expect(rl.hit('u', 1, 200).ok).toBe(true);
    expect(rl.hit('u', 2, 200).ok).toBe(true);
    const refused = rl.hit('u', 3, 1);
    expect(refused.ok).toBe(false);
    expect(refused.retryAfter).toBe(600);
    // a refused request records nothing
    expect(rl.hit('u', 600_001, 200).ok).toBe(true);
  });

  it('a request bigger than the remaining budget is refused even when some budget is left', () => {
    const rl = createRateLimiter({ limit: 10, windowMs: 1000 });
    expect(rl.hit('u', 0, 8).ok).toBe(true);
    const r = rl.hit('u', 1, 5);
    expect(r.ok).toBe(false);
    expect(r.remaining).toBe(2);
    expect(rl.hit('u', 2, 2).ok).toBe(true);
  });
});
