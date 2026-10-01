import { afterEach, describe, expect, it, vi } from 'vitest';
import { ERROR_MESSAGES, appError, errorResponse, httpStatusFor, isNextControlError, parseDbError, runAction } from './errors';

function pgError(message: string, detail = '', code = 'P0001') {
  return Object.assign(new Error(message), { code, detail, severity: 'ERROR' });
}

afterEach(() => vi.restoreAllMocks());

describe('parseDbError', () => {
  it('extracts code and Indonesian message', () => {
    expect(parseDbError(pgError('R15_NOT_DRAFT: Hanya draf yang dapat dihapus.'))).toEqual({
      code: 'R15_NOT_DRAFT',
      message: 'Hanya draf yang dapat dihapus.',
    });
  });

  it('parses JSON detail', () => {
    const detail = JSON.stringify({ rows: [{ section: 'internal', index: 0, id: 'Z99999999', code: 'R16_NRP_NOT_FOUND' }] });
    const err = parseDbError(pgError('R16_NRP_NOT_FOUND: NRP tidak ditemukan di data BAAK: Z99999999.', detail));
    expect(err.code).toBe('R16_NRP_NOT_FOUND');
    expect(err.detail).toEqual({ rows: [{ section: 'internal', index: 0, id: 'Z99999999', code: 'R16_NRP_NOT_FOUND' }] });
  });

  it('keeps multi-line messages and non-JSON detail as text', () => {
    const err = parseDbError(pgError('VALIDATION_INVALID: Nilai tidak valid:\nurl', 'not json'));
    expect(err).toEqual({ code: 'VALIDATION_INVALID', message: 'Nilai tidak valid:\nurl', detail: 'not json' });
  });

  it('maps unknown errors to INTERNAL and logs them', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    expect(parseDbError(new Error('connection refused'))).toEqual({ code: 'INTERNAL', message: ERROR_MESSAGES.INTERNAL });
    expect(parseDbError('boom')).toEqual({ code: 'INTERNAL', message: ERROR_MESSAGES.INTERNAL });
    expect(spy).toHaveBeenCalledTimes(2);
  });

  it('maps insufficient privilege and malformed input SQLSTATEs', () => {
    expect(parseDbError(pgError('permission denied for table activities', '', '42501')).code).toBe('AUTH_FORBIDDEN');
    expect(parseDbError(pgError('invalid input syntax for type uuid: "abc"', '', '22P02')).code).toBe('BAD_REQUEST');
  });

  it('round-trips appError', () => {
    expect(parseDbError(appError('RATE_LIMITED'))).toEqual({ code: 'RATE_LIMITED', message: ERROR_MESSAGES.RATE_LIMITED });
    expect(parseDbError(appError('BAD_REQUEST', 'Tanggal wajib diisi.', { fields: ['start'] }))).toEqual({
      code: 'BAD_REQUEST',
      message: 'Tanggal wajib diisi.',
      detail: { fields: ['start'] },
    });
  });
});

describe('httpStatusFor', () => {
  it.each([
    ['AUTH_REQUIRED', 401],
    ['AUTH_FORBIDDEN', 403],
    ['FILE_FORBIDDEN', 403],
    ['NOT_FOUND', 404],
    ['FILE_NOT_FOUND', 404],
    ['RATE_LIMITED', 429],
    ['INTERNAL', 500],
    ['R07_IA_REQUIRED', 400],
    ['BAD_REQUEST', 400],
  ])('%s → %i', (code, status) => {
    expect(httpStatusFor(code)).toBe(status);
  });
});

describe('runAction', () => {
  it('wraps success', async () => {
    await expect(runAction(async () => 42)).resolves.toEqual({ ok: true, data: 42 });
  });

  it('wraps business errors', async () => {
    const res = await runAction(async () => {
      throw pgError('R27_NOTE_REQUIRED: Catatan revisi wajib diisi.');
    });
    expect(res).toEqual({ ok: false, code: 'R27_NOTE_REQUIRED', message: 'Catatan revisi wajib diisi.' });
  });

  it('rethrows Next.js redirect / notFound control errors', async () => {
    const redirectErr = Object.assign(new Error('NEXT_REDIRECT'), { digest: 'NEXT_REDIRECT;replace;/login;307;' });
    expect(isNextControlError(redirectErr)).toBe(true);
    await expect(
      runAction(async () => {
        throw redirectErr;
      }),
    ).rejects.toBe(redirectErr);
    expect(isNextControlError(new Error('x'))).toBe(false);
  });
});

describe('errorResponse', () => {
  it('returns JSON with the mapped status', async () => {
    const res = errorResponse(pgError('FILE_FORBIDDEN: Anda tidak memiliki akses ke berkas ini.'));
    expect(res.status).toBe(403);
    await expect(res.json()).resolves.toEqual({ code: 'FILE_FORBIDDEN', message: 'Anda tidak memiliki akses ke berkas ini.' });
  });
});

describe('ERROR_MESSAGES', () => {
  it('covers every contract code', () => {
    const codes = [
      'AUTH_REQUIRED', 'AUTH_FORBIDDEN', 'NOT_FOUND', 'STATE_INVALID', 'TRACK_NOT_PENDING', 'VALIDATION_REQUIRED',
      'VALIDATION_INVALID', 'END_BEFORE_START', 'R04_AGREEMENT_NOT_VALID', 'R07_REQUIRED_FIELD', 'R07_AGREEMENT_REQUIRED',
      'R07_IA_REQUIRED', 'R07_IR_REQUIRED', 'R08_END_AFTER_TODAY', 'R09_NO_ACADEMIC_YEAR', 'R11_PARTICIPANTS_REQUIRED',
      'R12_OUTBOUND_STUDENT_REQUIRED', 'R12_INBOUND_STUDENT_REQUIRED', 'R13_FILE_TOO_LARGE', 'R13_FILE_TYPE',
      'R14_UNIT_NOT_ALLOWED', 'R15_NOT_DRAFT', 'R16_NRP_NOT_FOUND', 'R16_SECTION_MISMATCH', 'R17_NOT_INBOUND',
      'R17_INBOUND_DATA_REQUIRED', 'R19_EMPLOYEE_NOT_FOUND', 'R21_NEW_VERSION_REQUIRED', 'R22_DUPLICATE_NRP',
      'R22_DUPLICATE_EMPLOYEE', 'R26_REASON_REQUIRED', 'R26_NOTE_REQUIRED', 'R27_NOTE_REQUIRED', 'R29_EDIT_FORBIDDEN',
      'R34_UNLINK_ADMIN_ONLY', 'DUP_SAME_GROUP', 'R53_ALREADY_MATCHED', 'R54_NO_UNIT', 'R54_NUDGE_TOO_SOON',
      'R55_ALREADY_FROZEN', 'R55_NO_SEMESTER', 'R58_REASON_REQUIRED', 'R58_NOT_LIVE', 'SETTINGS_INVALID',
      'CAL_INVALID_RANGE', 'FILE_FORBIDDEN', 'FILE_NOT_FOUND', 'RATE_LIMITED', 'INTERNAL', 'BAD_REQUEST',
    ];
    for (const c of codes) expect(ERROR_MESSAGES[c], c).toBeTruthy();
  });
});
