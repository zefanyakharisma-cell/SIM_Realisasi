# SIM Realisasi — Master PRD
**Version:** 1.0 (Mockup)  ·  **Date:** 1 October 2026  ·  **Owner:** International Office (KUI), Petra Christian University
**Companion docs:** Schema v1.0 · Architecture v1.0 · Design v1.0 · Rules v1.0
**Sibling system:** SIM Kerjasama v2.0 (source of truth for MoU/MoA documents)

---

## 1. Purpose

SIM Realisasi is a management information system that collects, verifies, stores, and reports every **realization (implementation)** of PCU's MoUs and MoAs. Each realization is one activity, documented by one **Implementation Arrangement (IA)** and one **Implementation Report (IR)**, and linked to the agreement(s) it implements.

It exists so IO can:
- Produce four institutional KPIs from verified data, with a drill-down to every activity behind each number.
- Report semesterly from frozen, reproducible snapshots.
- Show which agreements are realized and which are dormant, and feed that back into SIM Kerjasama (document detail and renewal evaluation).

This PRD describes the **mockup** build: a working prototype on dummy data that proves the business rules before production.

---

## 2. KPIs the system must answer

| Code | Name | Definition (summary — full formulas in Rules §6) |
|---|---|---|
| **1.1** | Jumlah mahasiswa Inbound & Outbound | Count of students per event (NRP × event), split inbound/outbound, per semester |
| **1.19.S1** | Jumlah Kegiatan Internasional berkolaborasi dengan mitra | Count of verified events linked to ≥1 foreign partner |
| **1.19.24** | Persen terlaksana MoU dan MoA | Agreements (renewal chains) with ≥1 verified IA in the academic year ÷ agreements active in that year (minus grace-period exclusions) |
| **1.19.S8** | Persen kegiatan internasional dilaporkan melalui SIM | Verified international SIM activities ÷ (those + unmatched international entries in IO's Known Activities register) |

**Reporting rhythm:** academic-year basis with two frozen snapshots — **Ganjil (year-to-date)** and **Genap (full academic year)**.

---

## 3. Scope

### In scope (mockup)
- Activity submission by UA/UP (Detail, Peserta, File) with IA **and** IR mandatory at submission.
- Two parallel verification tracks: **Partnership team** (Detail + File) and **Mobility team** (Peserta), each with its own revision loop.
- NRP / employee-ID lookup against **mock BAAK and HR datasets**.
- Duplicate-event detection and linking ("one event, two units").
- IO Known Activities register (for KPI 1.19.S8).
- KPI dashboard with drill-down, semester freeze, snapshot archive.
- Excel export for **every** report and list.
- Settings: academic calendar & cutoffs, grace period, reporting deadline, SLAs, Jenis Kegiatan master with KPI flags.
- "Realisasi" tab on SIM Kerjasama document detail; zero-realization flag.
- In-app notifications + email outbox (emails logged, not sent, in mockup).

### Out of scope
- Mobility **not** tied to a PCU MoU/MoA (IISMA, free movers, government scholarships). KPI 1.1 is officially MoU/MoA-based.
- Import of pre-system (spreadsheet) realization data. History starts at go-live; every frozen semester stays downloadable afterwards.
- Real BAAK/HR integration (mocked; API contract defined in Architecture §6).
- Internal student transcripts (available in BAAK; not uploaded).
- Partner-side access.

---

## 4. Users & roles

| Role | Who | Can do |
|---|---|---|
| `submitter` | UA/UP accounts (role-based unit emails, same as SIM Kerjasama) | Create/submit activities for own unit; respond to revisions; view own unit's activities and counts |
| `io_staff` + team `partnership` | IO Partnership team | Verify Detail + File; request revision; reject; link duplicates; manage Known Activities register; edit verified activities (logged) |
| `io_staff` + team `mobility` | IO Mobility team | Verify participant sets; request revision; view transcripts; edit verified participant data (logged) |
| `io_admin` | Head of IO / IO admin | Everything above + settings, Jenis master, freeze/unfreeze snapshots, reopen frozen data |
| `viewer` | Rektorat / stakeholders | Dashboard, KPI drill-down at activity level (no participant personal data), exports of non-personal reports |

Team membership is an attribute on top of the SIM Kerjasama application role (`io_staff`); `io_admin` belongs to both teams.

---

## 5. Core concepts

- **Activity** — one realization event. Has exactly one IA and one IR (1:1, DIKTI-aligned). A multi-year program submits a new activity (with its own IA/IR) each round.
- **Linked agreement(s)** — one or more SIM Kerjasama documents the activity implements. Stores both `original_document_id` (never changes) and `current_document_id` (follows renewals).
- **Renewal chain** — a document plus all its renewal predecessors/successors. KPI 1.19.24 counts **chains**, not document rows, so a mid-year renewal never double-counts.
- **Event group** — groups activities that are the same real event submitted by different units. University-level counts dedupe by event group; unit-level counts don't.
- **Participant set** — the versioned list of PETRA students, PETRA staff, and inbound (external) students for an activity. Mobility approves a specific version.
- **External persons** — structured list of foreign speakers / visiting lecturers / guests (replaces "Pembicara / Dosen Asing" and "Peserta Pegawai Eksternal"). Part of Detail; verified by Partnership.
- **Known activity** — an IO-logged record of an international activity discovered outside the SIM (Surat Tugas, news, faculty report, LoA/visa letter). Used as the S8 denominator gap.
- **Snapshot** — frozen KPI values at a semester cutoff, with the underlying record IDs stored for drill-down and export.

---

## 6. Process flows

### 6.1 Submission (UA/UP)
1. Unit opens **New Activity**; fills **Detail**, **Peserta**, **File**; can save as Draft.
2. Activity must have ended (Tanggal Selesai ≤ today) — IR can't exist before.
3. Agreement picker shows documents **valid on the activity dates** (including now-archived ones). Partner + country auto-fill and are snapshotted.
4. Peserta: paste/upload NRPs and employee IDs → lookup auto-fills name, faculty, prodi. Unknown IDs block submission. Inbound students: NRP lookup + home institution + transcript PDF each.
5. Submit (Ajukan) → status `in_verification`; both tracks start (Mobility only if participants exist or the Jenis requires it).
6. Reporting deadline: Tanggal Selesai + 30 days (configurable). Late submissions are accepted and flagged.

### 6.2 Partnership verification (Detail + File + External persons)
- **Approve** → track `approved`.
- **Request revision** (note required) → unit edits Detail/files/external persons → resubmit → track back to `pending`. Mobility track untouched unless Jenis Kegiatan changed (see Rules R-24).
- **Reject** (reason required: duplicate / not a partnership activity / wrong agreement / other) → terminal. Unit may create a new activity.
- **Link duplicate** → merges event groups.

### 6.3 Mobility verification (Peserta)
- Reviews the current participant-set version, incl. inbound transcripts.
- **Approve** → version `approved`, track `approved`; participant rows now count.
- **Request revision** (note required, optional per-row notes) → unit uploads a new version → `pending`. Previous versions are kept (revision history with diff).

### 6.4 Verified
Activity becomes `verified` when Partnership = approved **and** Mobility = approved or not_required. Only verified activities count in KPIs.

### 6.5 Post-verification edits
IO only (Partnership for Detail/File, Mobility for Peserta, Admin both). Every change goes to the Update Log with a field diff. Edits touching a frozen period don't alter the snapshot; they're listed as "post-freeze changes" in the next report.

### 6.6 Semester close
- Each semester has a **cutoff date** (default: semester end + 30 days).
- On the cutoff date the system computes and **freezes** a snapshot (Ganjil = YTD, Genap = full year). IO Admin can also freeze manually or re-freeze with a logged reason.
- Activities verified after a freeze but dated inside the frozen period appear as **late additions** in the next snapshot's report; frozen numbers never change.

### 6.7 Known Activities (S8)
- Partnership team logs activities discovered elsewhere.
- System suggests matches to SIM activities (same unit, date ±7 days, name similarity); IO confirms match or dismisses.
- Unmatched entries → "Nudge unit" sends a notification asking the unit to submit.

---

## 7. Functional requirements

### 7.1 Activity form
**Detail**
| Field | Type | Rule |
|---|---|---|
| Nama Kegiatan | text | required |
| Jenis Kegiatan | select (master) | required; drives KPI flags |
| Tanggal Mulai / Selesai | date | required; Selesai ≥ Mulai; Selesai ≤ today |
| Semester & Tahun Akademik | derived | from Tanggal Mulai via academic calendar; read-only |
| Moda | offline / online / hybrid | required |
| Tempat Pelaksanaan | venue, city, country | required (online: platform name) |
| Durasi | derived days | read-only |
| SKS diakui | number | optional |
| Sumber Dana | PCU / partner / government / participant / mixed / none | optional |
| Deskripsi | long text | required |
| Unit | multi-select (unit master) | submitter unit locked + co-units |
| Kerjasama | multi-select (agreements valid on activity dates) | required ≥1; warning if unit outside Lingkup Kerja Sama |
| Mitra / Negara | auto | snapshotted from agreements |
| SDG | multi-select (1–17) | optional |
| Pembicara / Dosen Asing / Tamu | structured rows: name, institution, country, role | optional |

**Peserta**
- PETRA students — NRP list (paste or Excel template) → lookup.
- PETRA staff — employee ID list → lookup.
- Inbound students — NRP lookup (must exist as `inbound_exchange` in BAAK) + home institution + home student number + transcript PDF.

**File**
- IA (PDF, required), IR (PDF, required), Evidence (photos/PDF/links, optional, multiple). All versioned.

### 7.2 Queues & lists
- Unit: My Activities (filters, status, SLA, deadline flags), Revision inbox.
- Partnership: Verification queue (SLA-sorted), Duplicate candidates, Known Activities register.
- Mobility: Participant verification queue (SLA-sorted), version diff view.
- All activities list (IO/viewer) with per-column filters → Excel export of filtered view.

### 7.3 Dashboard
- Period selector: academic year × {Ganjil YTD, Full year, Live}. Frozen periods show snapshot values with "Frozen on …" badge.
- 4 KPI cards → drill-down list → activity detail.
- Charts: inbound vs outbound per semester; activities by country; by unit; by SDG; realization % by unit; top partners.
- Snapshot archive: every frozen snapshot, downloadable as Excel.

### 7.4 Exports (Excel, every report)
1. KPI summary (period) + one sheet per KPI with underlying rows
2. Activity list (filtered view)
3. Participant list — Mobility / IO Admin only
4. Known Activities register (matched/unmatched)
5. Frozen snapshot workbook (summary + items + late additions + post-freeze changes)
6. Realization by agreement (chain) — realized / not realized / grace-excluded
7. Verification SLA report (per activity, per track)

### 7.5 Settings (IO Admin)
- Academic calendar: years, semester ranges, cutoff dates
- Grace period (default **6 months**)
- Reporting deadline (default **30 days** after Tanggal Selesai)
- Verification SLA (default yellow **>3**, red **>5** business days)
- Unit revision reminders (default reminder **7 days**, escalate to IO **14 days**)
- Duplicate detection window (default ±3 days) and name similarity (default 0.5)
- Jenis Kegiatan master with flags
- Indonesian public holidays (for business-day calculation)

### 7.6 SIM Kerjasama integration
- Document detail → **Realisasi** tab: verified activities on the whole renewal chain, counts by year, latest activity date.
- Active document list → "No realization this academic year" flag (respecting the grace period).
- Renewal evaluation screen → realization summary shown as evidence.

### 7.7 Notifications (in-app + email outbox)
| Event | Recipient |
|---|---|
| Submission received | Partnership team (+ Mobility if required) |
| Revision requested | Submitting unit |
| Revision reminder / escalation | Unit / IO |
| Activity verified or rejected | Submitting unit |
| Verification SLA yellow / red | Assigned team / IO Admin |
| Reporting deadline H-7, H, weekly after | Units with activities ending in range* |
| Duplicate candidate detected | Partnership team |
| Known-activity nudge | Unit |
| Snapshot frozen | IO Admin, viewers |

\*Deadline reminders only apply to Drafts (the system can't know about activities never started).

---

## 8. Non-functional requirements
- **Privacy (UU PDP 27/2022):** participant data and transcripts visible only to the submitting unit, Mobility team, and IO Admin; viewers see counts only; all participant exports logged.
- **Auditability:** no hard deletes; every state change and edit logged with actor and timestamp; file and participant versions retained.
- **Reproducibility:** snapshots store values + item IDs + settings used.
- **Performance (mockup):** dashboard < 2 s on seed data; exports < 10 s.
- **Language:** UI in Bahasa Indonesia with English field terms where IO already uses them (IA, IR, MoU, MoA).
- **Responsiveness:** desktop-first; usable on tablet.

---

## 9. Mockup acceptance — what must be demonstrable
1. Dual-track verification with independent revision loops (seed activity with a Mobility revision while Partnership is approved).
2. KPI 1.1 per-person-per-event counting; dedupe across a two-unit duplicate at university level, double-count at unit level.
3. KPI 1.19.24: grace-period exclusion, auto-renewed inclusion, renewal chain counted once.
4. Semester freeze; a late addition appearing in the next report without changing frozen values.
5. S8 with matched and unmatched known activities.
6. Every list and report downloadable as Excel.

---

## 10. Decision log

| # | Decision |
|---|---|
| D1 | S8 baseline = IO-side Known Activities register |
| D2 | 1.19.24 numerator counts IA only (MoA under MoU does **not** count as realization of the MoU) |
| D3 | Grace period configurable, default 6 months, measured from the chain's first start date |
| D4 | Auto-renewed agreements always in the 1.19.24 denominator |
| D5 | 1.1 counts per person per event; two units claiming one event → counted in both at unit level, deduped at university level |
| D6 | International vs domestic grouping derived from the agreement's partner country |
| D7 | Only students with an NRP are counted; inbound students are required to have an NRP (Rector's rule) |
| D8 | Only MoU/MoA-based activities are recorded |
| D9 | IA and IR both mandatory at submission; KPI lag accepted |
| D10 | One activity = one IA = one IR (DIKTI-aligned) |
| D11 | Partnership verifies Detail + File; Mobility verifies Peserta; both required to count |
| D12 | Activity links keep original + current document; validity checked against activity dates, not today |
| D13 | Jenis Kegiatan master with KPI flags drives counting |
| D14 | Internal participants via NRP/employee-ID lookup; inbound students upload transcripts for IO; external guests as structured list; participant revision history kept |
| D15 | Realization window = academic year; semesterly cutoff & frozen snapshots |
| D16 | Post-verification edits IO-only with Update Log |
| D17 | Every report exportable to Excel; frozen semesters always downloadable |
| D18 | Shares stack & database with SIM Kerjasama |
| D19 | BAAK/HR mocked with dummy data; NRP format randomized for the mockup |

---

## 11. Open items (for production, not blocking the mockup)
1. Real BAAK/HR integration method (API vs DB view vs scheduled CSV) and owner (PSI).
2. Whether internal outbound students need a transcript snapshot at activity time.
3. Final production stack decision (shared with SIM Kerjasama: fresh build vs extending SIMKS).
4. Official Jenis Kegiatan list and KPI-flag mapping from IO.
5. Official academic calendar cutoff dates for 2026/2027.
