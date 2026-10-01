# SIM Realisasi — Business Rules
**Version:** 1.0 (Mockup) · Authoritative for behaviour. If another doc disagrees, this one wins.

---

## 1. Activity scope
- **R-01** Only activities implementing a PCU MoU/MoA from SIM Kerjasama are recorded. Non-MoU mobility (IISMA, free movers, scholarships) is out of scope.
- **R-02** One activity = one IA = one IR. A program spanning several rounds submits one activity per round.
- **R-03** An activity links to ≥1 agreement. Each link stores the original document; the current document is always resolved through the renewal chain, never stored.
- **R-04** An agreement is selectable if its validity period overlaps the activity dates — regardless of its status today (active or archived). Rejected and in-process documents are never selectable.
- **R-05** If the submitting unit is not in the agreement's Lingkup Kerja Sama, the system warns but does not block.
- **R-06** Partner name and country are snapshotted at link time; later partner edits/merges in SIM Kerjasama don't change them.

## 2. Submission
- **R-07** Required at submission: all required Detail fields, ≥1 agreement, IA (PDF), IR (PDF).
- **R-08** Tanggal Selesai must be ≤ today (an IR can't exist before the activity ends).
- **R-09** Semester and academic year are derived from Tanggal Mulai. A start date outside any configured academic year cannot be submitted (IO Admin must add the year first).
- **R-10** Reporting deadline = Tanggal Selesai + `reporting_deadline_days` (default 30). Submissions after it are accepted and flagged `Terlambat`.
- **R-11** If the Jenis requires mobility review (or any participant rows exist), the participant set must be non-empty and the Mobility track starts as `pending`; otherwise `not_required`.
- **R-12** Mandatory participant section by Jenis direction: outbound → ≥1 PETRA student; inbound → ≥1 inbound student.
- **R-13** Files: PDF only for IA/IR/transcripts, max 10 MB each; evidence accepts PDF/JPG/PNG (max 10 MB) or links.
- **R-14** A unit may submit for itself; co-units are added by the submitter and get read-only access.
- **R-15** Drafts can be deleted by the unit (they never counted); submitted activities are never deleted.

## 3. Participants
- **R-16** Every counted student must have an NRP that resolves in the BAAK registry. Unknown NRPs block submission.
- **R-17** Inbound students must exist in BAAK with category `inbound_exchange` (Rector's rule: all inbound students hold an NRP) and need home institution + transcript PDF.
- **R-18** Graduated/inactive NRPs and inactive employees produce a warning, not a block.
- **R-19** PETRA staff must resolve in HR by employee ID. Staff are recorded, not counted in KPI 1.1.
- **R-20** Foreign speakers / visiting lecturers / guests go in the structured External Persons list (Detail section); they're verified by Partnership and are not counted in KPI 1.1.
- **R-21** Participant sets are versioned. A unit revision creates version n+1; earlier versions are kept read-only. Only the single `approved` version counts; approving a new version marks the previous approved one `superseded`.
- **R-22** Duplicate NRPs within one participant set are rejected at entry.

## 3A. Status machine
- **R-23** Track transitions:
  ```text
  Partnership: pending → approved | revision_requested | rejected
               revision_requested → pending (on unit resubmit)
  Mobility:    not_required
               pending → approved | revision_requested
               revision_requested → pending (on new participant version)
  ```
- **R-24** A Partnership-track revision that changes Jenis Kegiatan resets the Mobility track to `pending` (or `not_required`) because counting rules may change. Any other Detail/File revision leaves Mobility untouched.
- **R-25** Overall status (derived, never set directly):
  | Condition | Status |
  |---|---|
  | not submitted | draft |
  | Partnership = rejected | rejected |
  | any track = revision_requested | revision_requested |
  | Partnership = approved and Mobility ∈ {approved, not_required} | verified |
  | otherwise | in_verification |
- **R-26** Only Partnership can reject. Reject requires a reason (duplicate / not a partnership activity / wrong agreement / other) + note. Rejection is terminal.
- **R-27** Revision requests require a note. Mobility may add per-row notes.
- **R-28** `verified_at` is set when the activity first becomes verified; it is not changed by later edits.

## 4. Post-verification edits
- **R-29** Only IO can edit a verified activity: Partnership (Detail, files, external persons, agreements), Mobility (participants — as a new IO-created version, auto-approved), IO Admin (all).
- **R-30** Every edit writes an Update Log entry with a field-level diff and actor.
- **R-31** Edits to an activity whose date falls inside a frozen window are flagged `in_frozen_period` and listed as "Perubahan Pasca-Beku" in the next report. Frozen values never change.

## 5. Duplicates & event groups
- **R-32** Every activity starts in its own event group.
- **R-33** Duplicate candidate when: shares ≥1 renewal chain with another non-rejected activity, dates overlap within ±`dup_date_window_days`, name similarity ≥ `dup_name_similarity`.
- **R-34** Partnership can link candidates (merge event groups) or dismiss. Linking is reversible only by IO Admin (logged).
- **R-35** Linked activities stay separate records with their own units, files, and participants.

## 6. KPI calculations
General:
- **R-36** Only `verified` activities count. Activity date = Tanggal Mulai.
- **R-37** Windows: Ganjil report = academic-year start → Ganjil end (YTD); Genap report = full academic year; Live = academic-year start → today.

**KPI 1.1 — Jumlah mahasiswa Inbound & Outbound**
- **R-38** Count = number of distinct (NRP, event group) pairs among students in the approved participant set of verified activities whose Jenis has `counts_as_mobility`.
  - Outbound counts `internal` section students of `outbound` Jenis.
  - Inbound counts `inbound` section students of `inbound` Jenis.
- **R-39** One student in two different events = 2. Same event claimed by two units (linked) = 1 at university level, counted in **both** units at unit level.
- **R-40** Reported per semester and per academic year.

**KPI 1.19.S1 — Kegiatan internasional dengan mitra**
- **R-41** Count = distinct event groups among verified activities whose Jenis has `counts_for_s1` and that link ≥1 partner with country ≠ Indonesia. Domestic count shown alongside for reference.

**KPI 1.19.24 — Persen terlaksana MoU & MoA**
- **R-42** Unit of count = renewal chain (an agreement and all its renewals), so a mid-year renewal counts once.
- **R-43** Denominator = chains active at any point between academic-year start and the cutoff, **excluding** chains whose first start date is within `grace_period_months` (default 6) of the cutoff. Auto-renewed chains are **always** included (no grace exclusion).
- **R-44** Numerator = denominator chains with ≥1 verified activity (i.e., IA) dated between academic-year start and the cutoff, through any document in the chain.
- **R-45** An MoA signed under an MoU does **not** count as realization of the MoU. Only IAs count.
- **R-46** Reported as All, International, and Domestic (by the chain's partner countries; a chain with any foreign partner is international).
- **R-47** Grace-excluded chains are listed separately in reports, not hidden.

**KPI 1.19.S8 — Persen kegiatan internasional dilaporkan via SIM**
- **R-48** Reported = distinct event groups of verified international activities in the window.
- **R-49** Gap = international Known Activities in the window with status `unmatched`.
- **R-50** S8 = Reported ÷ (Reported + Gap). Matched entries are already represented by their SIM activity; dismissed entries are ignored.

## 7. Known Activities register
- **R-51** Only Partnership / IO Admin create, match, dismiss entries.
- **R-52** Match suggestions: same unit (or no unit), date within ±`known_match_window_days` (default 7), name similarity ≥ 0.4. Matching is always confirmed by a person.
- **R-53** A known activity can match only one SIM activity; a SIM activity can satisfy several known entries.
- **R-54** "Ingatkan unit" sends one nudge per entry; re-sending allowed after 14 days.

## 8. Semester freeze & snapshots
- **R-55** Each semester has a cutoff date (default end + 30 days). On the cutoff the system freezes a snapshot: Ganjil → `ganjil_ytd`, Genap → `genap_full_year`.
- **R-56** A snapshot stores values, contributing IDs, and the settings used. Settings changes never alter existing snapshots.
- **R-57** Activities verified after a snapshot but dated within its window are **late additions**: shown in the live view and listed in the next snapshot's report; the earlier snapshot stays unchanged. (Late Ganjil activities are naturally counted in that year's Genap full-year snapshot and marked as late.)
- **R-58** IO Admin can re-freeze with a mandatory reason; the old snapshot is kept and marked superseded.
- **R-59** Every snapshot, including superseded ones, stays downloadable as Excel indefinitely.

## 9. SLA & reminders
- **R-60** Verification SLA per track, in business days (excl. weekends + configured holidays), from the moment the track became `pending`. Yellow > 3, red > 5 (configurable). Unit revision time doesn't count against IO.
- **R-61** Unit revision: reminder after 7 days, escalation to IO after 14 days (configurable).
- **R-62** Reporting-deadline reminders apply to drafts: 7 days before, on the day, then weekly.

## 10. Access
| Action | submitter | io partnership | io mobility | io_admin | viewer |
|---|---|---|---|---|---|
| Create / submit / revise own activity | ✓ | — | — | ✓ (on behalf of a unit) | — |
| View activities | own + co-unit | all | all | all | verified |
| View participant names / transcripts | own | counts only | ✓ | ✓ | — |
| Partnership verify / reject / link duplicates | — | ✓ | — | ✓ | — |
| Mobility verify | — | — | ✓ | ✓ | — |
| Edit verified activity | — | Detail/File | Participants | ✓ | — |
| Known Activities register | — | ✓ | view | ✓ | — |
| Settings, calendar, Jenis, freeze | — | — | — | ✓ | — |
| Dashboard & non-personal exports | own unit | ✓ | ✓ | ✓ | ✓ |
| Participant exports | own unit | — | ✓ | ✓ | — |

- **R-63** Every export containing personal data is logged (actor, filters, row count).
- **R-64** No hard deletes after submission; everything is status + log.

## 11. Acceptance scenarios (map to seed data)
| ID | Given | When | Then |
|---|---|---|---|
| AT-01 | S-13 (FTI) and S-14 (Informatika) same summer program, 12 shared students, linked | KPI 1.1 for that semester | University outbound counts 12; FTI unit counts 12; Informatika unit counts 12 |
| AT-02 | Student D31240187 in S-15a and S-15b | KPI 1.1 | that student contributes 2 |
| AT-03 | S-16 Partnership approved, Mobility revision requested | view status | overall `revision_requested`; after v2 approved → `verified`; v1 kept, read-only |
| AT-04 | S-17 Partnership revision changes Jenis from Joint Seminar to Student Outbound | unit resubmits | Mobility track resets to `pending` |
| AT-05 | Agreement signed 3 months before 2026/2027 Ganjil cutoff | KPI 1.19.24 Ganjil | excluded from denominator, listed as grace-excluded |
| AT-06 | Auto-renewed agreement with no activity | KPI 1.19.24 | in denominator, not in numerator |
| AT-07 | S-20 activities before and after renewal | KPI 1.19.24 | chain counted once in denominator and once in numerator; detail shows original doc numbers |
| AT-08 | S-19 Ganjil 2025/2026 activity verified after Ganjil freeze | open Ganjil snapshot; open Genap snapshot | Ganjil values unchanged; Genap snapshot includes it, marked "Tambahan susulan" |
| AT-09 | 5 matched, 2 unmatched international known activities in window | KPI 1.19.S8 | denominator = reported + 2 |
| AT-10 | Unknown NRP pasted | submit | blocked with row-level error |
| AT-11 | Viewer opens participant export | — | not available; API returns 403 |
| AT-12 | Any list on screen with filters | Unduh Excel | workbook rows = on-screen filtered rows; Info sheet records filters |
