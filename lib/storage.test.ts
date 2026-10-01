import { describe, expect, it } from 'vitest';
import { MAX_FILE_BYTES, fileHref, newActivityFilePath, newTranscriptPath, validateUpload } from './storage';

const PDF = new Uint8Array([0x25, 0x50, 0x44, 0x46, 0x2d, 0x31]);
const ID = 'a0000000-0000-4000-8000-000000000013';

describe('validateUpload', () => {
  it('accepts a PDF with magic bytes', () => {
    expect(validateUpload({ name: 'ia.pdf', type: 'application/pdf', size: 100 }, 'pdf', PDF)).toEqual({ ok: true });
  });
  it('rejects oversize files', () => {
    const r = validateUpload({ name: 'x.pdf', type: 'application/pdf', size: MAX_FILE_BYTES + 1 }, 'pdf');
    expect(r).toMatchObject({ ok: false, code: 'R13_FILE_TOO_LARGE' });
  });
  it('rejects wrong types and fake PDFs', () => {
    expect(validateUpload({ name: 'x.png', type: 'image/png', size: 1 }, 'pdf')).toMatchObject({ code: 'R13_FILE_TYPE' });
    expect(validateUpload({ name: 'x.pdf', type: 'application/pdf', size: 1 }, 'pdf', new Uint8Array([1, 2, 3, 4, 5]))).toMatchObject({
      code: 'R13_FILE_TYPE',
    });
    expect(validateUpload({ name: 'x.png', type: 'image/png', size: 1 }, 'pdf_or_image')).toEqual({ ok: true });
  });
});

describe('paths', () => {
  it('builds activity file paths', () => {
    expect(newActivityFilePath(ID, 'ia', 'Laporan Akhir.PDF')).toMatch(
      new RegExp(`^realisasi-files/${ID}/ia/[0-9a-f-]{36}\\.pdf$`),
    );
    expect(newActivityFilePath(ID, 'evidence', 'foto.jpeg')).toMatch(/\.jpg$/);
    expect(newActivityFilePath(ID, 'evidence', 'noext')).toMatch(/\.bin$/);
  });
  it('builds transcript paths', () => {
    expect(newTranscriptPath(ID, 2, 'x01260012')).toMatch(new RegExp(`^realisasi-transcripts/${ID}/v2/X01260012-[0-9a-f]{8}\\.pdf$`));
  });
  it('encodes hrefs per segment', () => {
    expect(fileHref('realisasi-files/a b/ia/x.pdf')).toBe('/api/files/realisasi-files/a%20b/ia/x.pdf');
  });
});
