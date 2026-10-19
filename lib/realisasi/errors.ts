/**
 * Error contract (CONTRACTS §2.9, §6.6). Business errors arrive from SQL as
 * `message = '<CODE>: <pesan>'`, `detail = '<json or empty>'` (SQLSTATE P0001).
 * Pure apart from `console.error` for unexpected errors; safe on server and client.
 */
import type { ActionResult } from '@/lib/realisasi/types';

export interface AppError {
  code: string;
  message: string;
  detail?: unknown;
}

/** Fallback Indonesian text per code (placeholders removed). */
export const ERROR_MESSAGES: Record<string, string> = {
  AUTH_REQUIRED: 'Sesi tidak valid. Silakan masuk kembali.',
  AUTH_FORBIDDEN: 'Anda tidak memiliki akses untuk tindakan ini.',
  NOT_FOUND: 'Data tidak ditemukan.',
  STATE_INVALID: 'Tindakan tidak dapat dilakukan pada status kegiatan saat ini.',
  TRACK_NOT_PENDING: 'Jalur verifikasi ini tidak sedang menunggu verifikasi.',
  VALIDATION_REQUIRED: 'Kolom wajib belum diisi.',
  VALIDATION_INVALID: 'Nilai tidak valid.',
  END_BEFORE_START: 'Tanggal selesai tidak boleh sebelum tanggal mulai.',
  R04_AGREEMENT_NOT_VALID: 'Kerja sama tidak berlaku pada tanggal kegiatan.',
  R07_REQUIRED_FIELD: 'Data wajib belum lengkap.',
  R07_AGREEMENT_REQUIRED: 'Pilih minimal satu kerja sama.',
  R07_IA_REQUIRED: 'Implementation Arrangement (PDF) wajib diunggah.',
  R07_IR_REQUIRED: 'Implementation Report (PDF) wajib diunggah.',
  R08_END_AFTER_TODAY: 'Kegiatan belum selesai. Tanggal selesai harus hari ini atau sebelumnya.',
  R09_NO_ACADEMIC_YEAR: 'Tanggal mulai berada di luar tahun akademik yang terdaftar. Hubungi Admin IO.',
  R11_PARTICIPANTS_REQUIRED: 'Jenis kegiatan ini wajib memiliki data peserta.',
  R12_OUTBOUND_STUDENT_REQUIRED: 'Kegiatan outbound wajib memiliki minimal satu mahasiswa PETRA.',
  R12_INBOUND_STUDENT_REQUIRED: 'Kegiatan inbound wajib memiliki minimal satu mahasiswa inbound.',
  R13_FILE_TOO_LARGE: 'Ukuran berkas melebihi 10 MB.',
  R13_FILE_TYPE: 'Format berkas tidak diizinkan.',
  R14_UNIT_NOT_ALLOWED: 'Anda hanya dapat mengajukan kegiatan untuk unit Anda sendiri.',
  R15_NOT_DRAFT: 'Hanya draf yang dapat dihapus.',
  R16_NRP_NOT_FOUND: 'NRP tidak ditemukan di data BAAK.',
  R16_SECTION_MISMATCH: 'NRP terdaftar pada kategori lain; pindahkan ke bagian yang sesuai.',
  R17_NOT_INBOUND: 'NRP bukan mahasiswa inbound (kategori inbound_exchange).',
  R17_INBOUND_DATA_REQUIRED: 'Mahasiswa inbound wajib memiliki institusi asal dan transkrip (PDF).',
  R19_EMPLOYEE_NOT_FOUND: 'ID pegawai tidak ditemukan di data SDM.',
  R21_NEW_VERSION_REQUIRED: 'Perbarui data peserta (versi baru) sebelum mengajukan ulang.',
  R22_DUPLICATE_NRP: 'NRP tercantum lebih dari sekali.',
  R22_DUPLICATE_EMPLOYEE: 'ID pegawai tercantum lebih dari sekali.',
  R26_REASON_REQUIRED: 'Pilih alasan penolakan.',
  R26_NOTE_REQUIRED: 'Catatan penolakan wajib diisi.',
  R27_NOTE_REQUIRED: 'Catatan revisi wajib diisi.',
  R29_EDIT_FORBIDDEN: 'Hanya tim IO terkait yang dapat mengubah kegiatan terverifikasi.',
  R34_UNLINK_ADMIN_ONLY: 'Hanya Admin IO yang dapat membatalkan tautan duplikat.',
  DUP_SAME_GROUP: 'Kedua kegiatan sudah berada dalam satu grup kegiatan.',
  R53_ALREADY_MATCHED: 'Entri ini sudah dicocokkan dengan kegiatan SIM.',
  R54_NO_UNIT: 'Entri belum memiliki unit; tentukan unit sebelum mengingatkan.',
  R54_NUDGE_TOO_SOON: 'Pengingat sudah dikirim; tunggu sebelum mengirim ulang.',
  R55_ALREADY_FROZEN: 'Snapshot untuk periode ini sudah dibekukan. Gunakan "Bekukan ulang".',
  R55_NO_SEMESTER: 'Kalender semester untuk periode ini belum diatur.',
  R55_BEFORE_CUTOFF: 'Snapshot belum dapat dibekukan: tanggal cutoff semester belum tercapai.',
  R58_REASON_REQUIRED: 'Alasan pembekuan ulang wajib diisi.',
  R58_NOT_LIVE: 'Snapshot ini sudah digantikan.',
  SETTINGS_INVALID: 'Pengaturan tidak valid.',
  CAL_INVALID_RANGE: 'Rentang tanggal kalender tidak valid atau tumpang tindih.',
  FILE_FORBIDDEN: 'Anda tidak memiliki akses ke berkas ini.',
  FILE_NOT_FOUND: 'Berkas tidak ditemukan.',
  RATE_LIMITED: 'Terlalu banyak permintaan. Coba lagi sebentar.',
  DB_BUSY: 'Server sedang sibuk. Coba lagi dalam beberapa saat.',
  INTERNAL: 'Terjadi kesalahan pada server.',
  BAD_REQUEST: 'Permintaan tidak valid.',
};

const CODE_RE = /^([A-Z0-9_]+): (.*)$/s;

function prop(e: unknown, key: string): unknown {
  return typeof e === 'object' && e !== null && key in e ? (e as Record<string, unknown>)[key] : undefined;
}

function parseDetail(raw: unknown): unknown {
  if (raw === undefined || raw === null) return undefined;
  if (typeof raw !== 'string') return raw;
  const trimmed = raw.trim();
  if (trimmed === '') return undefined;
  try {
    return JSON.parse(trimmed) as unknown;
  } catch {
    return trimmed;
  }
}

/**
 * Next.js control-flow errors (redirect(), notFound(), dynamic-usage bailouts) must be rethrown,
 * never converted into an ActionResult.
 */
export function isNextControlError(e: unknown): boolean {
  const digest = prop(e, 'digest');
  if (typeof digest !== 'string') return false;
  return digest.startsWith('NEXT_') || digest === 'DYNAMIC_SERVER_USAGE' || digest === 'BAILOUT_TO_CLIENT_SIDE_RENDERING';
}

/**
 * Pool exhaustion: Supavisor (`EMAXCONNSESSION` / `XX000` "max clients reached"), Postgres `53300`
 * too_many_connections, or a connect timeout. Temporary — the user should retry.
 */
export function isConnectionLimitError(e: unknown): boolean {
  const code = prop(e, 'code');
  const message = prop(e, 'message');
  if (code === '53300' || code === 'CONNECT_TIMEOUT') return true;
  return typeof message === 'string' && /EMAXCONN|max clients reached|too many (clients|connections)/i.test(message);
}

/** Maps any thrown value to an AppError. Unknown errors become INTERNAL (original is logged). */
export function parseDbError(e: unknown): AppError {
  const message = prop(e, 'message');
  if (typeof message === 'string') {
    const m = CODE_RE.exec(message);
    if (m && m[1] && m[2] !== undefined) {
      const detail = parseDetail(prop(e, 'detail'));
      const text = m[2].trim() || ERROR_MESSAGES[m[1]] || ERROR_MESSAGES.INTERNAL!;
      return detail === undefined ? { code: m[1], message: text } : { code: m[1], message: text, detail };
    }
  }
  const sqlState = prop(e, 'code');
  if (isConnectionLimitError(e)) {
    console.error('[parseDbError] database connection limit reached', e);
    return { code: 'DB_BUSY', message: ERROR_MESSAGES.DB_BUSY! };
  }
  if (sqlState === '42501') {
    // insufficient_privilege (RLS / missing grant) — still an access problem for the user.
    return { code: 'AUTH_FORBIDDEN', message: ERROR_MESSAGES.AUTH_FORBIDDEN! };
  }
  if (sqlState === '22P02' || sqlState === '22007' || sqlState === '22008') {
    // invalid_text_representation / datetime format: malformed id or date in the request.
    return { code: 'BAD_REQUEST', message: ERROR_MESSAGES.BAD_REQUEST! };
  }
  console.error('[parseDbError] unexpected error', e);
  return { code: 'INTERNAL', message: ERROR_MESSAGES.INTERNAL! };
}

export function httpStatusFor(code: string): number {
  switch (code) {
    case 'AUTH_REQUIRED':
      return 401;
    case 'AUTH_FORBIDDEN':
    case 'FILE_FORBIDDEN':
      return 403;
    case 'NOT_FOUND':
    case 'FILE_NOT_FOUND':
      return 404;
    case 'RATE_LIMITED':
      return 429;
    case 'DB_BUSY':
      return 503;
    case 'INTERNAL':
      return 500;
    default:
      return 400;
  }
}

/** Runs a server-side operation and returns an ActionResult (Next control errors are rethrown). */
export async function runAction<T>(fn: () => Promise<T>): Promise<ActionResult<T>> {
  try {
    return { ok: true, data: await fn() };
  } catch (e) {
    if (isNextControlError(e)) throw e;
    const err = parseDbError(e);
    return err.detail === undefined
      ? { ok: false, code: err.code, message: err.message }
      : { ok: false, code: err.code, message: err.message, detail: err.detail };
  }
}

/** JSON `{code, message, detail?}` response with the status from httpStatusFor. */
export function errorResponse(e: unknown): Response {
  const err = parseDbError(e);
  return Response.json(err, { status: httpStatusFor(err.code), headers: { 'Cache-Control': 'no-store' } });
}

/**
 * Builds a throwable in the same shape SQL errors have (`'<CODE>: <pesan>'` + detail), so app-side
 * checks flow through parseDbError/runAction/errorResponse exactly like database errors.
 */
export function appError(code: string, message?: string, detail?: unknown): Error & { detail?: unknown } {
  const text = message ?? ERROR_MESSAGES[code] ?? ERROR_MESSAGES.INTERNAL!;
  return Object.assign(new Error(`${code}: ${text}`), { detail });
}
