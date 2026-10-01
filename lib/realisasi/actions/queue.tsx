'use server';
/**
 * Lazy-loaded verification-queue panels (frontend review M-8): rows after the prefetched ones
 * render their Detail + actions on first expand. Returns server-rendered React content.
 */
import type { ReactNode } from 'react';
import { z } from 'zod';
import { mobilityPanel, partnershipPanel } from '@/components/realisasi/verify/queue-panels';
import { withUser } from '@/lib/db';
import { can, requireUser } from '@/lib/session';

const inputSchema = z.object({ track: z.enum(['partnership', 'mobility']), id: z.string().uuid() });

export async function loadQueuePanel(track: string, id: string): Promise<ReactNode | null> {
  const user = await requireUser();
  const parsed = inputSchema.safeParse({ track, id });
  if (!parsed.success) return null;
  if (!can(user, parsed.data.track === 'partnership' ? 'verify.partnership' : 'verify.mobility')) return null;
  return withUser(user.id, (tx) =>
    parsed.data.track === 'partnership' ? partnershipPanel(tx, parsed.data.id) : mobilityPanel(tx, parsed.data.id),
  );
}
