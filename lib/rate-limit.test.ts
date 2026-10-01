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
