# Frontend review — app/, components/, lib/ (TypeScript · React · a11y)

Reviewers: ECC `typescript-reviewer` + `react-reviewer` + `a11y-architect` (one combined pass).
Scope: whole tree (not a diff). Spec references are to `docs/spec/Design.md` and `docs/CONTRACTS.md`.

## Checks run

| Check | Result |
|---|---|
| `npx tsc --noEmit` | pass (0 errors) |
| `npm run lint` (`eslint .`, next/core-web-vitals + next/typescript, so `react-hooks` is on) | pass (0 problems). There are 2 `exhaustive-deps` disables: `participants-editor.tsx:252` has a justification, `column-filters.tsx:64` has one too, but the code behind it is a real bug (see M-2). `eslint-plugin-jsx-a11y` only runs the subset bundled in next/core-web-vitals. |
| `npx vitest run` | pass (9 files, 62 tests) |
| `next build` (scratch copy) | pass. No RSC serialization or boundary errors. |
| Runtime smoke (`next start`, DB `sim_realisasi_ts`, seeded) | 20 pages × 5 roles all returned 200. No error boundaries rendered. |
| DB JSON vs TS types | I emitted the real RPC outputs as typed literals and ran `tsc` on them (`dashboard`, `activity_detail` ×2, `kpi_drilldown` 1.1/1.19.24/1.19.S8, `snapshot_list`, `agreement_realization`, `participant_version`). There is **one** mismatch (L-12). The `as DashboardData` / `as ActivityDetail` casts in `lib/realisasi/queries/*` are otherwise accurate. |
| Server/client boundary | Clean. No client file imports `lib/db`, `lib/session` or `queries/*` values (type-only imports only). The `lib/storage` value import from the client (`MAX_FILE_BYTES`) only uses `import type { Tx }`. All `'use server'` actions call `requireUser()` and zod-validate their inputs (settings actions also gate on `settings.manage`). |

Counts: **HIGH 2 · MEDIUM 9 · LOW 17**

---

## HIGH

### H-1 Autosave race: edits made during an in-flight save are marked "Tersimpan" and never saved
`components/realisasi/wizard/detail-form.tsx:236-266` (with `:222-227`)

`persistDraft` sets `dirtyRef.current = false` and `save.setSaved()` when **any** save completes. It does not check whether the user edited again while the request was in flight. Scenario:
1. The user types and the 1.5 s debounce fires save A.
2. While A is pending, the user edits "Deskripsi". `set()` sets `dirtyRef = true` and arms a new timer.
3. If the timer fires while A is still pending, `persistDraft` returns `null` because of `savingRef`, and the edit is dropped silently.
4. When A resolves, it overwrites `dirtyRef = false` and shows **"Tersimpan sebagai draf · 10:42"**. The `setSaved()` context change re-runs the effect, but `dirtyRef` is now false, so nothing is rescheduled.

The last edit is lost and the indicator says it was saved. The same `savingRef` early return also makes a click on **Lanjut** / **Simpan Draf** during an autosave do nothing, with no feedback (`onSaveDraft` gets `null` and returns).

**Fix:** keep a monotonically increasing `editSeq` ref. Increment it in `set()`, capture it at save start, and on success clear dirty and call `setSaved()` only if `editSeq` is unchanged. Otherwise reschedule a save of the latest state. Do not drop a save while one is running. Either queue it (`pendingRef = latestPayload`, run it after the current one finishes) or await the in-flight promise inside `persistDraft` so manual "Lanjut" saves after the autosave instead of being ignored.

**Resolution (fixed, app fix):** all saves go through `createDraftSaver` (`lib/realisasi/save-queue.ts`): one save at a time, later requests are queued (never dropped) and coalesced, the payload is read from a state ref when the save starts, and an edit-sequence counter marks the draft "Tersimpan" only when no edit happened after the saved snapshot. Manual "Simpan Draf"/"Lanjut" wait behind a running autosave. A save queued behind the first create reuses the new draft id. Tests: `lib/realisasi/save-queue.test.ts` (race reproduced and fixed) and `e2e/autosave.spec.ts` H-1 (holds the first autosave POST, edits, checks there is no second POST and no "Tersimpan" until it lands, then reloads and finds both edits).

### H-2 Participant editor commits stale arrays after `await`, so concurrent changes are lost and persisted that way
`components/realisasi/wizard/participants-editor.tsx:264-300, 302-331, 335-340, 342-356`

`addStudents`, `addStaff` and `uploadTranscript` await network I/O and then call `commit([...students, ...added], staff)` or `patchStudent(...)`. These use the `students` / `staff` captured in the render where the handler **started**. `commit` both replaces state and calls `saveParticipants`, which replaces the whole draft set in the DB. Scenarios:
- An inbound activity with two inbound students. The user drops transcript A, then transcript B, before A's upload finishes. A's completion writes `transcript_path` for row A using the old array. B's completion uses its own old array, which has no path for A, so **transcript A is erased** in state and in the DB. The checklist then fails `R17_INBOUND_DATA_REQUIRED` with no visible cause.
- The user clicks **Cek NRP** with 150 NRPs (slow lookup), then removes a staff row or runs **Cek ID Pegawai** in the other panel. Whichever request finishes last restores the other panel's old rows and persists them.
- Typing in an inbound row's "Institusi asal" while a transcript upload is pending: the upload completion reverts the typed text.

**Fix:** never build the next set from closure state after an `await`. Use functional updates (`setStudents(prev => [...prev, ...added])`, `setStudents(prev => prev.map(...))`). Persist from a `rowsRef` that is updated in the same reducer, for example a `useReducer` plus an effect that calls `persist(latest)` with the existing `seq` guard. The debounced tick effect (`:247-253`) already reads current state, so route every mutation through it.

**Resolution (fixed, app fix):** the editor keeps one source of truth in a ref and applies every mutation as an action through the pure `participantsReducer` (`components/realisasi/wizard/participants-model.ts`), so late lookup or upload results merge into the latest rows (duplicates are re-checked at apply time). Persistence goes through the same serialized saver and reads the latest rows when it starts. Tests: `participants-model.test.ts` (overlapping transcript uploads, slow lookup vs. removal, typing vs. upload, duplicate lookups) and `e2e/autosave.spec.ts` H-2 (a delayed NRP lookup no longer restores a removed staff row, verified after reload).

---

## MEDIUM

### M-1 Pending debounced or unsaved edits are dropped on navigation, submit and commit (no flush)
- `detail-form.tsx:259-266`: the cleanup only `clearTimeout`s. Clicking a Stepper link (`ui/stepper.tsx:157`) or "Kembali" within 1.5 s of typing discards the edit. There is also no `beforeunload` guard.
- `participants-editor.tsx:247-253`: same, with an 800 ms debounce for inbound text fields. `WizardNav` "Lanjut" (`wizard-nav.tsx:92`) navigates immediately.
- `participant-commit.tsx:264-281, 314`: "Simpan & setujui versi baru" is enabled while an inbound edit is still debounced or saving. `commit_participant_edit` then approves the DB draft without the last edit.
- `app/realisasi/kegiatan/[id]/revisi/page.tsx:102-136`: in revision mode, `DetailForm` saves only on "Simpan perubahan Detail". "Ajukan ulang" in `SubmitPanel` resubmits the stored data and silently discards unsaved Detail edits.

**Fix:** expose `flush(): Promise<void>` and a `dirty` flag from both editors through a context (the `SaveStatusProvider` is the natural place). Await `flush()` before router navigation, submit and commit, and disable the "Ajukan ulang" / commit buttons while `dirty || saving`. Add a `beforeunload` handler while dirty.

**Resolution (fixed, app fix):** `SaveStatusProvider` is also a flush hub: editors `registerFlush()`, and the stepper links, WizardNav (Kembali / Simpan Draf / Lanjut), SubmitPanel and the IO participant commit `await flush()` first. If a pending edit cannot be saved (an invalid field), navigation asks for confirmation and submit/commit stay put. Revision-mode Detail edits register a blocker that disables "Ajukan ulang" with a reason (the revision page is wrapped in the provider). A `beforeunload` prompt is armed while dirty or saving, and unmounting with a debounced edit saves it. Commit is disabled while participant edits are pending. Test: `e2e/autosave.spec.ts` M-1.

### M-2 Kegiatan search debounce uses a stale `filters` closure and wipes filters chosen in the meantime
`components/realisasi/list/column-filters.tsx:55-65`

The effect depends only on `[q]`. Its timer calls the `apply` captured when `q` changed, and that `apply` spreads the **old** `filters`. Scenario: type "seminar" and pick "Jenis = Joint Research" within 400 ms. The URL gets `type_id`, then the timer calls `router.replace` with `{...oldFilters, q}` and drops `type_id`. The eslint-disable hides exactly this problem.

**Fix:** keep the latest `filters` in a ref (`filtersRef.current = filters` during render) and build `next` from `filtersRef.current` inside the timeout. Alternatively, build the URL from `useSearchParams()` at fire time.

**Resolution (fixed, app fix):** `useFilterNavigation` builds the next URL from a `latest` ref that includes patches whose navigation has not landed yet, so the debounced search keeps filters chosen meanwhile.

### M-3 KPI 1.19.S8 "N kegiatan belum dilaporkan" link opens a register that does not match N
`app/realisasi/page.tsx:170-180`

The card counts only **international, unmatched** register entries **within the period window** (and the unit, when unit-scoped), per CONTRACTS §4.2. The link is a bare `/realisasi/kegiatan-diketahui?status=unmatched`. I confirmed this on seeded data: on `?ay=1&period=full` the card says **"0 kegiatan belum dilaporkan"**, and the link lists **2** entries (Sept 2026, AY 2026/2027). Domestic entries would also show up.

**Fix:** link with the same scope the card uses: `?status=unmatched&intl=1&from=<period.window_start>&to=<period.window_end>` (+ `unit_id=<scope.unit_id>`). `parseKnownFilters` already supports all of these. Or link to `/realisasi/laporan?report=kpi&kpi=1.19.S8&bucket=unmatched_known&…`, which uses the identical server-side rule.

**Resolution (fixed, app fix):** the S8 link now carries the card's scope: `status=unmatched&intl=1&from=<window_start>&to=<window_end>` (+ `unit_id` when unit-scoped).

### M-4 Combobox selection state is never exposed to assistive tech (Kerja sama picker, Unit lain)
`components/ui/combobox.tsx:230-238`

`aria-selected={isSelected}` on `CommandItem` is overwritten. cmdk spreads consumer props first and then sets `"aria-selected": !!highlighted` (verified in `node_modules/cmdk/dist/index.mjs`). The check icon is `aria-hidden`. A screen-reader user moving through the agreement list hears "selected" for whichever item is highlighted, and nothing tells them which agreements are already chosen. This fails WCAG 4.1.2 (Name, Role, Value) on a required wizard field.

**Fix:** use `role="option"` semantics that survive cmdk. Either put the state in the accessible name (`<span className="sr-only">{isSelected ? 'terpilih, ' : ''}</span>`), or render a `role="checkbox" aria-checked` element inside the item. Keep `aria-multiselectable` on the list.

**Resolution (fixed, app fix):** the chosen state is part of the option's accessible name (sr-only ", terpilih"), because cmdk overwrites `aria-selected`. `aria-multiselectable` is kept.

### M-5 "Realisasi % per Unit" chart draws units with no active agreements as 0,0 %
`components/realisasi/dashboard/charts.tsx:325-329, 382`

`value: d.pct ?? 0`. When `denominator = 0`, `pct` is `null` per CONTRACTS §4.3 (`nullif(d,0)`). The bar and its label then read "0,0%", which is indistinguishable from a unit that realized none of its agreements. The table view correctly shows "–". This misreports a KPI.

**Fix:** filter out rows with `pct === null` from the bar data, or render them with a "–" label and no bar. Add an `extra` of "tidak ada kerja sama aktif".

**Resolution (fixed, app fix):** units with `pct = null` get no bar; they are listed under the chart as "Tidak ada kerja sama aktif (–)".

### M-6 Invalid "SKS diakui" input is silently discarded
`components/realisasi/wizard/detail-form.tsx:125, 135`

`Number('2,5,0'.replace(',', '.'))` returns `NaN`, which becomes `sks_recognized: null`, so the form validates and saves. The user's value disappears with no error. The same happens for "abc" or "3 sks".

**Fix:** keep the raw string through validation and emit a field error "SKS harus berupa angka" when it is non-empty and not a finite number (`/^\d+([.,]\d+)?$/`).

**Resolution (fixed, app fix):** a non-empty SKS value must match `^\d+([.,]\d+)?$`. Otherwise the field shows "SKS harus berupa angka", and autosave skips the invalid state instead of saving `null`.

### M-7 Every autosave and participant save re-renders the whole wizard page on the server
`lib/realisasi/actions/submission.ts:58, 107` (also `:85`, and `revision-workspace.tsx:175` adds an extra `router.refresh()`)

`revalidatePath('/realisasi', 'layout')` inside a server action makes Next return a fresh RSC payload for the current route in the action response. On the wizard that means `getFormOptions`, `activity_detail`, `nav_counts` and the layout for **every** 1.5 s autosave and every participant edit. That is wasted DB work and slower autosave round-trips, which also widens the H-1 window. All `/realisasi` pages are `force-dynamic`, so there is no cached data to invalidate.

**Fix:** drop `revalidatePath` from `saveActivityDraft` and `saveParticipants`. Keep it for state-changing actions (submit, delete, verification). In `RevisionWorkspace`, refresh only once after the final save, or only to update the checklist.

**Resolution (fixed, app fix):** `saveActivityDraft` and `saveParticipants` no longer call `revalidatePath`. `RevisionWorkspace` refreshes once, after a participant save that leaves nothing queued.

### M-8 Queue rows after the 50th cannot be expanded or verified in place
`app/realisasi/verifikasi/kemitraan/page.tsx:20,29` and `mobilitas/page.tsx:98,113`; `components/realisasi/verify/queue-table.tsx:304`

Only the first 50 rows get `expanded` content. Rows 51 and later still show an expand button, which reveals "Detail tidak tersedia." and no actions. Design §3.5 requires actions in the expanded row. Prefetching 50 full `activity_detail` payloads into the RSC response is also heavy.

**Fix:** lazy-load the expanded panel per row. Use a server action or route that returns detail on first expand, or render the expanded content via `<Suspense>` per row. At minimum, hide the toggle and link to the detail page for rows without prefetched content.

**Resolution (fixed, app fix):** queue pages render the first 20 rows' panels with the page (`QUEUE_PREFETCH`, `components/realisasi/verify/queue-panels.tsx`). Any later row loads the same Detail + preview + actions panel on first expand, through the server action `loadQueuePanel` (role-checked). If loading fails, the row shows a link to the detail page.

### M-9 Status tooltips use the `title` attribute only (Design §6 "badge text + dot + tooltip")
`components/realisasi/status-badge.tsx:47, 61, 85, 98`; `kpi-tables.tsx:26`; `activity-table.tsx:14,29`

`title` tooltips on non-focusable `<span>`s are not available to keyboard or touch users, and screen readers read them inconsistently. "Di luar lingkup" depends on its tooltip to explain itself ("grey outline with info tooltip"). The flag's meaning (`FLAG_DESCRIPTION`) is therefore not available to keyboard users (WCAG 1.3.1 / 2.1.1).

**Fix:** use the existing Radix `SimpleTooltip` with a focusable trigger (`tabIndex={0}` + `aria-describedby`), or append the description as `sr-only` text for screen readers and use a focusable info icon for sighted keyboard users.

**Resolution (fixed, app fix):** a new focusable `Hint` (Radix tooltip plus an sr-only description) replaces `title` on StatusBadge, FlagPill, SlaChip and the late-addition pill. Inside the Duplikat? link the pill is plain, and the link carries the description.

---

## LOW

1. **Design §3.6/§2 "Duplikat? links to candidate"**: `activity-table.tsx:70-76` links to the generic `/realisasi/verifikasi/duplikat` list, not the candidate. Link to `/realisasi/kegiatan/<id>` (which shows the candidates via `DuplicateActions`) or add `?activity=<id>` filtering.
   - **Resolution:** fixed: the Duplikat? pill links to `/realisasi/kegiatan/<id>`, whose page lists the candidates.
2. **Design §3.5 "Detail + IA/IR preview side by side"**: `verify/file-preview.tsx:17-50` shows IA **or** IR in tabs. The tablist also lacks arrow-key navigation (ARIA tabs pattern). Render the two iframes in a 2-column grid on xl, or implement roving `tabIndex` + ArrowLeft/Right.
   - **Resolution:** fixed (keyboard part): the IA/IR tablist has roving `tabIndex` plus ArrowLeft/Right/Home/End. Detail and preview already sit side by side on xl. The two PDFs stay in tabs, because two iframes next to the Detail would be too narrow.
3. **Autosave indicator empty on load**: `app/realisasi/kegiatan/baru/page.tsx:258` never passes `savedAt` to `WizardShell`, so an existing draft shows no "Tersimpan sebagai draf · HH:MM" (Design §3.3) until the next save. Pass `detail.updated_at` (or the latest log `created_at`).
   - **Resolution:** fixed: the wizard passes `savedAt` (the draft's `updated_at` from `v_activity_list`) to `WizardShell`.
4. **Raw identifier in Riwayat**: `lib/realisasi/status.ts:196-209` `LOG_ACTION_LABEL` has no `dismiss_duplicate` entry. SQL writes it (`0009`, amendment 9), so the log shows "dismiss_duplicate". Add `dismiss_duplicate: 'Ditandai bukan duplikat'`.
   - **Resolution:** fixed: added `dismiss_duplicate: 'Ditandai bukan duplikat'`.
5. **Wrong copy for employee lookup errors**: `participants-editor.tsx:150,153` always says "Layanan data mahasiswa tidak dapat dihubungi", including for `/api/lookup/employees`. Pass the message per endpoint ("data pegawai").
   - **Resolution:** fixed: `postJson` takes the service name ("data mahasiswa" / "data pegawai").
6. **English parse errors shown to users**: `participants-editor.tsx:350` and `:668` call `await res.json()` without `.catch`. A non-JSON error body (e.g. a proxy 413/502 HTML page) surfaces "Unexpected token '<'…". Use `res.json().catch(() => ({}))` as `files-editor.tsx:69` does.
   - **Resolution:** fixed: transcript and template responses use `res.json().catch(() => ({}))`.
7. **Partial multi-file upload leaves a stale list**: `files-editor.tsx:63-81`. If file 3 of 3 fails, files 1–2 are stored but `router.refresh()` only runs on full success. The UI does not show them and the user may re-upload duplicates. Call `router.refresh()` in `finally`.
   - **Resolution:** fixed: `router.refresh()` runs in `finally` whenever at least one file was stored.
8. **FileDrop does not expose invalid state**: `ui/file-drop.tsx:85-88` maps `aria-invalid` to `data-invalid` only. The required-transcript error is visual only. Forward `aria-invalid` to the `<button>`.
   - **Resolution:** fixed: `aria-invalid` is not allowed on `role=button` (jsx-a11y), so the invalid state is announced as sr-only text inside the button ("wajib diisi, belum ada berkas").
9. **Error-summary link targets**: `detail-form.tsx:369` links to `#f-${target}`. There is no element `#f-mode` (radios are `f-mode-<m>`), and `#f-document_ids` is a combobox button inside `AgreementPicker` that only exists when rendered. Map targets to focusable ids and focus them on click (`href` alone does not move focus into a Radix trigger reliably).
   - **Resolution:** fixed: summary links target `f-mode-<current>` for Moda, and on click they focus the real control (or its first focusable descendant), falling back to the section heading.
10. **Period segmented control misuses ARIA**: `dashboard/period-selector.tsx:73-90` puts `role="radio"` on `<Link>`s with three tab stops and no arrow keys. Either use links with `aria-current` or a real radio group (`RadioGroup` from ui) that navigates `onValueChange`.
   - **Resolution:** fixed: the period control is a `<nav>` of links with `aria-current="page"`.
11. **Notification bell can spin forever / unhandled rejection**: `notification-bell.tsx:29-35`. If `listNotifications` rejects (network or deploy skew), `setLoading(false)` never runs. At `:58` the `.then` has no `.catch`. Wrap both in `try/finally` / add `.catch(() => toast.error(...))`.
   - **Resolution:** fixed: `try/finally` around `listNotifications`, and `.catch` on mark-read.
12. **`ChecklistItem` type is missing `fields`**: the real `activity_detail().checklist` `R07_REQUIRED_FIELD` item carries `"fields": [...]` (WP-DB amendment 8; tsc on the real JSON failed with TS2353). `SubmitPanel` therefore cannot tell the user *which* Detail fields are missing. Add `fields?: string[]` and render them through `FIELD_LABEL`.
   - **Resolution:** fixed: `ChecklistItem.fields?: string[]`. SubmitPanel lists them with the human field labels.
13. **Raw storage path shown as "sebelumnya"**: `verify/participant-diff-table.tsx:176` + `Cell :69`. For a changed transcript the previous value is printed as `realisasi-transcripts/<uuid>/v1/...`. Show "Transkrip diganti" instead of the path.
   - **Resolution:** fixed: a changed transcript shows "Transkrip diganti" / "Transkrip ditambahkan" instead of the storage path.
14. **Stale dialog state in Pengaturan**: `settings/calendar-manager.tsx:242, 299`. Semester and year dialogs initialise `useState` once, so cancelled edits reappear on reopen, and props updated after `router.refresh()` are ignored. Reset `v` in `onOpenChange(true)` from props.
   - **Resolution:** fixed: the semester and year dialogs reset their values from props on open.
15. **Badge count `aria-label` on a span**: `participants-editor.tsx:689`. `aria-label` on a non-interactive `<span>` is ignored by most screen readers, so the panel summary reads only "Mahasiswa PETRA 3". Use visible/sr-only text ("3 baris").
   - **Resolution:** fixed: the count badge has visible text plus sr-only " baris", with no `aria-label` on the span.
16. **Date filters navigate on partial input**: `list/column-filters.tsx:152-170`. Typing a year in a date input emits intermediate valid dates (e.g. `0002-05-01`) and each triggers `router.replace` plus a server query. Apply on `blur`/Enter, or debounce like `q`.
   - **Resolution:** fixed: date filters apply on blur, on Enter or after an 800 ms pause; years before 1900 (partial input) are ignored.
17. **`formatNumber` on non-integers**: `lib/realisasi/format.ts:85-91` uses `String(n)`, so `0.1+0.2` gives "0,30000000000000004" and `1e21` gives "1e+21". KPI values are integers today, so this has no current impact. Use `toLocaleString`-free fixed-point formatting (e.g. `Number(n.toFixed(6))`), or document integer-only use.
   - **Resolution:** fixed: fixed-point formatting (max 6 decimals, BigInt for ≥ 1e21). Test in `format.test.ts`.

Notes (not counted):
- `components/realisasi/activity/convert.ts:40` hard-codes `auto_renewed: false`, so a selected auto-renewed agreement briefly shows its old end date before the lookup returns.
- `role="toolbar"` on the activity action bar (`activity-header.tsx:50`) implies roving-focus keyboard behaviour that isn't implemented. A `role="group"` would be accurate. **Resolution:** changed to `role="group"`.
- Charts are SVG without text alternatives, but each card offers "Lihat sebagai tabel", which satisfies 1.1.1 if users can find it.

---

## What looked good
- Dates: `'YYYY-MM-DD'` is never put through `new Date()` for display, timestamps are converted deterministically to WIB, and `lib/db.ts` parsers keep `date` as a string. No hydration-sensitive `Intl` formatting.
- Status language matches Design §2 exactly (labels, tones). Track chips have text + dot + sr-only status. SLA chips carry a level in text.
- Dialogs are Radix (focus trap, Esc, labelled close "Tutup"). Verification dialogs require notes/reasons client-side and map server error codes to inline fields. The queue toggle is a real `<button>` with `aria-expanded/controls`.
- Server actions are consistently `requireUser → zod → withUser → RPC → runAction`, and Next control errors are rethrown.
