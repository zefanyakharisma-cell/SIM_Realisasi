import { Lock, Radio } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { formatDate, formatDateTime } from '@/lib/realisasi/format';
import type { PeriodInfo } from '@/lib/realisasi/types';

/** Lock badge "Dibekukan <date>" for frozen periods; "Live s.d. <today>" otherwise. */
export function PeriodBadge({ period }: { period: PeriodInfo }) {
  if (period.frozen) {
    return (
      <Badge
        variant="blue"
        data-testid="period-frozen-badge"
        title={`Snapshot ${period.label} dibekukan ${formatDateTime(period.frozen_at)} oleh ${period.frozen_by_name ?? 'Job terjadwal'}`}
      >
        <Lock className="h-3 w-3" aria-hidden="true" />
        Dibekukan {formatDate(period.frozen_at)}
      </Badge>
    );
  }
  return (
    <Badge variant="neutral" data-testid="period-live-badge">
      <Radio className="h-3 w-3" aria-hidden="true" />
      Live s.d. {formatDate(period.window_end < period.today ? period.window_end : period.today)}
    </Badge>
  );
}
