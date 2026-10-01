import { Badge } from '@/components/ui/badge';
import { formatDate, formatNumber } from '@/lib/realisasi/format';
import type { AgreementFlag } from '@/lib/realisasi/types';

/** "Belum ada realisasi tahun akademik ini" & friends (text + colour, never colour alone). */
export function AgreementFlagBadge({ flag }: { flag: AgreementFlag | undefined }) {
  if (!flag) return <span className="text-xs text-muted-foreground">–</span>;
  switch (flag.flag) {
    case 'realized':
      return <Badge variant="green">Terealisasi · {formatNumber(flag.activities_this_ay)} kegiatan TA ini</Badge>;
    case 'not_realized':
      return (
        <Badge variant="amber" data-testid="flag-not-realized">
          Belum ada realisasi tahun akademik ini
        </Badge>
      );
    case 'grace':
      return <Badge variant="blue">Masa tenggang s.d. {formatDate(flag.grace_until)}</Badge>;
    default:
      return <Badge variant="neutral">Tidak aktif</Badge>;
  }
}
