'use server';

/** Notification server actions (own rows only — RLS `recipient_id = auth.uid()`; marks via `mark_notifications_read`). */
import { revalidatePath } from 'next/cache';
import { withUser, type Tx } from '@/lib/db';
import { requireUser } from '@/lib/session';
import { appError, runAction } from '@/lib/realisasi/errors';
import type { ActionResult, NotificationRow } from '@/lib/realisasi/types';

async function selectNotifications(tx: Tx, opts: { limit: number; unreadOnly: boolean }): Promise<NotificationRow[]> {
  return tx<NotificationRow[]>`
    select id, recipient_id::text as recipient_id, kind, title, body, link, read_at, created_at
      from realisasi.notifications
     where (not ${opts.unreadOnly}::boolean or read_at is null)
     order by created_at desc, id desc
     limit ${opts.limit}::int`;
}

export async function listNotifications(opts?: { limit?: number; unreadOnly?: boolean }): Promise<ActionResult<NotificationRow[]>> {
  const user = await requireUser();
  const limit = Math.min(Math.max(Math.trunc(opts?.limit ?? 10), 1), 200);
  return runAction(() => withUser(user.id, (tx) => selectNotifications(tx, { limit, unreadOnly: Boolean(opts?.unreadOnly) })));
}

/** `ids = null` marks every unread notification of the current user. Returns the number updated. */
export async function markNotificationsRead(ids: number[] | null): Promise<ActionResult<number>> {
  const user = await requireUser();
  const res = await runAction(async () => {
    if (ids !== null && (!Array.isArray(ids) || !ids.every((n) => Number.isSafeInteger(n) && n > 0))) {
      throw appError('BAD_REQUEST');
    }
    const literal = ids === null ? null : `{${ids.join(',')}}`;
    return withUser(user.id, async (tx) => {
      const [row] = await tx<{ n: number }[]>`select realisasi.mark_notifications_read(${literal}::bigint[]) as n`;
      return row?.n ?? 0;
    });
  });
  if (res.ok) revalidatePath('/realisasi', 'layout');
  return res;
}
