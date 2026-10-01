'use client';

import { Download, MoreHorizontal, Table2, BarChart3 } from 'lucide-react';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { Button } from '@/components/ui/button';

/** ⋯ menu on every dashboard card/chart: "Unduh Excel" (+ optional table/chart toggle). */
export function CardMenu({
  exportHref,
  label,
  showingTable,
  onToggleTable,
}: {
  exportHref: string;
  label: string;
  showingTable?: boolean;
  onToggleTable?: () => void;
}) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon" className="h-8 w-8 shrink-0" aria-label={`Menu ${label}`}>
          <MoreHorizontal aria-hidden="true" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        {onToggleTable ? (
          <DropdownMenuItem onSelect={onToggleTable}>
            {showingTable ? <BarChart3 aria-hidden="true" /> : <Table2 aria-hidden="true" />}
            {showingTable ? 'Lihat grafik' : 'Lihat sebagai tabel'}
          </DropdownMenuItem>
        ) : null}
        <DropdownMenuItem asChild>
          <a href={exportHref} download data-testid="export-excel">
            <Download aria-hidden="true" />
            Unduh Excel
          </a>
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
