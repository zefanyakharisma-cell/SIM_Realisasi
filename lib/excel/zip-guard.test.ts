import { deflateRawSync } from 'node:zlib';
import ExcelJS from 'exceljs';
import { describe, expect, it } from 'vitest';
import { checkZip } from './zip-guard';

/** Minimal zip writer (deflate) for test archives; `declared` lets a test lie about sizes. */
function zip(entries: Array<{ name: string; data: Buffer; declared?: number }>): Buffer {
  const locals: Buffer[] = [];
  const cens: Buffer[] = [];
  let offset = 0;
  for (const e of entries) {
    const comp = deflateRawSync(e.data);
    const name = Buffer.from(e.name);
    const size = e.declared ?? e.data.length;
    const loc = Buffer.alloc(30);
    loc.writeUInt32LE(0x04034b50, 0);
    loc.writeUInt16LE(20, 4);
    loc.writeUInt16LE(8, 8);
    loc.writeUInt32LE(comp.length, 18);
    loc.writeUInt32LE(size, 22);
    loc.writeUInt16LE(name.length, 26);
    const cen = Buffer.alloc(46);
    cen.writeUInt32LE(0x02014b50, 0);
    cen.writeUInt16LE(20, 4);
    cen.writeUInt16LE(20, 6);
    cen.writeUInt16LE(8, 10);
    cen.writeUInt32LE(comp.length, 20);
    cen.writeUInt32LE(size, 24);
    cen.writeUInt16LE(name.length, 28);
    cen.writeUInt32LE(offset, 42);
    locals.push(loc, name, comp);
    cens.push(cen, name);
    offset += loc.length + name.length + comp.length;
  }
  const cd = Buffer.concat(cens);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(entries.length, 8);
  eocd.writeUInt16LE(entries.length, 10);
  eocd.writeUInt32LE(cd.length, 12);
  eocd.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, cd, eocd]);
}

describe('checkZip (security review M-1: xlsx decompression bomb)', () => {
  it('accepts a real participant template', async () => {
    const wb = new ExcelJS.Workbook();
    const ws = wb.addWorksheet('Peserta');
    ws.addRow(['NRP']);
    for (let i = 0; i < 1000; i++) ws.addRow([`D3124${String(i).padStart(4, '0')}`]);
    const buf = Buffer.from(await wb.xlsx.writeBuffer());
    const res = checkZip(buf);
    expect(res.ok).toBe(true);
  });

  it('rejects an archive that inflates past the limit (honest headers)', () => {
    const bomb = zip([{ name: 'xl/worksheets/sheet1.xml', data: Buffer.alloc(6 * 1024 * 1024, 'A') }]);
    expect(bomb.length).toBeLessThan(64 * 1024); // tiny on the wire
    expect(checkZip(bomb)).toEqual({ ok: false, reason: 'too_large' });
  });

  it('rejects a bomb whose headers lie about the uncompressed size', () => {
    const bomb = zip([{ name: 'xl/worksheets/sheet1.xml', data: Buffer.alloc(8 * 1024 * 1024, 'A'), declared: 100 }]);
    expect(checkZip(bomb)).toEqual({ ok: false, reason: 'too_large' });
  });

  it('rejects too many entries and non-zip input', () => {
    const many = zip(Array.from({ length: 70 }, (_, i) => ({ name: `f${i}`, data: Buffer.from('x') })));
    expect(checkZip(many)).toEqual({ ok: false, reason: 'too_many_entries' });
    expect(checkZip(Buffer.from('NRP\nD31240187\n'))).toEqual({ ok: false, reason: 'not_zip' });
  });
});
