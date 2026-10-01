// Excel workbook helpers (Design §5, CONTRACTS §6.8 / §8.2).
// Server-only: imported by export route handlers and the registry.
import ExcelJS from 'exceljs';

export type CellFormat = 'date' | 'datetime' | 'pct' | 'int' | 'decimal' | 'text';
export type CellValue = string | number | Date | boolean | null;

export interface InfoSheet {
  kind: string;
  title: string;
  filters: Array<[string, string]>;
  generatedBy: string;
  generatedAt: Date;
  dataAsOf: string;
  rowCount: number;
  /** Extra rows appended after the standard ones (e.g. snapshot metadata). */
  extra?: Array<[string, string]>;
}

export interface Column<R> {
  header: string;
  key: string;
  width?: number;
  value: (row: R) => CellValue;
  /** Static format, or a per-row format (used by mixed "Nilai" columns). */
  format?: CellFormat | ((row: R) => CellFormat);
}

const JAKARTA_OFFSET_MS = 7 * 60 * 60 * 1000;
const NUM_FMT: Record<CellFormat, string | undefined> = {
  date: 'dd-mm-yyyy',
  datetime: 'dd-mm-yyyy hh:mm',
  pct: '0.0%',
  int: '#,##0',
  decimal: '0.00',
  text: '@',
};

const HEADER_FILL: ExcelJS.Fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFE8EEF7' } };

export function createWorkbook(): ExcelJS.Workbook {
  const wb = new ExcelJS.Workbook();
  wb.creator = 'SIM Realisasi';
  wb.created = new Date();
  return wb;
}

/**
 * 'YYYY-MM-DD' → Date at UTC midnight (Excel shows the same calendar day).
 * ISO timestamp → Date shifted to Asia/Jakarta wall-clock (Excel has no TZ).
 */
export function toExcelDate(v: string | Date | null | undefined, withTime = false): Date | null {
  if (v === null || v === undefined || v === '') return null;
  if (v instanceof Date) return withTime ? new Date(v.getTime() + JAKARTA_OFFSET_MS) : v;
  if (/^\d{4}-\d{2}-\d{2}$/.test(v)) return new Date(`${v}T00:00:00Z`);
  const d = new Date(v);
  if (Number.isNaN(d.getTime())) return null;
  const shifted = new Date(d.getTime() + JAKARTA_OFFSET_MS);
  if (withTime) return shifted;
  return new Date(Date.UTC(shifted.getUTCFullYear(), shifted.getUTCMonth(), shifted.getUTCDate()));
}

const FORMULA_LEAD = /^[=+\-@\t\r]/;

/**
 * Formula-injection guard (security review L-6, OWASP "CSV injection"): text that starts with
 * = + - @ TAB or CR gets a leading apostrophe, so it stays text even after the user re-saves the
 * workbook as CSV or re-enters the cell. Use for every free-text cell (and any future CSV export).
 */
export function neutralizeFormula(text: string): string {
  return FORMULA_LEAD.test(text) ? `'${text}` : text;
}

/** Converts a raw value to what exceljs should store for the given format. */
function coerce(value: CellValue, fmt: CellFormat | undefined): ExcelJS.CellValue {
  if (value === null || value === undefined) return null;
  if (typeof value === 'string' && fmt !== 'date' && fmt !== 'datetime') return neutralizeFormula(value);
  switch (fmt) {
    case 'date':
      return typeof value === 'string' || value instanceof Date ? toExcelDate(value) : value;
    case 'datetime':
      return typeof value === 'string' || value instanceof Date ? toExcelDate(value, true) : value;
    case 'pct':
      // KPI percentages arrive as 0–100 numbers (e.g. 42.9) → store as fraction.
      return typeof value === 'number' ? value / 100 : value;
    case 'int':
    case 'decimal':
      return typeof value === 'number' ? value : value;
    default:
      if (typeof value === 'boolean') return value ? 'Ya' : 'Tidak';
      return value;
  }
}

function displayLength(value: CellValue, fmt: CellFormat | undefined): number {
  if (value === null || value === undefined) return 0;
  if (fmt === 'date') return 10;
  if (fmt === 'datetime') return 16;
  if (fmt === 'pct') return 7;
  if (value instanceof Date) return 10;
  const s = typeof value === 'boolean' ? (value ? 'Ya' : 'Tidak') : String(value);
  // longest line for multi-line cells
  return s.split('\n').reduce((m, line) => Math.max(m, line.length), 0);
}

function styleHeader(ws: ExcelJS.Worksheet, columnCount: number): void {
  const header = ws.getRow(1);
  header.font = { bold: true };
  header.alignment = { vertical: 'middle' };
  for (let c = 1; c <= columnCount; c += 1) {
    header.getCell(c).fill = HEADER_FILL;
    header.getCell(c).border = { bottom: { style: 'thin', color: { argb: 'FF9AA5B1' } } };
  }
  ws.views = [{ state: 'frozen', ySplit: 1, xSplit: 0 }];
}

/** Excel sheet names: ≤31 chars, no []:*?/\ */
export function safeSheetName(name: string): string {
  return name.replace(/[[\]:*?/\\]/g, '-').slice(0, 31) || 'Sheet';
}

export function addTableSheet<R>(
  wb: ExcelJS.Workbook,
  name: string,
  columns: Column<R>[],
  rows: R[],
): ExcelJS.Worksheet {
  const ws = wb.addWorksheet(safeSheetName(name));
  ws.columns = columns.map((c) => ({ header: c.header, key: c.key }));
  const widths = columns.map((c) => c.header.length);

  for (const row of rows) {
    const excelRow = ws.addRow(
      Object.fromEntries(
        columns.map((c) => {
          const fmt = typeof c.format === 'function' ? c.format(row) : c.format;
          return [c.key, coerce(c.value(row), fmt)];
        }),
      ),
    );
    columns.forEach((c, i) => {
      const raw = c.value(row);
      const fmt = typeof c.format === 'function' ? c.format(row) : c.format;
      const numFmt = fmt ? NUM_FMT[fmt] : undefined;
      if (numFmt && fmt !== 'text') excelRow.getCell(i + 1).numFmt = numFmt;
      if (typeof raw === 'string' && raw.includes('\n')) {
        excelRow.getCell(i + 1).alignment = { wrapText: true, vertical: 'top' };
      }
      widths[i] = Math.max(widths[i] ?? 0, displayLength(raw, fmt));
    });
  }

  columns.forEach((c, i) => {
    const col = ws.getColumn(i + 1);
    col.width = c.width ?? Math.min(60, Math.max(8, (widths[i] ?? 8) + 2));
  });

  styleHeader(ws, columns.length);
  if (columns.length > 0) {
    ws.autoFilter = { from: { row: 1, column: 1 }, to: { row: Math.max(1, rows.length + 1), column: columns.length } };
  }
  return ws;
}

export function formatJakartaDateTime(d: Date): string {
  const s = new Date(d.getTime() + JAKARTA_OFFSET_MS).toISOString();
  return `${s.slice(8, 10)}-${s.slice(5, 7)}-${s.slice(0, 4)} ${s.slice(11, 16)} WIB`;
}

/** Info sheet: always the first sheet (CONTRACTS §8.2). */
export function addInfoSheet(wb: ExcelJS.Workbook, info: InfoSheet): void {
  const ws = wb.addWorksheet('Info');
  // Always first, even when data sheets were added before (exceljs sorts by orderNo; others start at 1).
  (ws as unknown as { orderNo: number }).orderNo = 0;
  ws.columns = [
    { header: 'Keterangan', key: 'k' },
    { header: 'Nilai', key: 'v' },
  ];
  const rows: Array<[string, string | number]> = [
    ['Jenis ekspor', info.kind],
    ['Judul', info.title],
    ...info.filters.map(([label, value]): [string, string] => [`Filter: ${label}`, value]),
    ['Dibuat oleh', info.generatedBy],
    ['Dibuat pada', formatJakartaDateTime(info.generatedAt)],
    ['Data per', info.dataAsOf],
    ['Jumlah baris', info.rowCount],
    ...(info.extra ?? []),
  ];
  let maxK = 10;
  let maxV = 10;
  for (const [k, v] of rows) {
    ws.addRow({ k, v });
    maxK = Math.max(maxK, k.length);
    maxV = Math.max(maxV, String(v).length);
  }
  ws.getColumn(1).width = Math.min(45, maxK + 2);
  ws.getColumn(2).width = Math.min(100, maxV + 2);
  ws.getColumn(2).alignment = { wrapText: true, vertical: 'top' };
  ws.getColumn(1).font = { bold: true };
  styleHeader(ws, 2);
}

export async function toBuffer(wb: ExcelJS.Workbook): Promise<Buffer> {
  const ab = await wb.xlsx.writeBuffer();
  return Buffer.from(ab as ArrayBuffer);
}
