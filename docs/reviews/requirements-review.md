# Requirements review: SIM Realisasi mockup vs specification

**Reviewer:** ECC code-reviewer agent (requirements coverage and end-to-end behaviour)
**Date:** 2026-10-01 · **Code reviewed:** `git HEAD` 3e9b85d
**Specs used:** PRD.md §3–§9, Rules.md (authoritative), Design.md §1–§5, Architecture.md, CONTRACTS.md including both amendment sections.
**Out of scope:** deep SQL correctness, security and TS/React quality. Those are covered by `database-review.md` and `security-review.md`, and nothing listed there is repeated here.

## Method

- I traced each requirement to code (routes, components, actions, RPCs) using the CONTRACTS route map and capability model (`lib/session.ts` `can()`, `components/layout/nav.ts`).
- Runtime check: I copied `git HEAD` to the scratchpad, reset a fresh DB `sim_realisasi_cr` with `scripts/db-reset.sh`, and ran `next dev -p 3303`. I drove the app with Playwright (sandbox Chromium) as all 8 demo accounts, using the `demo_uid` cookie, which is the same mechanism as the login page buttons.
  - I took the UI routes for every role and checked the Forbidden/visible matrix.
  - I walked AT-03, AT-04 and AT-10 end to end, plus the full wizard: an inbound student with a transcript, a graduated-NRP warning, IA/IR upload, an evidence link, and submit.
  - I tested the Partnership queue (reject/revision dialogs), post-verification edit, co-units, the Known Activities register (create, suggestion, nudge) and manual freeze.
  - I ran the daily jobs from Pengaturan, and covered notifications, every Laporan report, all 12 export kinds (status codes per role, sheet names, Info sheet) and the SIM Kerjasama pages.
  - For AT-12 I downloaded the workbook through the on-screen "Unduh Excel" link and compared its rows with `list-total` for 8 filter combinations.
- Clean-up: dev server stopped, DB `sim_realisasi_cr` dropped.

**Status legend:** **done** = implemented and reachable by the right roles (verified at runtime unless marked *code*). **partial** = implemented with a gap. **missing** = not implemented. **wrong** = implemented contrary to spec.

---

## 1. Traceability matrix

### 1.1 Acceptance scenarios (Rules §11) and mockup acceptance (PRD §9)

| Req | Where | Status | Evidence |
|---|---|---|---|
| AT-01 two-unit duplicate: uni 12 / FTI 12 / Informatika 12 | `/realisasi` dashboard `?unit=`, `dashboard()` | done | Live 26/27: Informatika outbound 12, FTI 15 (12 from S-13 + 3 from S-16 after my AT-03), university uses the S-13/14 event group once (DB review covers the SQL) |
| AT-02 one student in two events = 2 | KPI 1.1 drill-down | done (DB-tested) | Drill-down lists S-15a and S-15b separately |
| AT-03 dual-track revision; v2 approved → verified; v1 read-only | `/kegiatan/[id]/revisi` → `RevisionWorkspace`; `/verifikasi/mobilitas` diff panel | done | As ua-fti: removed B12254341, added B12222426, then "Ajukan ulang". Status became Dalam Verifikasi with Mobilitas: Menunggu. As io.mobility: the queue diff showed 1 added / 1 removed with the v1 row note, then Setujui. Result: Terverifikasi; version selector `v1 (perlu revisi)` / `v2 (disetujui)`; v1 "hanya baca" with notes |
| AT-04 Jenis change in P revision resets Mobility | `/revisi` DetailForm `mode="revision"` + participants panel | done | As ua-fbe on S-17: Jenis → Student Outbound, saved, added D31240187, resubmitted. Result: Kemitraan Menunggu, Mobilitas Menunggu, and the mobility team got a notification |
| AT-05 grace exclusion (Ganjil 26/27) | `/laporan?report=kpi&kpi=1.19.24&bucket=grace_excluded` | done (frozen) / see I-1 | After freezing Ganjil 26/27, doc 902 (`044/MoA/PCU-USTUTT`) is listed as "Masa tenggang s.d. 2 Jun 2027". Live shows doc 901 as grace |
| AT-06 auto-renewed in denominator, not numerator | 1.19.24 drill-down / Realisasi per kerja sama | done | `002/MoU/PCU-UKDW` "otomatis diperpanjang · Belum terlaksana" |
| AT-07 renewal chain counted once; original doc numbers | 1.19.24 drill-down, `/kerjasama/dokumen/905/realisasi` | done | "Rantai: 018 → 015". The Kerjasama tab shows both activities, with "Dokumen saat kegiatan" 018 / 015 |
| AT-08 late addition after freeze | `/laporan?report=arsip&snapshot=…` | done | Ganjil 25/26 shows 0 tambahan susulan. Genap 25/26 lists RL-2026-0019 under "Tambahan susulan", with the S-05 post-freeze change |
| AT-09 S8 = reported ÷ (reported + unmatched) | Dashboard S8 card, register | done | 5 ÷ (5 + 2) at seed. After I added a register entry: 5 ÷ 8 = 62.5%, and the card says "3 kegiatan belum dilaporkan" |
| AT-10 unknown NRP blocks with row-level error | wizard step 2 `ParticipantsEditor` | done | Z99999999 gives a red "Tidak ditemukan" row and a `participants-blocking` alert, and `wizard-next` is disabled. B11200005 shows the amber "Sudah lulus (peringatan)". D31240187 in the inbound section shows "Bukan mahasiswa inbound" (blocking) |
| AT-11 viewer participant export → 403 | `/api/export/participants` | done | Viewer gets 403 JSON and io.partnership gets 403. io.mobility and ua-fti get 200. The report is hidden in Laporan for viewer and partnership |
| AT-12 export rows = on-screen rows; Info records filters | `ExportButton` + `/api/export/activities`, `known-activities` | done | 8 combinations matched exactly: status+unit_id, country, preset late/mine/this_semester, sla+semester, q+sort, partnership queue, and register unmatched. Info has a "Filter: …" row per filter |
| PRD §9.1–9.6 | — | done | Every item is demonstrable from seed data, except the AT-05 caveat in I-1 |

### 1.2 Functional requirements PRD §7.1 (activity form)

| Req | Where | Status | Notes |
|---|---|---|---|
| Nama, Jenis (shows the KPI-flag helper), Tanggal Mulai/Selesai, Moda | `components/realisasi/wizard/detail-form.tsx` | done | The helper reads e.g. "Dihitung sebagai mobilitas inbound — wajib isi peserta mahasiswa inbound …" |
| Selesai ≥ Mulai; Selesai ≤ today (R-08) | detail-form + `submission_checklist` | done | A future end date gives the inline message "baru dapat diajukan setelah 5 Okt 2026 (R-08)" |
| Semester/TA derived, read-only, live | `derived-period` | done | |
| Tempat (venue/city/country; online = platform) | detail-form | done | |
| Durasi derived | detail summary "(5 hari)" | done | |
| SKS, Sumber Dana (6 options), Deskripsi | detail-form | done | |
| Unit: submitter locked + co-units; io_admin picks unit | detail-form `lockedUnitId`, `unitEditable` | done | A co-unit added later (FSD on RL-2026-0020) gets read-only access with no action buttons (R-14) |
| Kerjasama picker: valid on activity dates, archived tagged, Mitra/Negara auto + snapshot, out-of-scope warning | `agreement-picker.tsx`, `/api/lookup/documents` | done | Options show doc · kind · partner · flag · "berlaku s.d." / "diperpanjang otomatis". 018 (archived) appears for Oct 2025 dates. The card shows the "tidak termasuk dalam Lingkup" warning |
| SDG chips (17) | `sdg-chips.tsx` | done | |
| Pembicara / Dosen Asing / Tamu rows | `external-persons.tsx` | done (*code* + UI) | |
| Peserta: PETRA students paste/Excel template, staff by ID, inbound (BAAK `inbound_exchange`, home institution, home number, country, transcript PDF) | `participants-editor.tsx`, `/api/template/peserta`, `/api/upload` | done | The template download returns 200 xlsx. Transcript upload gives "Lihat transkrip" |
| File: IA, IR required PDF, versioned; evidence files + links | `files-editor.tsx` | done | IA/IR show v1, size, Pratinjau and "Unggah versi baru". The evidence link was added |
| Autosave draft after Detail; autosave indicator | `save-status.tsx` | done | "Tersimpan sebagai draf · 23:36" |
| Step 4 review, checklist, late notice, Ajukan / Simpan Draf | `submit-panel.tsx` | done | S-23: "Batas pelaporan 13 Sep 2026 telah lewat — kegiatan akan ditandai Terlambat." Checklist noise: see L-3 |
| Delete draft (R-15) | `delete-draft-button.tsx` | done | "Hapus draf" appears on S-23 |

### 1.3 Queues & lists PRD §7.2 / Design §3.2, §3.5–3.7

| Req | Where | Status | Notes |
|---|---|---|---|
| Unit "My Activities" with filters, status, SLA, **deadline flags** | `/realisasi/kegiatan` | **partial** | Filters, status, SLA and Terlambat (late submission) are present. Drafts near or past the reporting deadline get no flag (M-2) |
| Revision inbox | Kegiatan nav badge `revision_inbox` + preset "Perlu tindakan saya" + revision banner "Perbaiki sekarang" | done | |
| Partnership queue, SLA-sorted, inline expand with Detail + IA/IR preview, Enter key | `/verifikasi/kemitraan`, `queue-table.tsx` | done | Sorted red → yellow → ok. Enter expands the row. The panel has an IA/IR iframe preview |
| Reject (reason select + note) / revision (note) dialogs | `action-dialog.tsx`, `partnership-actions.tsx` | done | An empty submit shows "Pilih alasan penolakan." / "Catatan penolakan wajib diisi." |
| Mobility queue, SLA-sorted, version diff, per-row notes, transcript side sheet | `/verifikasi/mobilitas`, `participant-diff-table.tsx`, `mobility-actions.tsx` | done | |
| Duplicate candidates: side-by-side card, score, Tautkan / Bukan duplikat | `/verifikasi/duplikat` | done | RL-2026-0028 vs 0030 at 86.0%. The detail page also has "Tautkan Duplikat", and io_admin has "Batalkan tautan" |
| Known Activities register: table, "+ Catat kegiatan" sheet, suggestions with Cocokkan, Ingatkan unit disabled + timestamp, Abaikan | `/kegiatan-diketahui` | done | A new entry gets suggestion RL-2026-0026 at 100%. After a nudge: "Diingatkan 1 Okt 2026 23:40 · kirim ulang mulai 15 Okt 2026", button disabled |
| All-activities list (IO/viewer) with per-column filters → export | list + `column-filters.tsx` | done | Viewer sees verified only ("Kegiatan yang sudah terverifikasi.") |
| Saved filter chips `Perlu tindakan saya`, `Terlambat`, `Semester ini` | `list-toolbar.tsx` | done | |
| List columns (Kode … Flags), track chips | `activity-table.tsx` | partial | Drafts show "Kemitraan: Menunggu" (L-1) |

### 1.4 Dashboard PRD §7.3 / Design §3.1

| Req | Status | Notes |
|---|---|---|
| Period selector: AY × Ganjil (YTD) / Setahun / Live; frozen lock badge "Dibekukan …" | done | |
| 4 KPI cards: sub-line, delta vs same period last year, click → drill-down; 1.19.24 "x dari y kerja sama" + "n dalam masa tenggang"; S8 "n kegiatan belum dilaporkan" → register?status=unmatched | done | The S8 link is plain text for roles without register access |
| Drill-down → activity detail | done | |
| Six charts (inbound/outbound per semester, per country, per unit, SDG heatmap, realization % per unit, top partners), each with ⋯ → Unduh Excel | done | All 6 headings are present, and the `chart` export returns 200 for viewer |
| Submitter view scoped to own unit + "Draf mendekati tenggat" | done | FSD: "RL-2026-0023 … Batas 13 Sep 2026 (lewat 18 hari)" |
| Late-addition banner | done | |

### 1.5 Exports PRD §7.4 (Excel, every report)

| # | Export | Kind / where | Status | Access verified |
|---|---|---|---|---|
| 1 | KPI summary + one sheet per KPI | `kpi-summary` (Laporan Ringkasan), `kpi-drilldown` (cards) | done | Sheets: Info, Ringkasan, 1.1, 1.19.S1, 1.19.24, 1.19.S8 |
| 2 | Activity list (filtered) | `activities` | done | AT-12 |
| 3 | Participant list: Mobility / IO Admin only (+ own unit per Rules §10) | `participants` | done | Sheets Mahasiswa / Pegawai. Viewer and partnership get 403. `export_log` records it |
| 4 | Known Activities register | `known-activities` | done | Viewer 403 |
| 5 | Frozen snapshot workbook (summary + items + late additions + post-freeze changes) | `snapshot` | done | Sheets Ringkasan, 1.1, 1.19.S1, 1.19.24, 1.19.S8, Tambahan Susulan, Perubahan Pasca-Beku, plus "1.1 Peserta" for mobility/admin only. Raw field keys: see L-2 |
| 6 | Realization by agreement | `realization-by-agreement` | done | |
| 7 | Verification SLA report | `sla` | done | One row per activity per track (49 rows) |
| — | Duplicates, snapshot archive, chart, agreement-activities | extra kinds | done | Submitter gets 403 on `snapshot-archive` (L-7) |
| Info sheet, filename pattern, header styling | `lib/excel/workbook.ts` | done | `SIM-Realisasi_snapshot_Genap-2025-2026-(Setahun)_20261001-2344.xlsx` |

### 1.6 Settings PRD §7.5 / Design §3.9 (io_admin only; all other roles get Forbidden)

| Req | Status | Notes |
|---|---|---|
| Academic calendar: years, semester ranges, cutoffs, freeze status, Bekukan sekarang / Bekukan ulang | done / see M-3 | "Ubah semester" dialog, "Tambah tahun akademik" |
| Grace period (6 mo), reporting deadline (30 d), SLA (3/5), reminders (7/14), duplicate window/similarity, register match window/similarity, nudge resend | done | All appear on the Umum tab with the "Berlaku untuk perhitungan live…" note |
| Jenis Kegiatan master with flag toggles, deactivate not delete | done | |
| Holidays | done | |
| Demo time travel (`demo_today`) + "Jalankan job harian" | done | The job reported "4 notifikasi SLA · 0 pengingat revisi · 0 eskalasi · 1 pengingat tenggat" |

### 1.7 SIM Kerjasama integration PRD §7.6 / Design §3.10

| Req | Where | Status | Notes |
|---|---|---|---|
| Document detail → Realisasi tab: summary strip, chain table with "Dokumen saat kegiatan", empty state + grace text, export | `/kerjasama/dokumen/[id]/realisasi` | done | Doc 901 shows "Belum ada realisasi … Dalam masa tenggang hingga 15 Des 2026 …" |
| Active list "no realization this AY" flag respecting grace | `/kerjasama/dokumen` | done | Flags: Terealisasi / Belum ada realisasi TA ini / Masa tenggang / Tidak aktif |
| **Renewal evaluation screen → realization summary as evidence** | — | **missing** | M-1 |

### 1.8 Notifications PRD §7.7 (in-app + email outbox)

| Event → recipient | Status | Evidence |
|---|---|---|
| Submission received → Partnership (+ Mobility if required) | done | RL-2026-0101 notified io.partnership, io.mobility and kepala.io (twice: L-4) |
| Revision requested → unit | done | RL-2026-0101 → ua-fti. Link goes to `/revisi` |
| Revision reminder / escalation → unit / IO | done (job) | Run through `run_daily_jobs`. Seed state had no due items after my resubmits |
| Verified / rejected → unit | done | `activity_verified` for S-16 → ua-fti |
| SLA yellow / red → team / IO Admin | done | The job created 4 `sla_yellow` and 4 `sla_red` |
| Reporting deadline H-7 / H / weekly (drafts) → unit | done | The job created `deadline_weekly` for S-23 |
| Duplicate candidate → Partnership | done (seed + `_scan_duplicates`) | |
| Known-activity nudge → unit | done | ua-fbe got "Mohon laporkan: Kunjungan dosen FBE ke Hanyang University" |
| Snapshot frozen → IO Admin, viewers | done | The manual freeze notified rektorat and kepala.io. Seed duplicates: see L-6 |
| Bell, unread count, `/notifikasi`, mark read; email outbox rows written | done | The outbox has no UI, which is acceptable for the mockup ("logged, not sent") |

### 1.9 Navigation and access (Design §1, Rules §10)

| Item | submitter | partnership | mobility | io_admin | viewer | Status |
|---|---|---|---|---|---|---|
| Dashboard / Kegiatan / Laporan | ✓ | ✓ | ✓ | ✓ | ✓ | done |
| + Kegiatan Baru | ✓ | Forbidden | Forbidden | ✓ (picks unit) | Forbidden | done |
| Verifikasi Kemitraan (badge) | Forbidden | ✓ 4 | Forbidden | ✓ | Forbidden | done |
| Verifikasi Mobilitas (badge) | Forbidden | Forbidden | ✓ 3 | ✓ | Forbidden | done |
| Duplikat (badge) | Forbidden | ✓ | view by URL | ✓ | Forbidden | done |
| Kegiatan Diketahui | Forbidden | ✓ | view by URL, **no nav** | ✓ | Forbidden | partial (L-5) |
| Pengaturan | Forbidden | Forbidden | Forbidden | ✓ | Forbidden | done |
| Participant names: own unit ✓, partnership counts only, mobility ✓, viewer counts only | | | | | | done ("Nama peserta hanya dapat dilihat oleh unit, tim Mobilitas, dan Admin IO.") |
| Edit verified: partnership Detail/File, mobility Participants, admin both | | | | | | done ("Edit Detail/Berkas" / "Edit Peserta"). The edit is logged with diff + note, flagged "Pasca-beku" when in a frozen window (R-29..R-31) |
| Laporan list hides Daftar peserta / Register / Arsip per role | | | | | | done (submitter: no Register/Arsip; viewer: no Peserta/Register; partnership: no Peserta) |

### 1.10 Rules spot-checks reached through the UI

R-04/R-06 (picker, partner snapshot), R-05 (warn not block), R-07..R-13 (checklist), R-14 (co-unit read-only), R-15 (delete draft), R-16..R-18, R-21 (versions kept read-only), R-22 (duplicate NRP rejected at entry), R-23..R-28, R-29..R-31 (post-verification edit, Pasca-beku), R-34 (unlink admin-only button), R-47 (grace listed separately), R-51..R-54, R-55..R-59 (freeze, refreeze button, archive downloadable), R-60 (SLA chips/levels), R-63 (`export_log`). All were observed as **done**.

---

## 2. Gaps and bugs (prioritised)

**Counts:** HIGH 0 · MEDIUM 3 · LOW 7 · INFO 1.
The core flows and all 12 acceptance scenarios work end to end in the UI. The gaps below are coverage and UX gaps at the edges of the spec.

### MEDIUM

#### M-1. Renewal-evaluation realization summary is missing (PRD §7.6 bullet 3, Architecture §7 "Renewal evaluation")
- **Location:** no route or component exists. `app/kerjasama/dokumen/[id]/page.tsx` only redirects to `…/realisasi`. `grep -ri evaluasi app components` finds nothing. The CONTRACTS §7 route map also leaves it out, so it was dropped at planning time without being recorded as descoped.
- **Repro:** open `/kerjasama/dokumen` as any role. There is no renewal-evaluation view and no "evidence" summary block outside the Realisasi tab.
- **Fix:** add a small `RealizationSummary` component, using the summary strip already built from `agreement_realization()`: count per AY, last activity, total students. Render it on a `/kerjasama/dokumen/[id]/evaluasi` stub page, or on the document "Detail" tab, labelled "Bukti realisasi untuk evaluasi perpanjangan". Alternatively, record it as explicitly descoped in PRD §11 or the plan.

#### M-2. Drafts near or past the reporting deadline have no flag in "My Activities" (PRD §7.2 "deadline flags", Rules R-62)
- **Location:** `components/realisasi/list/activity-table.tsx:51-79` (`Flags`). The flags cover only `is_late` (late *submission*), SLA, out-of-scope and duplicate. The "Terlambat" preset (`preset=late`) also uses only `is_late`.
- **Repro:** log in as ua-fsd and open `/realisasi/kegiatan?status=draft`. RL-2026-0023 (reporting deadline 13 Sep 2026, 18 days overdue) shows "Tidak ada penanda". The deadline appears only on the dashboard "Draf mendekati tenggat" card.
- **Fix:** expose `reporting_deadline` (already on the activity) in `v_activity_list`. Render a pill for `status='draft'`: `Tenggat 13 Sep` (amber when ≤ `deadline_reminder_before_days`) or `Lewat tenggat` (red). Optionally include overdue drafts in the `late` preset, or add a `deadline` flag filter, so the export matches (AT-12).

#### M-3. "Bekukan sekarang" freezes the official semester snapshot before the semester ends, with no warning, and the cutoff job then skips that semester
- **Location:** `components/realisasi/settings/calendar-manager.tsx` (freeze dialog) → `freezeNow` → `freeze_snapshot`. Job rule CONTRACTS §5.1: the freeze runs only when there is "no live snapshot for (AY, kind)".
- **Repro:** log in as kepala.io, open Pengaturan → Kalender Akademik, and click Ganjil 2026/2027 "Bekukan sekarang" on 1 Oct 2026. The dialog only says the values will be stored.
  - Result: a live `ganjil_ytd` snapshot is created with `window_end 2027-01-31` and `cutoff 2027-03-02`, but its values are as of 1 Oct. The dashboard for Ganjil 26/27 is now "Dibekukan 1 Okt 2026".
  - Activities verified from Oct 2026 to Jan 2027 will not be in the Ganjil report, and the 2 Mar 2027 scheduled freeze will skip that semester. The only remedy is a manual "Bekukan ulang" with a reason.
- **Why it matters:** PRD §6.6 allows a manual freeze, but a premature one silently corrupts the official YTD report. The database review's M4 covers `p_as_of`/`p_actor` spoofing, not this UI path.
- **Fix:** in the dialog, when `today < semester.end_date` (or `< cutoff_date`), show a destructive warning ("Semester belum berakhir — data setelah hari ini tidak akan masuk snapshot dan job cutoff tidak akan membekukan ulang"). Require typing a reason, or disable the button before `end_date` unless the admin confirms explicitly. Also show "data per {frozen_at}" next to the window in Arsip.

### LOW

#### L-1. Draft rows show misleading track chips
- **Location:** `components/realisasi/list/activity-table.tsx` (track chip cell).
- **Repro:** as ua-fsd, `/realisasi/kegiatan?status=draft` shows RL-2026-0023 as "Draf" with "Kemitraan: Menunggu · Mobilitas: Tidak diperlukan". The detail header for the same draft shows no chips.
- **Fix:** render "–" (or a grey "Belum diajukan") for `status='draft'`, matching the detail header.

#### L-2. Post-freeze changes show raw DB field keys in reports
- **Location:** `components/realisasi/reports/snapshot-archive.tsx:130` and `lib/excel/sheets.ts:294` (`formatDiff`).
- **Repro:** Laporan → Arsip → Genap 2025/2026 → "Perubahan pasca-beku" shows `venue: Auditorium PCU → …`. The Riwayat tab localises the same diff as "Tempat / platform".
- **Fix:** map keys through `components/realisasi/activity/labels.ts`, or move the field-label map to `lib/realisasi/status.ts` so the Excel builder can share it.

#### L-3. Checklist noise on the first submission
- **Location:** `components/realisasi/wizard/submit-panel.tsx` (renders every `submission_checklist` item).
- **Repro:** wizard step 4 for a new draft lists "Terpenuhi: Versi peserta baru dibuat untuk revisi Mobilitas" (`R21_NEW_VERSION_REQUIRED`), which only applies to a resubmit.
- **Fix:** hide `R21_NEW_VERSION_REQUIRED` when `resubmit` is false. Optionally hide `R12_*` items that do not apply to the selected Jenis direction.

#### L-4. io_admin receives each submission notification twice
- **Location:** `submit_activity` notifies the partnership team and the mobility team. kepala.io belongs to both.
- **Repro:** submit RL-2026-0101 (needs both tracks). kepala.io gets two "Pengajuan baru: RL-2026-0101", one linked to each queue.
- **Fix:** acceptable as-is, since there are two links. If not intended, dedupe recipients per event and link to the activity.

#### L-5. Mobility has the register view right but no nav entry
- **Location:** `components/layout/nav.ts` shows "Kegiatan Diketahui" only for `known.manage`.
- **Detail:** Rules §10 gives the mobility team "view" on the register, and the page allows `known.view`, but it is reachable only by URL or the S8 card link. Contract amendment 9 chose this deliberately, but it contradicts Rules §10, which is authoritative.
- **Fix:** show the item for `known.view`, keeping the actions hidden.

#### L-6. Seeded snapshot notifications are duplicated
- **Location:** `supabase/seed/05_notifications.sql` + `90_freeze.sql`.
- **Repro:** after `db-reset`, rektorat sees three AY 2025/2026 "Snapshot dibekukan" notifications. One is dated 30 Agu 2026 (seed row). Two are dated at reset time, created by `freeze_snapshot` with `now_ts()` instead of the freeze `as_of`.
- **Fix:** drop the hand-written seed row, or suppress notifications when freezing from the seed. Consider stamping `created_at` with `p_as_of`.

#### L-7. Submitters cannot download snapshot workbooks or the archive
- **Location:** `/api/export/snapshot-archive` and `/api/export/snapshot` return 403 for submitters, and Laporan hides Arsip for them.
- **Detail:** Rules §10 grants submitters "Dashboard & non-personal exports — own unit", and R-59 says every snapshot stays downloadable. CONTRACTS §8.2 excluded submitters. The impact is low, because a submitter can still export the frozen own-unit KPI values through Ringkasan for a frozen period (`kpi-summary` reads from the snapshot).
- **Fix:** either allow `snapshot` scoped to the unit's items, or document the deviation.

### INFO

#### I-1. AT-05 cannot be shown in an unfrozen Ganjil view before the agreement starts
- An unfrozen period computes with `cutoff = least(cutoff, today())` (WP-DB amendment 7).
- So before 2 Dec 2026, Ganjil 2026/2027 does not list doc 902 as grace-excluded at all. It appears only after a freeze, which uses the nominal cutoff, or with `demo_today` ≥ 2026-12-02.
- For the demo script: show grace with doc 901 in Live, or set `demo_today` first.
