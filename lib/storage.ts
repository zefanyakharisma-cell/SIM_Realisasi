/**
 * File storage facade (CONTRACTS §6.4). Blobs live in `realisasi.file_blobs` behind the
 * `storage_put` / `storage_get` RPCs; this module is the swap point for Supabase Storage.
 * Path helpers and `validateUpload` are pure (client-safe); put/get need a `withUser` tx (server).
 */
import type { Tx } from '@/lib/db';

export const BUCKETS = { files: 'realisasi-files', transcripts: 'realisasi-transcripts' } as const;
export type Bucket = (typeof BUCKETS)[keyof typeof BUCKETS];
export const MAX_FILE_BYTES = 10 * 1024 * 1024;
export type UploadPolicy = 'pdf' | 'pdf_or_image';

const PDF_MIME = 'application/pdf';
const IMAGE_MIMES = ['image/jpeg', 'image/png'] as const;
const EXT_BY_MIME: Record<string, string> = { 'application/pdf': 'pdf', 'image/jpeg': 'jpg', 'image/png': 'png' };
const PDF_MAGIC = [0x25, 0x50, 0x44, 0x46, 0x2d]; // '%PDF-'

function startsWith(bytes: Uint8Array, magic: readonly number[]): boolean {
  if (bytes.length < magic.length) return false;
  return magic.every((b, i) => bytes[i] === b);
}

export function validateUpload(
  file: { name: string; type: string; size: number },
  policy: UploadPolicy,
  firstBytes?: Uint8Array,
): { ok: true } | { ok: false; code: 'R13_FILE_TOO_LARGE' | 'R13_FILE_TYPE'; message: string } {
  const allowedMimes: readonly string[] = policy === 'pdf' ? [PDF_MIME] : [PDF_MIME, ...IMAGE_MIMES];
  const allowedLabel = policy === 'pdf' ? 'PDF' : 'PDF, JPG, PNG';
  if (file.size > MAX_FILE_BYTES) {
    return { ok: false, code: 'R13_FILE_TOO_LARGE', message: 'Ukuran berkas melebihi 10 MB.' };
  }
  const typeError = { ok: false as const, code: 'R13_FILE_TYPE' as const, message: `Format berkas tidak diizinkan (${allowedLabel}).` };
  if (!allowedMimes.includes(file.type)) return typeError;
  if (file.type === PDF_MIME && firstBytes && !startsWith(firstBytes, PDF_MAGIC)) return typeError;
  return { ok: true };
}

function extensionFor(filename: string): string {
  const match = /\.([A-Za-z0-9]{1,8})$/.exec(filename);
  const ext = match?.[1]?.toLowerCase();
  if (ext === 'jpeg') return 'jpg';
  return ext && Object.values(EXT_BY_MIME).includes(ext) ? ext : 'bin';
}

function randomHex(bytes: number): string {
  const buf = new Uint8Array(bytes);
  globalThis.crypto.getRandomValues(buf);
  return Array.from(buf, (b) => b.toString(16).padStart(2, '0')).join('');
}

/** realisasi-files/<activityId>/<kind>/<uuid>.<ext> */
export function newActivityFilePath(activityId: string, kind: 'ia' | 'ir' | 'evidence', filename: string): string {
  return `${BUCKETS.files}/${activityId}/${kind}/${globalThis.crypto.randomUUID()}.${extensionFor(filename)}`;
}

/** realisasi-transcripts/<activityId>/v<version>/<nrp>-<8hex>.pdf */
export function newTranscriptPath(activityId: string, version: number, nrp: string): string {
  const safeNrp = nrp.replace(/[^A-Za-z0-9]/g, '').toUpperCase();
  return `${BUCKETS.transcripts}/${activityId}/v${version}/${safeNrp}-${randomHex(4)}.pdf`;
}

export async function putObject(tx: Tx, path: string, data: Buffer, mime: string): Promise<void> {
  await tx`select realisasi.storage_put(${path}::text, ${mime}::text, ${data}::bytea)`;
}

export async function getObject(tx: Tx, path: string): Promise<{ data: Buffer; mime: string; size: number }> {
  const rows = await tx<{ data: Buffer; mime: string; size_bytes: number }[]>`
    select data, mime, size_bytes from realisasi.storage_get(${path}::text)`;
  const row = rows[0];
  if (!row) {
    // storage_get raises FILE_NOT_FOUND itself; this guards an empty result set.
    throw Object.assign(new Error('FILE_NOT_FOUND: Berkas tidak ditemukan.'), { detail: '' });
  }
  return { data: row.data, mime: row.mime, size: row.size_bytes };
}

/** '/api/files/' + path with each segment URI-encoded. */
export function fileHref(path: string): string {
  return '/api/files/' + path.split('/').map(encodeURIComponent).join('/');
}
