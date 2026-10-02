# SIM Realisasi: business process (BPMN, Bizagi style)

Two BPMN 2.0 process models of SIM Realisasi, following [`../spec/Rules.md`](../spec/Rules.md) v1.1 (Revisi V.1).
Each one comes as a `.bpmn` file (BPMN 2.0 XML with diagram layout) and a Bizagi-styled `.svg` render.

| Process | Files |
|---|---|
| 1. Pengajuan & Verifikasi Kegiatan | [`sim-realisasi-pengajuan-verifikasi.bpmn`](sim-realisasi-pengajuan-verifikasi.bpmn) · [`.svg`](sim-realisasi-pengajuan-verifikasi.svg) |
| 2. Pengingat, Tutup Semester & Pelaporan | [`sim-realisasi-tutup-semester.bpmn`](sim-realisasi-tutup-semester.bpmn) · [`.svg`](sim-realisasi-tutup-semester.svg) |

**Opening in Bizagi Modeler:** File → Import → *BPMN 2.0* (or *Import → BPMN*), then pick the `.bpmn` file.
Pools, lanes, tasks (user / service / send), gateways, timer and conditional start events, sequence flows and
message flows come in with their positions. Bizagi applies its own default colours on import; the `.svg` shows the
intended look. The files also open in [bpmn.io](https://demo.bpmn.io) and Camunda Modeler.

**Regenerating:** the layout lives in [`generate.py`](generate.py) (no dependencies). After editing it run
`python3 docs/bpmn/generate.py`, which rewrites all four files.

## 1. Pengajuan & Verifikasi Kegiatan

Pool *SIM Realisasi* with lanes **Unit Akademik (Pengaju)**, **Tim Mobilitas IO**, **SIM Realisasi (Sistem)**;
collapsed pools **SIM Kerjasama** and **BAAK & HR**.

| # | Lane | Step | Rule |
|---|---|---|---|
| 1 | Unit | Kegiatan selesai → isi Detail & pilih satu Kerja Sama (dokumen berlaku pada tanggal kegiatan, dari SIM Kerjasama) | R-03, R-04, R-08 |
| 2 | Sistem | Simpan draf; turunkan semester/TA dari Tanggal Mulai; batas pelaporan = Tanggal Selesai + 30 hari | R-07, R-09, R-10 |
| 3 | Unit | Gateway *Kegiatan mobilitas?* (dari aturan Jenis Kegiatan / Agenda) | R-07a, R-11 |
| 4a | Unit | Tidak: unggah IA & IR (PDF) + bukti opsional | R-13 |
| 4b | Unit → Sistem | Ya: isi peserta (NRP, NIP, inbound) → lookup ke BAAK & HR; ID tak dikenal kembali ke unit | R-12, R-16–R-19, R-22 |
| 4c | Unit | Unggah IA, IR & satu PDF mobilitas (transkrip, poster, dokumentasi) | R-11 |
| 5 | Unit → Sistem | Ajukan → validasi; tandai *Terlambat* bila lewat batas | R-07, R-10 |
| 6 | Sistem | Non-mobilitas: track `not_required`, langsung **Terverifikasi** | R-11, R-25, AT-04 |
| 7 | Sistem | Mobilitas: track `pending`, deteksi duplikat mahasiswa antar-unit, notifikasi tim | R-33 |
| 8 | Mobilitas | Tinjau peserta & PDF; bila ada duplikat, pilih kegiatan yang mempertahankan mahasiswa (persetujuan terblokir selama konflik terbuka) | R-27a, R-34 |
| 9 | Mobilitas → Unit | Tidak sesuai: minta revisi (satu catatan wajib) → unit memperbaiki & mengajukan ulang (versi peserta n+1) → kembali ke langkah 7 | R-21, R-24, R-26, R-27 |
| 10 | Mobilitas → Sistem | Sesuai: setujui versi peserta → **Terverifikasi**, `verified_at`, notifikasi unit | R-21, R-25, R-28 |
| 11 | Sistem | Hitung ke RENSTRA & International Awards; kirim ringkasan ke tab Realisasi SIM Kerjasama | R-36–R-50 |

Tidak ada penolakan: kiriman yang salah selalu kembali sebagai revisi (R-26).

## 2. Pengingat, Tutup Semester & Pelaporan

Lanes **Unit Akademik**, **SIM Realisasi (Sistem)**, **IO Admin**, **Pimpinan (Viewer)**. Three independent starts:

- **Setiap hari (timer):** cek draf menjelang batas pelaporan (H-7, H, lalu mingguan) dan revisi tertunda ≥ 7 hari →
  kirim pengingat in-app + email outbox → unit melengkapi/mengajukan (R-61, R-62).
- **Tanggal cutoff semester (timer, akhir semester + 30 hari):** hitung RENSTRA 1.1, 1.19.S1, 1.19.24 & Awards →
  bekukan snapshot (nilai, ID kontributor, pengaturan) → notifikasi → IO Admin meninjau; bila perlu, bekukan ulang
  dengan alasan wajib (snapshot lama menjadi `superseded`) → unduh workbook Excel → pimpinan meninjau dashboard
  & drill-down (R-55–R-59).
- **Kegiatan diverifikasi/diubah bertanggal di periode beku (conditional):** tandai *Tambahan Susulan* /
  *Perubahan Pasca-Beku*, tampilkan di YTD dan laporan snapshot berikutnya; snapshot lama tidak berubah (R-31, R-57).
