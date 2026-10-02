import { describe, expect, it } from 'vitest';
import { MAX_FILE_BYTES, fileHref, newActivityFilePath, newMobilityBundlePath, validateUpload } from './storage';

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
  it('builds mobility bundle paths', () => {
    expect(newMobilityBundlePath(ID)).toMatch(new RegExp(`^realisasi-transcripts/${ID}/mobility_bundle/[0-9a-f-]{36}\\.pdf$`));
  });
  it('encodes hrefs per segment', () => {
    expect(fileHref('realisasi-files/a b/ia/x.pdf')).toBe('/api/files/realisasi-files/a%20b/ia/x.pdf');
  });
});

describe('image content sniffing (security review L-3)', () => {
  it('requires JPEG / PNG magic bytes for images and rejects HTML posing as PNG', async () => {
    const { sniffMime } = await import('./storage');
    const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    const jpg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0]);
    const html = new TextEncoder().encode('<html><script>');
    expect(validateUpload({ name: 'a.png', type: 'image/png', size: 8 }, 'pdf_or_image', png)).toEqual({ ok: true });
    expect(validateUpload({ name: 'a.jpg', type: 'image/jpeg', size: 8 }, 'pdf_or_image', jpg)).toEqual({ ok: true });
    expect(validateUpload({ name: 'a.png', type: 'image/png', size: 8 }, 'pdf_or_image', html)).toMatchObject({ code: 'R13_FILE_TYPE' });
    expect(validateUpload({ name: 'a.png', type: 'image/png', size: 8 }, 'pdf_or_image', jpg)).toMatchObject({ code: 'R13_FILE_TYPE' });
    expect(sniffMime(png)).toBe('image/png');
    expect(sniffMime(html)).toBeNull();
  });
});

describe('isValidStoragePath (security review L-4)', () => {
  it('accepts the keys the app writes and rejects traversal / odd input', async () => {
    const { isValidStoragePath } = await import('./storage');
    const id = 'a0000000-0000-4000-8000-000000000013';
    expect(isValidStoragePath(newActivityFilePath(id, 'ia', 'x.pdf'))).toBe(true);
    expect(isValidStoragePath(newActivityFilePath(id, 'evidence', 'foto.JPEG'))).toBe(true);
    expect(isValidStoragePath(newMobilityBundlePath(id))).toBe(true);
    expect(isValidStoragePath('realisasi-files/../../etc/passwd')).toBe(false);
    expect(isValidStoragePath(`realisasi-transcripts/${id}/v1/X01250024-81ed5df4.pdf\u0000`)).toBe(false);
    expect(isValidStoragePath(`other-bucket/${id}/ia/${id}.pdf`)).toBe(false);
  });
});
