# SIM Realisasi — Business Rules
**Version:** 1.1 (Mockup, Revisi V.1) · Authoritative for behaviour. If another doc disagrees, this one wins.

Revisi V.1 summary: one-page submission form; Jenis Kegiatan = SIM Kerjasama's Agenda Kerjasama list; Inbound/Outbound
per kegiatan; one kerja sama per kegiatan; one verification track (Mobility) — non-mobility kegiatan are recorded on
submit; duplicate students between units are decided inside Verifikasi Mobilitas; no SLA, no Kegiatan Diketahui, no
KPI 1.19.S8; "KPI" is called **RENSTRA** in the UI; four period cut-offs; International Awards dashboard; Unit Akademik
only.

**Revisi V.2 (2026-10-05)** — the "SIM Kerjasama" navigation section is hidden: SIM Realisasi only reads SIM
Kerjasama's data (agreements, partners, units); its document screens belong to the SIM Kerjasama app. An agreement's
Realisasi page stays reachable from the RENSTRA tables (deep link `/kerjasama/dokumen/<id>/realisasi`).

**Revisi V.1, round 2 (2026-10-05)** — supersedes the rules below where they differ:
1. Every KUI account (Kepala Kantor Kerja Sama dan Urusan Internasional, Head of Partnership and Global Alliance, Staff
   of Partnership and Global Alliance) is `io_admin`: all features unlocked. Live install:
   `supabase/deploy/patch-2026-10-05-kui-admin.sql`.
2. Excel exports have no "Info" sheet; every workbook opens directly on the data.
3. The Kegiatan export adds the columns SDG, Link IA and Link IR (absolute links to the current IA/IR files).
4. The Kegiatan export adds a sheet "Peserta": every participant (PETRA/inbound students, staff, external persons) of
   each listed kegiatan, from its latest reported (non-draft) version. Only for roles allowed to export participants
   (admin, Mobility team, submitter); logged as a personal-data export.
5. The Kegiatan list has one quick filter only: "Perlu tindakan saya" (KUI: submissions awaiting approval; unit: drafts
   and kegiatan sent back for revision). "Terlambat" and "Semester ini" are removed.
6. "Setujui" on Verifikasi Mobilitas is a plain confirmation ("Apakah Anda yakin…?") without a Catatan.
7. "Minta Revisi" notifies the submitting unit (notification bar) and the kegiatan is flagged **Revisi** on Verifikasi
   Mobilitas for both sides: KUI sees it under "Dikembalikan untuk Revisi"; the unit sees a read-only status list of its
   mobility kegiatan (Menunggu verifikasi / Revisi, with KUI's note and "Revisi sekarang").
8. International Awards lists only the top 3 of each leaderboard (competition ranking on the total, ties at rank 3
   kept, units with 0 hidden), on screen and in the export.

---

## 1. Activity scope
- **R-01** Only activities implementing a PCU MoU/MoA from SIM Kerjasama are recorded. Non-MoU mobility (IISMA, free movers, scholarships) is out of scope.
- **R-02** One activity = one IA = one IR. A program spanning several rounds submits one activity per round.
- **R-03** An activity links to exactly **one** agreement. The link stores the original document; the current document is always resolved through the renewal chain, never stored.
- **R-04** An agreement is selectable if its validity period overlaps the activity dates — regardless of its status today (active or archived). Rejected and in-process documents are never selectable.
- **R-05** If the submitting unit is not in the agreement's Lingkup Kerja Sama, the system warns but does not block.
- **R-06** Partner name and country are snapshotted at link time; later partner edits/merges in SIM Kerjasama don't change them.
- **R-06a** Only **Unit Akademik** (SIMKS `jenis_unit` = akademik) submit or take part as co-units; unit pickers and report filters list academic units only.

## 2. Submission
- **R-07** One page: Detail & Kerja sama, Peserta, Berkas, Ajukan. Peserta and Berkas unlock once the Detail is saved as a draft. Required at submission: all required Detail fields, the agreement, IA (PDF), IR (PDF).
- **R-07a** Jenis Kegiatan is chosen from SIM Kerjasama's Agenda Kerjasama list (amendment excluded). Realisasi keeps one rule per agenda (`agenda_rules`): its **mobility category** (JD/DD, Student Exchange, Short/Summer, other mobility, or none) and whether it counts for 1.19.S1. IO Admin edits the rules in Pengaturan → Jenis Kegiatan.
- **R-07b** Every kegiatan is **Inbound** or **Outbound** (one dropdown per kegiatan). Kota and Sumber Dana are not recorded. SKS diakui is asked only for mobility kegiatan.
- **R-08** Tanggal Selesai must be ≤ today (an IR can't exist before the activity ends).
- **R-09** Semester and academic year are derived from Tanggal Mulai. A start date outside any configured academic year cannot be submitted (IO Admin must add the year first).
- **R-10** Reporting deadline = Tanggal Selesai + `reporting_deadline_days` (default 30). Submissions after it are accepted and flagged `Terlambat`.
- **R-11** A **mobility kegiatan** (agenda with a mobility category) needs a non-empty participant set and one **PDF combining the students' transcripts, the poster and the documentation** (`mobility_bundle`); its Mobility track starts as `pending`. Any other kegiatan has track `not_required` and is **verified on submit**.
- **R-12** Mandatory participant section by the kegiatan's direction: outbound → ≥1 PETRA student; inbound → ≥1 inbound student.
- **R-13** Files: PDF only for IA/IR and the mobility PDF, max 10 MB each; evidence accepts PDF/JPG/PNG (max 10 MB) or links.
- **R-14** A unit may submit for itself; "Unit Lain yang Terlibat" are added by the submitter and get read-only access.
- **R-15** A draft can be deleted by the account that created it, or by IO Admin (any draft); other users of the unit can edit it but not delete it. Drafts never counted; submitted activities are never deleted.

## 3. Participants
- **R-16** Every counted student must have an NRP that resolves in the BAAK registry. Unknown NRPs block submission.
- **R-17** Inbound students must exist in BAAK with category `inbound_exchange` (Rector's rule: all inbound students hold an NRP) and need a home institution. Their transcripts are part of the mobility PDF (R-11).
- **R-18** Graduated/inactive NRPs and inactive employees produce a warning, not a block.
- **R-19** PETRA staff must resolve in HR by employee ID. Staff are recorded, not counted in RENSTRA 1.1.
- **R-20** Foreign speakers / visiting lecturers / guests go in the structured External Persons list (Detail section); they are not counted in RENSTRA 1.1.
- **R-21** Participant sets are versioned. A unit revision creates version n+1; earlier versions are kept read-only. Only the single `approved` version counts; approving a new version marks the previous approved one `superseded`.
- **R-22** Duplicate NRPs within one participant set are rejected at entry.

## 3A. Status machine
- **R-23** Track transitions (Mobility is the only verification track):
  ```text
  Mobility:    not_required                      (non-mobility kegiatan)
               pending → approved | revision_requested
               revision_requested → pending      (on unit resubmit / new participant version)
  ```
- **R-24** Changing Jenis Kegiatan during a revision re-evaluates the track: a mobility agenda → `pending`, otherwise `not_required`.
- **R-25** Overall status (derived, never set directly):
  | Condition | Status |
  |---|---|
  | not submitted | draft |
  | Mobility = revision_requested | revision_requested |
  | Mobility ∈ {approved, not_required} | verified |
  | otherwise | in_verification |
- **R-26** Nothing is rejected: a wrong submission goes back to the unit as a revision.
- **R-27** Revision requests require one general note (no per-row notes).
- **R-27a** Mobility cannot approve a kegiatan while it has open duplicate-student conflicts (R-33).
- **R-28** `verified_at` is set when the activity first becomes verified; it is not changed by later edits.

## 4. Post-verification edits
- **R-29** Only IO can edit a verified activity: Mobility (participants — as a new IO-created version, auto-approved), IO Admin (all).
- **R-30** Every edit writes an Update Log entry with a field-level diff and actor.
- **R-31** Edits to an activity whose date falls inside a frozen window are flagged `in_frozen_period` and listed as "Perubahan Pasca-Beku" in the next report. Frozen values never change.

## 5. Duplicate students (inside Verifikasi Mobilitas)
- **R-32** Every activity is its own event; kegiatan are no longer linked or merged.
- **R-33** **Rule 2.1 — conflict.** The same NRP in the counting sets of two non-draft mobility kegiatan of **different submitting units** with **overlapping dates** is a conflict. Conflicts are found on submit and on every participant change and appear in Verifikasi Mobilitas → Duplikat Mahasiswa (and on both activity pages).
- **R-34** Mobility compares both kegiatan (including their mobility PDFs) and keeps the student on one of them ("Pilih kegiatan ini", optional note, logged). The decision can be changed later. While open, the student counts in neither kegiatan.
- **R-35** **Rule 2.2.** The same unit claiming one student in two kegiatan is not a conflict: the student counts in both.

## 6. RENSTRA calculations (shown as "RENSTRA"; identifiers keep `kpi_*`)
General:
- **R-36** Only `verified` activities count. Activity date = Tanggal Mulai.
- **R-37** Period cut-offs for the dashboard, charts, reports and every Excel export: **Ganjil** (Ganjil start → end), **Genap** (Genap start → end), **Setahun (kumulatif)** (academic-year start → end), **YTD** (academic-year start → today, never frozen; offered only for the active academic year, other years fall back to Setahun). Ganjil and Setahun read their frozen snapshots when present; Genap is computed over its window as of the full-year snapshot's freeze, so it never drifts afterwards.

**RENSTRA 1.1 — Jumlah mahasiswa Inbound & Outbound**
- **R-38** Count = (NRP, kegiatan) pairs among students in the approved participant set of verified mobility kegiatan.
  - Outbound kegiatan count `internal` (PETRA) students; inbound kegiatan count `inbound` students.
  - A student in an open conflict counts nowhere; after a decision, only in the kept kegiatan.
- **R-39** One student in two different kegiatan = 2 (rule 2.2). Two units claiming the same student in overlapping kegiatan = 1, for the unit Mobility kept (rule 2.1).
- **R-40** Reported per semester and per academic year.

**RENSTRA 1.19.S1 — Kegiatan internasional dengan mitra**
- **R-41** Count = verified kegiatan whose agenda counts for S1 and whose agreement has ≥1 partner with country ≠ Indonesia. Domestic count shown alongside for reference.

**RENSTRA 1.19.24 — Persen terlaksana MoU & MoA**
- **R-42** Unit of count = renewal chain (an agreement and all its renewals), so a mid-year renewal counts once.
- **R-43** Denominator = chains active at any point between academic-year start and the cutoff, **excluding** chains whose first start date is within `grace_period_months` (default 6) of the cutoff. Auto-renewed chains are **always** included (no grace exclusion).
- **R-44** Numerator = denominator chains with ≥1 verified activity (i.e., IA) dated between academic-year start and the cutoff, through any document in the chain.
- **R-45** An MoA signed under an MoU does **not** count as realization of the MoU. Only IAs count.
- **R-46** Reported as All, International, and Domestic (by the chain's partner countries; a chain with any foreign partner is international).
- **R-47** Grace-excluded chains are listed separately in reports, not hidden.

KPI 1.19.S8 and the Known Activities register (former R-48…R-54) are removed.

## 7. International Awards (dashboard tab, report and export)
- **R-48** Ranked by **Program Studi** only (Fakultas, Program and UP units are never ranked), same verified kegiatan, period cut-offs and conflict rules as RENSTRA 1.1; each board ranked by total. Student boards credit each student to their own Program Studi; a student without a PETRA prodi (e.g. inbound exchange) goes to the submitting unit when it is a Program Studi, else is not counted. A Fakultas scope shows its Program Studi.
- **R-49** Student boards — **Inbound** (inbound kegiatan, inbound students), **Outbound Dalam Negeri** (outbound, kegiatan country = ID, PETRA students), **Outbound Internasional** (outbound, country ≠ ID). Columns: Program Studi JD/DD, Student Exchange, Short/Summer Program, Kegiatan Internasional (<14 hari) = other mobility kegiatan lasting `end − start + 1 < 14` days; each student counts in one column.
- **R-50** **Inisiatif Internasional**: number of verified international kegiatan per submitting Program Studi — inbound mobility, outbound mobility, other kegiatan — and the total.

## 8. Semester freeze & snapshots
- **R-55** Each semester has a cutoff date (default end + 30 days). On the cutoff the system freezes a snapshot: Ganjil → `ganjil_ytd`, Genap → `genap_full_year` (shown as Setahun).
- **R-56** A snapshot stores values, contributing IDs, and the settings used. Settings changes never alter existing snapshots.
- **R-57** Activities verified after a snapshot but dated within its window are **late additions**: shown in YTD and listed in the next snapshot's report; the earlier snapshot stays unchanged.
- **R-58** IO Admin can re-freeze with a mandatory reason; the old snapshot is kept and marked superseded.
- **R-59** Every snapshot, including superseded ones, stays downloadable as Excel indefinitely.

## 9. Work queue & reminders (no SLA)
- **R-60** There is no verification SLA. The Mobility team sees what needs processing — kegiatan waiting for verification (oldest first), open duplicate students, kegiatan waiting for the unit — in the dashboard card "Perlu diproses", the sidebar badge and notifications.
- **R-61** Unit revision: reminder to the unit after 7 days (configurable); no escalation.
- **R-62** Reporting-deadline reminders apply to drafts: 7 days before, on the day, then weekly.

## 10. Access
| Action | submitter | io staff (Mobility) | io_admin | viewer |
|---|---|---|---|---|
| Create / submit / revise own activity | ✓ | — | ✓ (on behalf of a unit) | — |
| View activities | own + co-unit | all | all | verified |
| View participant names / mobility PDF | own | ✓ | ✓ | — |
| Mobility verify, decide duplicate students | — | ✓ | ✓ | — |
| Edit verified activity | — | Participants | ✓ | — |
| Settings, calendar, Jenis Kegiatan rules, freeze | — | — | ✓ | — |
| Dashboard, International Awards & non-personal exports | own unit | ✓ | ✓ | ✓ |
| Participant exports | own unit | ✓ | ✓ | — |

- **R-63** Every export containing personal data is logged (actor, filters, row count).
- **R-64** No hard deletes after submission; everything is status + log.

## 11. Acceptance scenarios (map to seed data)
| ID | Given | When | Then |
|---|---|---|---|
| AT-01 | S-13 (FTI) and S-14 (Informatika) same summer program, 12 shared students; Mobility kept them on S-13 | RENSTRA 1.1 | counted once, for FTI; Informatika 0 for those students |
| AT-02 | Student D31240187 in S-15a and S-15b (same unit) | RENSTRA 1.1 | that student contributes 2 |
| AT-03 | S-16 Mobility revision requested | view status | overall `revision_requested`; after v2 approved → `verified`; v1 kept, read-only |
| AT-04 | A non-mobility kegiatan (e.g. S-17 seminar) | unit submits | verified immediately (track `not_required`) |
| AT-05 | Agreement signed 3 months before 2026/2027 Ganjil cutoff | RENSTRA 1.19.24 Ganjil | excluded from denominator, listed as grace-excluded |
| AT-06 | Auto-renewed agreement with no activity | RENSTRA 1.19.24 | in denominator, not in numerator |
| AT-07 | S-20 activities before and after renewal | RENSTRA 1.19.24 | chain counted once in denominator and once in numerator; detail shows original doc numbers |
| AT-08 | S-19 Ganjil 2025/2026 activity verified after Ganjil freeze | open Ganjil snapshot; open Setahun snapshot | Ganjil values unchanged; Setahun snapshot includes it, marked "Tambahan susulan" |
| AT-09 | S-18 (Informatika) claims two of S-13's students, overlapping dates | open Verifikasi Mobilitas | two open conflicts; S-18 cannot be approved until Mobility picks a kegiatan for each |
| AT-10 | Unknown NRP pasted | submit | blocked with row-level error |
| AT-11 | Viewer opens participant export | — | not available; API returns 403 |
| AT-12 | Any list on screen with filters | Unduh Excel | workbook rows = on-screen filtered rows; Info sheet records filters (incl. period) |
