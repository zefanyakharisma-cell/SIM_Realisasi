# SIM Realisasi — Design
**Version:** 1.0 (Mockup) · Inherits the SIM Kerjasama v2.0 design system (tokens, typography, components). This doc only defines what's new.

---

## 1. Navigation
Sidebar section **Realisasi** under the shared app shell (SIM Kerjasama stays as its own section):

| Item | submitter | io partnership | io mobility | io_admin | viewer |
|---|---|---|---|---|---|
| Dashboard | ✓ (own unit) | ✓ | ✓ | ✓ | ✓ |
| Kegiatan | ✓ | ✓ | ✓ | ✓ | ✓ (verified) |
| + Kegiatan Baru | ✓ | — | — | ✓ | — |
| Verifikasi Kemitraan | — | ✓ (badge = queue count) | — | ✓ | — |
| Verifikasi Mobilitas | — | — | ✓ (badge) | ✓ | — |
| Duplikat | — | ✓ (badge) | — | ✓ | — |
| Kegiatan Diketahui | — | ✓ | — | ✓ | — |
| Laporan & Ekspor | ✓ (own unit) | ✓ | ✓ | ✓ | ✓ |
| Pengaturan | — | — | — | ✓ | — |

---

## 2. Status language
| Status | Label (ID) | Badge colour |
|---|---|---|
| draft | Draf | neutral grey |
| in_verification | Dalam Verifikasi | blue |
| revision_requested | Perlu Revisi | amber |
| verified | Terverifikasi | green |
| rejected | Ditolak | red |

**Track chips** shown side by side on every activity row: `Kemitraan ●` `Mobilitas ●` — dot colour = track status (grey not required, blue pending, amber revision, green approved, red rejected).

**Flags** (small pill, outline):
- `Terlambat` (late submission) — amber outline
- `SLA 4 hari` — yellow fill when yellow, red fill when red
- `Di luar lingkup` (unit outside Lingkup Kerja Sama) — grey outline with info tooltip
- `Duplikat?` — purple outline, links to candidate
- `Tambahan susulan` (late addition, in reports) — blue outline

---

## 3. Screens

### 3.1 Dashboard
- **Header:** period selector — Tahun Akademik dropdown + segmented control `Ganjil (YTD) | Setahun | Live`. Frozen periods show a lock badge "Dibekukan 2 Mar 2026".
- **KPI row (4 cards):** big number, sub-line (e.g. "Inbound 42 · Outbound 118"), delta vs same period last year; click → drill-down.
  - 1.19.24 card shows % + "38 dari 61 kerja sama" + small "7 dalam masa tenggang".
  - 1.19.S8 card shows % + "3 kegiatan belum dilaporkan" link → register filtered to unmatched.
- **Charts (2-column grid):** Inbound vs Outbound per semester (grouped bar) · Kegiatan per negara (horizontal bar, top 10) · Kegiatan per unit · SDG coverage (17-cell grid heatmap) · Realisasi % per unit · Mitra teraktif.
- **Submitter view:** same layout scoped to own unit; adds "Draf mendekati tenggat" list.
- Every card/chart has a ⋯ menu → "Unduh Excel".

### 3.2 Kegiatan list
- Table: Kode · Nama · Jenis · Unit · Mitra (flag + name) · Tanggal · Semester · Status · Track chips · Flags.
- Per-column filters (same pattern as SIM Kerjasama lists); "Unduh Excel" exports the filtered view.
- Saved filter chips: `Perlu tindakan saya`, `Terlambat`, `Semester ini`.

### 3.3 Submission wizard (`/kegiatan/baru`)
Stepper: **1 Detail → 2 Peserta → 3 Berkas → 4 Tinjau & Ajukan**. Autosave indicator top-right ("Tersimpan sebagai draf · 10:42").

**Step 1 — Detail**
- Two-column form. Semester & Tahun Akademik appear as read-only text that updates live after Tanggal Mulai.
- Jenis Kegiatan select shows a helper line from its flags: "Dihitung sebagai mobilitas outbound — wajib isi peserta mahasiswa PETRA".
- **Kerjasama picker** (combobox, multi): disabled until dates are filled; each option shows `doc number · MoU/MoA · partner · 🇯🇵 · berlaku s.d. 2028-05-01`, archived ones tagged `Arsip (diperbarui)`. Selected agreements render as cards with auto-filled Mitra + Negara (read-only). Out-of-scope warning appears inline under the card.
- **Pembicara / Dosen Asing / Tamu**: repeatable row group (Nama, Institusi, Negara, Peran) with "+ Tambah orang".
- SDG: 17 toggle chips with official colours.

**Step 2 — Peserta**
Three collapsible panels, each with a count in the header:
1. *Mahasiswa PETRA* — textarea "Tempel NRP (satu per baris)" + "Unggah template Excel" + "Unduh template". After **Cek NRP**: result table with ✓ found (name, fakultas, prodi), ✗ not found (row red, blocks submit), ⚠ graduated/inactive (amber, allowed).
2. *Pegawai PETRA* — same pattern with employee ID.
3. *Mahasiswa Inbound* — NRP lookup, then per row: Institusi asal (prefilled from BAAK, editable), No. mahasiswa asal, Negara asal, Transkrip (PDF drop zone, required).
- Panels the Jenis makes mandatory show a red "Wajib" tag.

**Step 3 — Berkas**
- Two required drop zones: Implementation Arrangement (PDF), Implementation Report (PDF) — show filename, size, version, preview button.
- Bukti (optional): multi-file drop zone + "Tambah tautan".

**Step 4 — Tinjau & Ajukan**
- Read-only summary of all sections; checklist of validation results; late-submission notice if past deadline ("Batas pelaporan 14 Sep 2026 telah lewat — kegiatan tetap dapat diajukan dan akan ditandai Terlambat").
- Primary button **Ajukan**; secondary **Simpan Draf**.

### 3.4 Activity detail (`/kegiatan/[id]`)
- Header: code, name, status badge, track chips, flags; action bar by role (Approve / Minta Revisi / Tolak / Tautkan Duplikat / Edit).
- Tabs: **Detail** · **Peserta** (version selector `v1 · v2 (disetujui)`) · **Berkas** (with version history) · **Riwayat** (merged log: verification, revision, update — filter by kind; update entries show field diffs).
- Revision banner (amber) at top for the unit: who requested, note, which track, "Perbaiki sekarang" button.

### 3.5 Verification queues
- **Kemitraan:** table sorted by SLA (red first). Row expands inline to show Detail + IA/IR preview side by side so short checks don't need a page change. Actions in the expanded row.
- **Mobilitas:** same pattern; expanded row shows the participant set with **version diff** vs previous version — added rows green, removed red strike-through, changed cells highlighted; per-row note field when requesting revision; transcript opens in a side sheet.
- Action dialogs: revision and reject require a note (reject also requires a reason select).

### 3.6 Duplikat
- Card per candidate: two activities side by side (name, unit, dates, agreement, participant count) + similarity score. Buttons: **Tautkan sebagai satu kegiatan** · **Bukan duplikat**.

### 3.7 Kegiatan Diketahui (register)
- Table: Tanggal · Judul · Unit · Mitra/Negara · Sumber · Status (Belum dilaporkan / Cocok / Diabaikan) · Kegiatan SIM.
- "+ Catat kegiatan" side sheet form.
- Unmatched rows show suggested matches (score) with **Cocokkan**; plus **Ingatkan unit** (disabled + timestamp after sending).

### 3.8 Laporan & Ekspor
- Left: report list (Ringkasan KPI, per-KPI drill-down, Daftar kegiatan, Daftar peserta*, Register, Realisasi per kerja sama, SLA verifikasi, Arsip snapshot). *Hidden for roles without access.
- Right: filters + preview table + **Unduh Excel**.
- **Arsip snapshot:** timeline of frozen snapshots per academic year; each shows frozen date, by whom/job, superseded state, refreeze reason; download button.

### 3.9 Pengaturan (io_admin)
- Tabs: Umum (grace period, reporting deadline, SLA, reminders, duplicate thresholds) · Kalender Akademik (year/semester table with cutoff dates; freeze status per row; **Bekukan sekarang** / **Bekukan ulang**) · Jenis Kegiatan (table with flag toggles; deactivate instead of delete) · Hari Libur.
- Changing a setting shows "Berlaku untuk perhitungan live; snapshot yang sudah dibekukan tidak berubah."

### 3.10 SIM Kerjasama → Realisasi tab
- Summary strip: Total kegiatan · Tahun akademik ini · Mahasiswa (in/out) · Kegiatan terakhir.
- Table of verified activities across the renewal chain, with a column "Dokumen saat kegiatan" (original document number).
- Empty state: "Belum ada realisasi untuk kerja sama ini" (+ "Dalam masa tenggang hingga …" when applicable).

---

## 4. Empty, loading, error states
| Place | Empty state copy |
|---|---|
| Unit Kegiatan list | "Belum ada kegiatan. Laporkan realisasi kerja sama pertama unit Anda." + CTA |
| Verification queue | "Tidak ada antrean verifikasi. 🎉" |
| Register | "Belum ada kegiatan dicatat dari sumber lain." |
| Lookup error | "Layanan data mahasiswa tidak dapat dihubungi. Coba lagi." (retry) |
| Export > 10 s | progress toast, download starts when ready |

---

## 5. Excel output style
- Header row bold, frozen, autofilter on; column widths fitted.
- Dates `dd-mm-yyyy`; percentages with 1 decimal.
- First sheet **Info** (kind, filters, generated by/at, data as-of).
- Snapshot workbooks: `Ringkasan`, `1.1`, `1.19.S1`, `1.19.24`, `1.19.S8`, `Tambahan Susulan`, `Perubahan Pasca-Beku`.

---

## 6. Accessibility
- Status never conveyed by colour alone (badge text + dot + tooltip).
- All wizard fields labelled; errors announced inline and summarised at top of the step.
- Keyboard: queue rows expand with Enter; dialogs trap focus.
