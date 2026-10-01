/**
 * Decompression-bomb guard for uploaded .xlsx files (security review M-1). SERVER ONLY (node:zlib).
 *
 * An .xlsx is a zip archive. Before ExcelJS inflates it in memory, this walks the zip central
 * directory and inflates every entry with a hard output cap (`maxOutputLength`), so neither the
 * declared sizes nor a lying archive can make the server allocate more than `maxTotalBytes`.
 */
import { inflateRawSync } from 'node:zlib';

export interface ZipLimits {
  /** Max number of entries in the archive. */
  maxEntries: number;
  /** Max total uncompressed bytes over all entries. */
  maxTotalBytes: number;
}

export const XLSX_TEMPLATE_LIMITS: ZipLimits = { maxEntries: 64, maxTotalBytes: 5 * 1024 * 1024 };

export type ZipCheck = { ok: true; totalBytes: number; entries: number } | { ok: false; reason: 'not_zip' | 'too_many_entries' | 'too_large' | 'unsupported' };

const EOCD_SIG = 0x06054b50;
const CEN_SIG = 0x02014b50;
const LOC_SIG = 0x04034b50;

function findEocd(buf: Buffer): number {
  // EOCD is 22 bytes + up to 65,535 bytes of comment at the end of the file.
  const min = Math.max(0, buf.length - 22 - 0xffff);
  for (let i = buf.length - 22; i >= min; i--) if (buf.readUInt32LE(i) === EOCD_SIG) return i;
  return -1;
}

/** Validates the archive; never inflates more than `limits.maxTotalBytes` in total. */
export function checkZip(buf: Buffer, limits: ZipLimits = XLSX_TEMPLATE_LIMITS): ZipCheck {
  if (buf.length < 22 || buf.readUInt32LE(0) !== LOC_SIG) return { ok: false, reason: 'not_zip' };
  const eocd = findEocd(buf);
  if (eocd < 0) return { ok: false, reason: 'not_zip' };
  const count = buf.readUInt16LE(eocd + 10);
  const cdOffset = buf.readUInt32LE(eocd + 16);
  if (count === 0xffff || cdOffset === 0xffffffff) return { ok: false, reason: 'unsupported' }; // zip64
  if (count > limits.maxEntries) return { ok: false, reason: 'too_many_entries' };

  let p = cdOffset;
  let total = 0;
  for (let n = 0; n < count; n++) {
    if (p + 46 > buf.length || buf.readUInt32LE(p) !== CEN_SIG) return { ok: false, reason: 'not_zip' };
    const method = buf.readUInt16LE(p + 10);
    const compressed = buf.readUInt32LE(p + 20);
    const declared = buf.readUInt32LE(p + 24);
    const nameLen = buf.readUInt16LE(p + 28);
    const extraLen = buf.readUInt16LE(p + 30);
    const commentLen = buf.readUInt16LE(p + 32);
    const local = buf.readUInt32LE(p + 42);
    p += 46 + nameLen + extraLen + commentLen;

    if (compressed === 0xffffffff || declared === 0xffffffff) return { ok: false, reason: 'unsupported' };
    if (total + declared > limits.maxTotalBytes) return { ok: false, reason: 'too_large' };
    if (local + 30 > buf.length || buf.readUInt32LE(local) !== LOC_SIG) return { ok: false, reason: 'not_zip' };
    const dataStart = local + 30 + buf.readUInt16LE(local + 26) + buf.readUInt16LE(local + 28);
    if (dataStart + compressed > buf.length) return { ok: false, reason: 'not_zip' };
    const data = buf.subarray(dataStart, dataStart + compressed);

    const budget = limits.maxTotalBytes - total;
    let size: number;
    if (method === 0) {
      size = data.length;
    } else if (method === 8) {
      try {
        // Inflate with a hard cap: a lying header cannot make this allocate more than `budget`.
        size = inflateRawSync(data, { maxOutputLength: Math.max(1, budget) }).length;
      } catch (e) {
        if (e instanceof RangeError || (e as { code?: string }).code === 'ERR_BUFFER_TOO_LARGE') return { ok: false, reason: 'too_large' };
        return { ok: false, reason: 'not_zip' };
      }
    } else {
      return { ok: false, reason: 'unsupported' };
    }
    total += size;
    if (total > limits.maxTotalBytes) return { ok: false, reason: 'too_large' };
  }
  return { ok: true, totalBytes: total, entries: count };
}
