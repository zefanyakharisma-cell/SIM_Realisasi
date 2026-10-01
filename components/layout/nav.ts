/** Navigation model (Design §1). Built on the server (uses `can`), rendered by the client sidebar. */
import { can, type SessionUser } from '@/lib/session';
import type { NavCounts } from '@/lib/realisasi/types';

export type NavIcon =
  | 'dashboard'
  | 'list'
  | 'plus'
  | 'handshake'
  | 'users'
  | 'copy'
  | 'book'
  | 'report'
  | 'settings'
  | 'file';

export interface NavItem {
  href: string;
  label: string;
  icon: NavIcon;
  /** data-testid = `nav-<last route segment>` */
  testId: string;
  badge?: number;
  badgeLabel?: string;
  /** Exact match for active state (dashboard / list roots). */
  exact?: boolean;
}

export interface NavSection {
  title: string;
  items: NavItem[];
}

function item(href: string, label: string, icon: NavIcon, extra: Partial<NavItem> = {}): NavItem {
  const seg = href.split('?')[0]!.split('/').filter(Boolean).pop() ?? 'root';
  return { href, label, icon, testId: `nav-${seg}`, ...extra };
}

export function buildNav(user: SessionUser, counts: NavCounts): NavSection[] {
  const realisasi: NavItem[] = [
    item('/realisasi', 'Dashboard', 'dashboard', { exact: true }),
    item('/realisasi/kegiatan', 'Kegiatan', 'list', {
      exact: true,
      ...(user.role === 'submitter' && counts.revision_inbox > 0
        ? { badge: counts.revision_inbox, badgeLabel: `${counts.revision_inbox} kegiatan perlu revisi` }
        : {}),
    }),
  ];
  if (can(user, 'activity.create')) realisasi.push(item('/realisasi/kegiatan/baru', 'Kegiatan Baru', 'plus'));
  if (can(user, 'verify.partnership'))
    realisasi.push(
      item('/realisasi/verifikasi/kemitraan', 'Verifikasi Kemitraan', 'handshake', {
        badge: counts.partnership_queue,
        badgeLabel: `${counts.partnership_queue} dalam antrean`,
      }),
    );
  if (can(user, 'verify.mobility'))
    realisasi.push(
      item('/realisasi/verifikasi/mobilitas', 'Verifikasi Mobilitas', 'users', {
        badge: counts.mobility_queue,
        badgeLabel: `${counts.mobility_queue} dalam antrean`,
      }),
    );
  if (can(user, 'duplicates.manage'))
    realisasi.push(
      item('/realisasi/verifikasi/duplikat', 'Duplikat', 'copy', {
        badge: counts.duplicates_open,
        badgeLabel: `${counts.duplicates_open} kandidat terbuka`,
      }),
    );
  if (can(user, 'known.view')) realisasi.push(item('/realisasi/kegiatan-diketahui', 'Kegiatan Diketahui', 'book'));
  realisasi.push(item('/realisasi/laporan', 'Laporan & Ekspor', 'report'));
  if (can(user, 'settings.manage')) realisasi.push(item('/realisasi/pengaturan', 'Pengaturan', 'settings'));

  return [
    { title: 'Realisasi', items: realisasi },
    { title: 'SIM Kerjasama', items: [item('/kerjasama/dokumen', 'Dokumen', 'file')] },
  ];
}
