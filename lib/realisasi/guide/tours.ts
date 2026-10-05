/**
 * Mode Demo coach-mark tours: one tour per page, each step spotlights a real element and explains
 * it. Pure data, safe to import anywhere. Targets reuse the stable `data-testid`/`id` selectors the
 * e2e suite already relies on (plus a few `data-tour` attributes); steps whose target is missing or
 * hidden for the current role/screen are skipped by the tour engine. A step without a target is
 * shown as a centered pop-up. Wording follows the UI labels and docs/spec/Rules.md (Revisi V.1).
 */

export type TourSide = 'top' | 'right' | 'bottom' | 'left';

export interface TourStep {
  /** CSS selector of the element to spotlight; omitted → centered pop-up. */
  target?: string;
  title: string;
  body: string;
  tip?: string;
  side?: TourSide;
  /** Skip this step when this selector matches (e.g. an overview step that a more specific one replaces). */
  unless?: string;
}

export interface Tour {
  id: string;
  title: string;
  steps: TourStep[];
}

const tid = (id: string) => `[data-testid="${id}"]`;
const tour = (id: string) => `[data-tour="${id}"]`;

export const LOGIN_TOUR: Tour = {
  id: 'login',
  title: 'Halaman masuk',
  steps: [
    {
      title: 'Selamat datang di SIM Realisasi 👋',
      body: 'Aplikasi ini mencatat, memverifikasi, dan melaporkan setiap realisasi (pelaksanaan) MoU/MoA Petra Christian University yang tersimpan di SIM Kerjasama.',
      tip: 'Gunakan tombol Berikutnya, panah kiri/kanan pada keyboard, atau Esc untuk melewati tur.',
    },
    {
      title: 'Satu kegiatan = satu IA + satu IR',
      body: 'Setiap realisasi dilaporkan sebagai satu Kegiatan, dilengkapi Implementation Arrangement (IA) dan Implementation Report (IR), serta terhubung ke satu kerja sama yang berlaku pada tanggal kegiatan.',
    },
    {
      title: 'Hanya kegiatan terverifikasi yang dihitung',
      body: 'Kegiatan non-mobilitas langsung Terverifikasi saat diajukan. Kegiatan mobilitas (exchange, double degree, short program) diperiksa Tim Mobilitas lebih dulu. Dashboard RENSTRA hanya menghitung kegiatan Terverifikasi.',
    },
    {
      target: tid('demo-mode-toggle'),
      title: 'Sakelar Mode Demo',
      body: 'Sakelar ini menyalakan tur yang sedang Anda ikuti. Selama aktif, setiap halaman menjelaskan dirinya sendiri saat pertama kali dibuka.',
      tip: 'Pilihan ini hanya tersimpan di peramban Anda. Matikan kapan saja di sini atau lewat tombol Panduan di aplikasi.',
      side: 'bottom',
    },
    {
      target: tid('demo-auth-notice'),
      title: 'Masuk tanpa kata sandi',
      body: 'Ini mockup: Anda masuk dengan memilih akun demo. Pada versi produksi, halaman ini diganti SSO institusi.',
    },
    {
      target: tour('account-list'),
      title: 'Daftar akun demo',
      body: 'Setiap akun mewakili satu peran. Menu dan tombol yang tampil di aplikasi menyesuaikan peran akun yang dipilih.',
      side: 'top',
    },
    {
      target: '[data-testid^="login-"]',
      title: 'Kartu akun',
      body: 'Kartu menampilkan nama, lencana peran, unit, dan tim. Admin IO dapat mengakses semua menu termasuk Pengaturan; Staf IO memverifikasi mobilitas; Pengaju Unit melaporkan kegiatan; Pimpinan hanya melihat.',
      tip: 'Klik kartu untuk masuk. Ganti peran nanti lewat menu akun → "Ganti akun".',
    },
    {
      title: 'Siap mencoba',
      body: 'Pilih salah satu akun di bawah. Setelah masuk, tur dasar aplikasi dimulai, lalu setiap halaman memandu Anda saat pertama kali dibuka.',
      tip: 'Saran: mulai sebagai Admin IO untuk melihat semua fitur, lalu coba Pengaju Unit untuk alur pelaporan.',
    },
  ],
};

export const SHELL_TOUR: Tour = {
  id: 'shell',
  title: 'Tur dasar aplikasi',
  steps: [
    {
      title: 'Tur dasar aplikasi',
      body: 'Mari kenali bagian-bagian yang selalu ada di setiap halaman: menu navigasi, notifikasi, akun, dan tombol Panduan.',
    },
    {
      target: tid('nav-realisasi'),
      title: 'Dashboard',
      body: 'Ringkasan capaian RENSTRA, grafik, International Awards, dan daftar pekerjaan yang perlu diproses.',
      side: 'right',
    },
    {
      target: tid('nav-kegiatan'),
      title: 'Kegiatan',
      body: 'Daftar semua kegiatan yang boleh Anda lihat, dengan filter dan ekspor Excel. Lencana kuning menandai kegiatan yang perlu direvisi unit.',
      side: 'right',
    },
    {
      target: tid('nav-baru'),
      title: 'Kegiatan Baru',
      body: 'Formulir satu halaman untuk melaporkan kegiatan yang sudah selesai: detail, kerja sama, peserta, berkas, lalu ajukan.',
      side: 'right',
    },
    {
      target: tid('nav-mobilitas'),
      title: 'Verifikasi Mobilitas',
      body: 'Antrean kegiatan mobilitas yang menunggu verifikasi dan mahasiswa duplikat antar unit. Angka di lencana = jumlah yang perlu diproses.',
      side: 'right',
    },
    {
      target: tid('nav-laporan'),
      title: 'Laporan & Ekspor',
      body: 'Semua laporan RENSTRA, daftar kegiatan, peserta, International Awards, realisasi per kerja sama, dan arsip snapshot, masing-masing dapat diunduh sebagai Excel.',
      side: 'right',
    },
    {
      target: tid('nav-pengaturan'),
      title: 'Pengaturan',
      body: 'Khusus Admin IO: batas pelaporan, masa tenggang, kalender akademik dan cutoff, pembekuan snapshot, aturan Jenis Kegiatan, serta simulasi tanggal untuk demo.',
      side: 'right',
    },
    {
      target: tour('mobile-menu'),
      title: 'Menu navigasi',
      body: 'Di layar kecil, menu navigasi ada di balik tombol ini: Dashboard, Kegiatan, Verifikasi, Laporan, dan lainnya.',
    },
    {
      target: tid('notification-bell'),
      title: 'Notifikasi',
      body: 'Pengajuan baru, permintaan revisi, pengingat batas pelaporan, dan snapshot beku muncul di sini. Angka merah = belum dibaca.',
      side: 'bottom',
    },
    {
      target: tid('user-menu'),
      title: 'Menu akun',
      body: 'Menampilkan nama, peran, unit, dan tim Anda. Dari sini pilih "Ganti akun" untuk mencoba peran lain, atau "Keluar".',
      side: 'bottom',
    },
    {
      target: tid('demo-today-banner'),
      title: 'Simulasi tanggal aktif',
      body: 'Spanduk ini muncul ketika Admin IO mengubah "hari ini" untuk demo, sehingga semua perhitungan tanggal memakai tanggal simulasi.',
    },
    {
      target: tid('demo-guide-open'),
      title: 'Tombol Panduan',
      body: 'Buka tombol ini untuk mengulang tur halaman yang sedang dibuka, mengulang tur dasar ini, atau mematikan Mode Demo.',
      side: 'top',
    },
  ],
};

const DASHBOARD_TOUR: Tour = {
  id: 'dashboard',
  title: 'Dashboard',
  steps: [
    {
      target: tour('page-header'),
      title: 'Dashboard Realisasi',
      body: 'Halaman utama. Baris di bawah judul menunjukkan lingkup data (universitas atau unit Anda) dan periode yang sedang dilihat.',
    },
    {
      target: tour('page-actions'),
      title: 'Status periode',
      body: '"Live s.d. <tanggal>" berarti angka dihitung langsung dari data saat ini. "Dibekukan <tanggal>" berarti angka dibaca dari snapshot beku dan tidak akan berubah lagi.',
      side: 'left',
    },
    {
      target: '#period-ay',
      title: 'Tahun Akademik',
      body: 'Pilih tahun akademik yang ingin dilihat. Semua kartu, grafik, dan ekspor di halaman ini mengikuti pilihan ini.',
    },
    {
      target: 'nav[aria-labelledby="period-seg-label"]',
      title: 'Periode',
      body: 'Ganjil dan Genap = satu semester. Setahun (kumulatif) = seluruh tahun akademik. YTD = awal tahun akademik sampai hari ini, tidak pernah dibekukan.',
    },
    {
      target: '#period-unit',
      title: 'Lingkup',
      body: 'Admin, staf IO, dan pimpinan dapat mempersempit dashboard ke satu unit. Pengaju Unit selalu melihat unitnya sendiri.',
    },
    {
      target: 'nav[aria-label="Tab dashboard"]',
      title: 'Capaian Renstra & International Awards',
      body: 'Tab Capaian Renstra berisi indikator dan grafik. Tab International Awards berisi papan peringkat Program Studi: Inbound, Outbound Dalam Negeri, Outbound Internasional, dan Inisiatif Internasional.',
    },
    {
      target: tid('work-queue'),
      title: 'Perlu diproses',
      body: 'Daftar kerja Tim Mobilitas: kegiatan menunggu verifikasi (terlama di atas), mahasiswa duplikat yang belum diputuskan, dan kegiatan yang menunggu revisi unit. Klik baris untuk langsung membukanya.',
    },
    {
      target: tid('drafts-near-deadline'),
      title: 'Draf mendekati tenggat',
      body: 'Draf unit Anda yang mendekati batas pelaporan (Tanggal Selesai + 30 hari). Pengajuan setelah batas tetap diterima, tetapi diberi tanda Terlambat.',
    },
    {
      target: tid('kpi-card-1.1'),
      title: 'RENSTRA 1.1 — Mahasiswa inbound & outbound',
      body: 'Jumlah pasangan (NRP, kegiatan) dari daftar peserta yang disetujui. Satu mahasiswa di dua kegiatan dihitung 2; mahasiswa duplikat antar unit dihitung sekali, di unit yang dipilih Tim Mobilitas.',
      tip: 'Klik judul atau angka untuk membuka rincian kegiatan di balik angka ini.',
    },
    {
      target: tid('kpi-card-1.19.S1'),
      title: 'RENSTRA 1.19.S1 — Kegiatan internasional',
      body: 'Kegiatan terverifikasi dengan mitra luar negeri yang Jenis Kegiatannya dihitung untuk S1. Angka domestik ditampilkan sebagai pembanding.',
    },
    {
      target: tid('kpi-card-1.19.S4'),
      title: 'RENSTRA 1.19.S4 — MoU & MoA terlaksana',
      body: 'Persentase rantai kerja sama aktif yang punya minimal satu kegiatan terverifikasi. Perpanjangan dihitung satu rantai; kerja sama baru dalam masa tenggang 6 bulan dikeluarkan dari penyebut.',
    },
    {
      target: `${tid('kpi-card-1.1')} button[aria-label^="Menu"]`,
      title: 'Menu kartu (⋯)',
      body: 'Setiap kartu dan grafik punya menu ini untuk mengunduh angka beserta rinciannya sebagai Excel.',
      side: 'left',
    },
    {
      target: tid('kpi-grace-link'),
      title: 'Kerja sama dalam masa tenggang',
      body: 'Jumlah kerja sama yang dikeluarkan dari perhitungan karena masih baru. Klik untuk membuka rincian 1.19.S4: mereka tidak disembunyikan, hanya dipisahkan.',
    },
    {
      target: tid('chart-mobility_by_semester'),
      title: 'Grafik',
      body: 'Grafik inbound vs outbound per semester, kegiatan per negara, per unit, per SDG, dan persentase realisasi per unit. Arahkan kursor ke batang untuk melihat angkanya.',
      tip: 'Menu ⋯ di setiap grafik dapat menampilkan tabel data atau mengunduh Excel.',
    },
  ],
};

const AWARDS_TOUR: Tour = {
  id: 'dashboard-awards',
  title: 'International Awards',
  steps: [
    {
      target: 'nav[aria-label="Tab dashboard"]',
      title: 'International Awards',
      body: 'Papan peringkat per Program Studi pengaju, memakai kegiatan terverifikasi dan aturan duplikat yang sama dengan RENSTRA 1.1. Setiap papan diurutkan dari total tertinggi.',
    },
    {
      target: 'nav[aria-labelledby="period-seg-label"]',
      title: 'Periode tetap berlaku',
      body: 'Peringkat mengikuti periode dan tahun akademik yang dipilih, sama seperti tab Capaian Renstra.',
    },
    {
      target: '#main-content table',
      title: 'Kolom papan peringkat',
      body: 'Mahasiswa dikelompokkan per kategori: JD/DD, Student Exchange, Short/Summer Program, dan Kegiatan Internasional (< 14 hari). Setiap mahasiswa dihitung di satu kolom.',
      side: 'top',
    },
  ],
};

const ACTIVITY_LIST_TOUR: Tour = {
  id: 'kegiatan',
  title: 'Daftar kegiatan',
  steps: [
    {
      target: tour('page-header'),
      title: 'Daftar kegiatan',
      body: 'Pengaju Unit melihat kegiatan unitnya dan unit lain yang melibatkannya; staf dan Admin IO melihat semua; pimpinan hanya yang terverifikasi.',
    },
    {
      target: tid('nav-kegiatan-baru-cta'),
      title: 'Kegiatan Baru',
      body: 'Pintasan ke formulir pelaporan kegiatan (hanya untuk Pengaju Unit dan Admin IO).',
      side: 'left',
    },
    {
      target: `${tour('page-actions')} ${tid('export-excel')}`,
      title: 'Unduh Excel',
      body: 'Mengunduh daftar sesuai filter yang sedang aktif. Lembar Info di workbook mencatat filter yang dipakai.',
      side: 'left',
    },
    {
      target: '[role="group"][aria-label="Filter cepat"]',
      title: 'Filter cepat',
      body: 'Tombol "Perlu tindakan saya" menyaring kegiatan yang menunggu tindakan Anda: untuk KUI, pengajuan yang perlu disetujui; untuk unit, draf dan kegiatan yang perlu direvisi.',
    },
    {
      target: tid('list-total'),
      title: 'Jumlah hasil',
      body: 'Jumlah kegiatan yang cocok dengan filter saat ini.',
    },
    {
      target: '#list-sort',
      title: 'Urutkan',
      body: 'Ubah urutan daftar: tanggal mulai terbaru/terlama, kode, atau paling lama menunggu.',
      side: 'left',
    },
    {
      target: tid('column-filters'),
      title: 'Filter per kolom',
      body: 'Baris di bawah judul tabel berisi filter untuk setiap kolom: cari nama/kode, Jenis Kegiatan, arah, unit, negara, tanggal, periode, status, dan tanda (Terlambat, duplikat).',
    },
    {
      target: tid('activity-row'),
      title: 'Baris kegiatan',
      body: 'Klik nama kegiatan untuk membuka detailnya. Lencana status (Draf, Dalam Verifikasi, Perlu Revisi, Terverifikasi) menjelaskan dirinya bila disorot kursor atau keyboard.',
    },
    {
      target: tid('filters-reset'),
      title: 'Reset filter',
      body: 'Menghapus semua filter dan kembali ke daftar lengkap.',
    },
  ],
};

const NEW_ACTIVITY_TOUR: Tour = {
  id: 'kegiatan-baru',
  title: 'Kegiatan Baru',
  steps: [
    {
      title: 'Melaporkan kegiatan baru',
      body: 'Kegiatan dilaporkan setelah selesai, dalam satu halaman dengan empat bagian. Mari lihat setiap isian dan tombolnya.',
    },
    {
      target: tour('form-sections'),
      title: 'Bagian formulir',
      body: 'Lompat cepat ke Detail & Kerja sama, Peserta, Berkas, dan Ajukan. Di sebelah kanan terlihat status simpan otomatis.',
    },
    {
      target: '#f-name',
      title: 'Nama Kegiatan',
      body: 'Nama resmi kegiatan, misalnya "Student Exchange Semester Ganjil di Hanyang University".',
    },
    {
      target: '#f-agenda_id',
      title: 'Jenis Kegiatan',
      body: 'Diambil dari daftar Agenda Kerjasama SIM Kerjasama. Jenis menentukan apakah kegiatan termasuk mobilitas (perlu peserta dan verifikasi) dan apakah dihitung untuk RENSTRA 1.19.S1.',
    },
    {
      target: '#f-direction',
      title: 'Inbound / Outbound',
      body: 'Outbound = mahasiswa PETRA pergi ke mitra; Inbound = mahasiswa mitra datang ke PETRA. Arah menentukan peserta wajib dan cara penghitungan RENSTRA 1.1.',
    },
    {
      target: '#f-start_date',
      title: 'Tanggal Mulai & Selesai',
      body: 'Tanggal Selesai tidak boleh melewati hari ini, karena IR baru ada setelah kegiatan selesai. Semester dan tahun akademik dihitung otomatis dari Tanggal Mulai.',
    },
    {
      target: tid('derived-period'),
      title: 'Periode otomatis',
      body: 'Semester dan tahun akademik hasil turunan tanggal mulai, dan tidak dapat diubah manual.',
    },
    {
      target: '#f-venue',
      title: 'Tempat pelaksanaan',
      body: 'Nama tempat untuk kegiatan offline/hybrid, atau nama platform untuk kegiatan online, beserta negaranya.',
    },
    {
      target: '#f-description',
      title: 'Deskripsi',
      body: 'Ringkasan singkat kegiatan: tujuan, bentuk kegiatan, dan hasilnya.',
    },
    {
      target: '#f-co_unit_ids',
      title: 'Unit lain yang terlibat',
      body: 'Tambahkan unit akademik lain yang ikut melaksanakan. Mereka mendapat akses baca ke kegiatan ini.',
    },
    {
      target: 'section[aria-labelledby="f-document_id-label"]',
      title: 'Kerja sama',
      body: 'Pilih satu MoU/MoA yang berlaku pada tanggal kegiatan (termasuk yang kini sudah diarsipkan). Mitra dan negara terisi otomatis. Bila unit Anda di luar lingkup kerja sama, muncul peringatan, tetapi pengajuan tidak diblokir.',
      tip: 'Isi tanggal terlebih dahulu agar daftar kerja sama muncul.',
    },
    {
      target: 'section[aria-labelledby="sec-persons"]',
      title: 'Pembicara / Dosen Asing / Tamu',
      body: 'Daftar tamu dari luar: nama, institusi, negara, dan peran. Mereka dicatat, tetapi tidak dihitung di RENSTRA 1.1.',
    },
    {
      target: 'section[aria-labelledby="sec-sdg"]',
      title: 'SDG',
      body: 'Pilih tujuan pembangunan berkelanjutan (1–17) yang relevan. Opsional; dipakai untuk grafik per SDG.',
    },
    {
      target: tid('wizard-save-draft'),
      title: 'Simpan Draf',
      body: 'Menyimpan Detail sebagai draf dan membuka bagian Peserta dan Berkas. Setelah itu perubahan tersimpan otomatis. Draf boleh dihapus; kegiatan yang sudah diajukan tidak pernah dihapus.',
      side: 'top',
    },
    {
      target: '#bagian-peserta',
      title: 'Peserta',
      body: 'Tempel atau unggah daftar NRP mahasiswa dan NIP pegawai; nama, fakultas, dan prodi terisi dari data BAAK/HR. NRP yang tidak dikenal ditandai merah dan menghalangi pengajuan.',
      tip: 'Hanya kegiatan mobilitas yang wajib berisi peserta.',
    },
    {
      target: '#bagian-berkas',
      title: 'Berkas',
      body: 'IA dan IR wajib. Bukti tambahan (foto, PDF, atau tautan) boleh ditambahkan. Setiap berkas diberi versi, sehingga unggahan lama tetap tersimpan.',
    },
    {
      target: tid('drop-ia'),
      title: 'Implementation Arrangement (IA)',
      body: 'Wajib, PDF maksimal 10 MB. Seret berkas ke sini atau klik untuk memilih.',
    },
    {
      target: tid('drop-ir'),
      title: 'Implementation Report (IR)',
      body: 'Wajib, PDF maksimal 10 MB. Laporan pelaksanaan kegiatan.',
    },
    {
      target: tid('mobility-bundle-notice'),
      title: 'PDF mobilitas',
      body: 'Kegiatan mobilitas wajib satu PDF gabungan: transkrip mahasiswa, poster, dan dokumentasi. Tim Mobilitas memeriksanya saat verifikasi.',
    },
    {
      target: tid('submission-checklist'),
      title: 'Daftar periksa',
      body: 'Menunjukkan apa yang masih kurang sebelum kegiatan bisa diajukan. Semua butir harus hijau.',
    },
    {
      target: tid('wizard-submit'),
      title: 'Ajukan',
      body: 'Mengirim kegiatan. Non-mobilitas langsung Terverifikasi; mobilitas masuk antrean Tim Mobilitas. Pengajuan setelah batas pelaporan diberi tanda Terlambat.',
      side: 'top',
    },
    {
      target: '#bagian-ajukan',
      unless: tid('wizard-submit'),
      title: 'Ajukan',
      body: 'Bagian terakhir: daftar periksa kelengkapan dan tombol Ajukan. Non-mobilitas langsung Terverifikasi; mobilitas masuk antrean Tim Mobilitas.',
    },
  ],
};

const ACTIVITY_DETAIL_TOUR: Tour = {
  id: 'kegiatan-detail',
  title: 'Detail kegiatan',
  steps: [
    {
      target: tid('activity-code'),
      title: 'Kode kegiatan',
      body: 'Nomor unik kegiatan (RL-tahun-urut) yang dipakai di daftar, notifikasi, dan ekspor.',
    },
    {
      target: tour('activity-status'),
      title: 'Status & tanda',
      body: 'Status keseluruhan (Draf, Dalam Verifikasi, Perlu Revisi, Terverifikasi), status jalur Mobilitas, serta tanda seperti Terlambat atau Di luar lingkup.',
    },
    {
      target: '[role="group"][aria-label="Tindakan kegiatan"]',
      title: 'Tindakan',
      body: 'Tombol yang tersedia untuk peran Anda: lanjutkan draf, perbaiki revisi, atau (khusus IO) ubah kegiatan terverifikasi. Setiap perubahan dicatat.',
      side: 'left',
    },
    {
      target: tid('revision-banner'),
      title: 'Permintaan revisi',
      body: 'Catatan dari Tim Mobilitas tentang apa yang harus diperbaiki. Klik "Perbaiki sekarang" untuk membuka ruang revisi.',
    },
    {
      target: '#duplikat',
      title: 'Duplikat mahasiswa',
      body: 'Mahasiswa yang juga diklaim unit lain pada tanggal yang beririsan. Selama belum diputuskan Tim Mobilitas, mahasiswa ini tidak dihitung di kegiatan mana pun.',
    },
    {
      target: 'nav[aria-label="Bagian kegiatan"]',
      title: 'Tab kegiatan',
      body: 'Detail (isian & kerja sama), Peserta (daftar & versi), Berkas (IA, IR, PDF mobilitas, bukti), dan Riwayat (log status dan perubahan per kolom).',
    },
    {
      target: tid('participant-counts'),
      title: 'Ringkasan peserta',
      body: 'Jumlah mahasiswa PETRA, mahasiswa inbound, dan pegawai pada versi peserta yang ditampilkan.',
    },
    {
      target: '[data-testid^="version-v"]',
      title: 'Versi peserta',
      body: 'Setiap revisi membuat versi baru. Pilih versi untuk membandingkan; hanya versi yang disetujui yang dihitung.',
    },
  ],
};

const REVISION_TOUR: Tour = {
  id: 'kegiatan-revisi',
  title: 'Ruang revisi',
  steps: [
    {
      target: tid('revision-banner'),
      title: 'Catatan revisi',
      body: 'Baca apa yang diminta Tim Mobilitas sebelum memperbaiki.',
    },
    {
      target: 'section[aria-labelledby="rev-participants"]',
      title: 'Perbaiki peserta',
      body: 'Perubahan peserta dibuat sebagai versi baru; versi lama tetap tersimpan dan dapat dibandingkan.',
    },
    {
      target: tid('create-version'),
      title: 'Buat versi baru',
      body: 'Membuat salinan versi peserta terakhir yang bisa Anda ubah.',
    },
    {
      target: tid('files-editor'),
      title: 'Perbaiki berkas',
      body: 'Unggah ulang IA, IR, atau PDF mobilitas bila diminta. Berkas lama tetap tersimpan di riwayat.',
    },
    {
      target: tid('action-resubmit'),
      title: 'Ajukan ulang',
      body: 'Mengirim perbaikan kembali ke Tim Mobilitas; status kembali ke Dalam Verifikasi.',
      side: 'top',
    },
  ],
};

const VERIFY_TOUR: Tour = {
  id: 'verifikasi',
  title: 'Verifikasi Mobilitas',
  steps: [
    {
      target: tour('page-header'),
      title: 'Verifikasi Mobilitas',
      body: 'Semua pekerjaan Tim Mobilitas di satu halaman: mahasiswa duplikat di atas, antrean verifikasi di bawah.',
    },
    {
      target: tour('page-actions'),
      title: 'Ekspor',
      body: 'Unduh antrean verifikasi atau daftar duplikat mahasiswa sebagai Excel.',
      side: 'left',
    },
    {
      target: '#duplikat',
      title: 'Duplikat Mahasiswa',
      body: 'NRP yang sama diklaim dua unit berbeda pada kegiatan dengan tanggal beririsan. Selesaikan ini lebih dulu: kegiatan dengan duplikat terbuka tidak bisa disetujui.',
    },
    {
      target: tid('conflict-row'),
      title: 'Satu duplikat',
      body: 'Menampilkan mahasiswa dan kedua kegiatan yang mengklaimnya, lengkap dengan tautan ke PDF masing-masing.',
    },
    {
      target: `${tid('conflict-side')} button`,
      title: 'Pilih kegiatan ini',
      body: 'Menyimpan mahasiswa di kegiatan ini (catatan opsional, dicatat di log). Keputusan dapat diubah nanti.',
    },
    {
      target: tid('queue-mobility'),
      title: 'Antrean Verifikasi Mobilitas',
      body: 'Kegiatan mobilitas yang menunggu verifikasi, diurutkan dari pengajuan terlama.',
      side: 'top',
    },
    {
      target: tid('queue-toggle'),
      title: 'Buka baris',
      body: 'Menampilkan peserta, PDF mobilitas, perbandingan dengan versi sebelumnya, serta tombol "Setujui peserta" dan "Minta revisi peserta".',
      tip: '"Minta revisi peserta" wajib disertai catatan; kegiatan kembali ke unit. Tidak ada penolakan permanen.',
    },
  ],
};

const REPORTS_TOUR: Tour = {
  id: 'laporan',
  title: 'Laporan & Ekspor',
  steps: [
    {
      target: 'nav[aria-label="Daftar laporan"]',
      title: 'Daftar laporan',
      body: 'Pilih laporan di sini. Daftar menyesuaikan peran: misalnya daftar peserta hanya untuk pemilik data dan Tim Mobilitas.',
      side: 'right',
    },
    {
      target: tid('report-ringkasan'),
      title: 'Ringkasan RENSTRA',
      body: 'Nilai semua indikator RENSTRA untuk periode terpilih, beserta rinciannya.',
      side: 'right',
    },
    {
      target: tid('report-kpi'),
      title: 'Laporan per RENSTRA',
      body: 'Pilih satu indikator untuk melihat nilai tiap unit (Fakultas → Program Studi → Program) beserta data pendukungnya.',
      side: 'right',
    },
    {
      target: tid('report-peserta'),
      title: 'Daftar peserta',
      body: 'Nama dan NRP peserta. Ini data pribadi: setiap unduhan dicatat (siapa, filter, jumlah baris).',
      side: 'right',
    },
    {
      target: tid('report-realisasi-kerjasama'),
      title: 'Realisasi per kerja sama',
      body: 'Status setiap rantai MoU/MoA: Terlaksana, Belum terlaksana, atau Masa tenggang (dasar RENSTRA 1.19.S4).',
      side: 'right',
    },
    {
      target: tid('report-arsip'),
      title: 'Arsip snapshot',
      body: 'Semua snapshot beku per semester, termasuk yang sudah digantikan, selalu dapat diunduh lengkap dengan tambahan susulan dan perubahan pasca-beku.',
      side: 'right',
    },
    {
      target: 'section[aria-labelledby="report-title"] form',
      title: 'Filter laporan',
      body: 'Atur tahun akademik, periode, unit, atau filter lain lalu tampilkan. Pratinjau di bawah dan berkas Excel memakai filter yang sama persis.',
    },
    {
      target: `section[aria-labelledby="report-title"] ${tid('export-excel')}`,
      title: 'Unduh Excel',
      body: 'Mengunduh laporan yang sedang ditampilkan. Workbook memuat lembar Info berisi filter dan periode yang dipakai.',
    },
    {
      target: 'section[aria-labelledby="report-title"] table',
      title: 'Pratinjau',
      body: 'Baris yang akan masuk ke Excel. Pratinjau dibatasi; unduh Excel untuk melihat seluruh data.',
      side: 'top',
    },
  ],
};

const SETTINGS_UMUM_TOUR: Tour = {
  id: 'pengaturan-umum',
  title: 'Pengaturan → Umum',
  steps: [
    {
      target: 'nav[aria-label="Tab pengaturan"]',
      title: 'Tab pengaturan',
      body: 'Umum (aturan dasar & simulasi tanggal), Kalender Akademik (semester, cutoff, pembekuan), dan Jenis Kegiatan (aturan per agenda).',
    },
    {
      target: 'form[aria-label="Pengaturan umum"]',
      title: 'Aturan dasar',
      body: 'Batas pelaporan (default 30 hari setelah Tanggal Selesai), masa tenggang kerja sama baru (default 6 bulan), dan pengingat revisi unit (default 7 hari).',
      tip: 'Perubahan pengaturan tidak pernah mengubah snapshot yang sudah beku.',
    },
    {
      target: tid('demo-today-card'),
      title: 'Simulasi tanggal (demo)',
      body: 'Ubah "hari ini" untuk mendemokan cutoff semester, batas pelaporan, dan pengingat. Spanduk kuning muncul di seluruh aplikasi selama simulasi aktif.',
      tip: 'Kembalikan ke tanggal asli setelah demo agar data tetap konsisten.',
    },
    {
      target: tid('run-daily-jobs'),
      title: 'Jalankan tugas harian',
      body: 'Menjalankan sekarang tugas yang biasanya berjalan otomatis tiap hari: pengingat, pembekuan pada cutoff, dan notifikasi.',
    },
  ],
};

const SETTINGS_KALENDER_TOUR: Tour = {
  id: 'pengaturan-kalender',
  title: 'Pengaturan → Kalender Akademik',
  steps: [
    {
      target: '[data-testid^="semester-row-"]',
      title: 'Semester & cutoff',
      body: 'Setiap semester punya rentang tanggal dan tanggal cutoff (default akhir semester + 30 hari). Kegiatan dengan tanggal mulai di luar tahun akademik yang terdaftar tidak bisa diajukan.',
    },
    {
      target: tid('freeze-now'),
      title: 'Bekukan',
      body: 'Membekukan snapshot RENSTRA semester ini. Pada cutoff, sistem membekukan otomatis; tombol ini untuk pembekuan manual setelah cutoff.',
    },
    {
      target: tid('refreeze'),
      title: 'Bekukan ulang',
      body: 'Membuat snapshot baru dengan alasan wajib. Snapshot lama tetap disimpan dan ditandai digantikan.',
    },
  ],
};

const SETTINGS_JENIS_TOUR: Tour = {
  id: 'pengaturan-jenis',
  title: 'Pengaturan → Jenis Kegiatan',
  steps: [
    {
      target: tid('agenda-rules'),
      title: 'Aturan Jenis Kegiatan',
      body: 'Satu aturan per Agenda Kerjasama dari SIM Kerjasama.',
    },
    {
      target: tid('agenda-rule-row'),
      title: 'Kategori mobilitas & S1',
      body: 'Kategori mobilitas (JD/DD, Student Exchange, Short/Summer, mobilitas lain, atau tidak ada) menentukan apakah kegiatan perlu peserta dan verifikasi. Kolom S1 menentukan apakah dihitung di RENSTRA 1.19.S1.',
    },
  ],
};

const NOTIFICATIONS_TOUR: Tour = {
  id: 'notifikasi',
  title: 'Notifikasi',
  steps: [
    {
      target: tid('notification-list'),
      title: 'Daftar notifikasi',
      body: 'Pengajuan diterima, permintaan revisi, pengingat batas pelaporan, kegiatan terverifikasi, dan snapshot beku. Klik untuk membuka kegiatan terkait.',
      tip: 'Di mockup ini email hanya dicatat, tidak dikirim.',
    },
    {
      target: tour('page-actions'),
      title: 'Tandai semua dibaca',
      body: 'Menghapus angka merah pada ikon lonceng sekaligus.',
      side: 'left',
    },
  ],
};

const DOCUMENTS_TOUR: Tour = {
  id: 'dokumen',
  title: 'Dokumen kerja sama',
  steps: [
    {
      target: '#doc-q',
      title: 'Cari dokumen',
      body: 'Cari berdasarkan nomor dokumen, judul, atau nama mitra.',
    },
    {
      target: '#doc-flag',
      title: 'Filter realisasi',
      body: 'Tampilkan misalnya hanya kerja sama aktif yang belum punya realisasi tahun akademik ini (masa tenggang diperhitungkan).',
    },
    {
      target: '[role="region"][aria-label="Dokumen kerja sama"]',
      title: 'Daftar dokumen',
      body: 'Setiap baris menampilkan dokumen, mitra, masa berlaku, dan tanda realisasi. Klik nomor dokumen untuk membuka detail dan tab Realisasi.',
      side: 'top',
    },
  ],
};

const DOCUMENT_DETAIL_TOUR: Tour = {
  id: 'dokumen-detail',
  title: 'Detail dokumen',
  steps: [
    {
      target: tour('page-header'),
      title: 'Detail dokumen',
      body: 'Informasi dokumen dari SIM Kerjasama (hanya dibaca, tidak diubah oleh SIM Realisasi).',
    },
    {
      target: 'nav[aria-label="Tab dokumen"]',
      title: 'Realisasi & Evaluasi perpanjangan',
      body: 'Tab Realisasi menampilkan kegiatan terverifikasi di seluruh rantai perpanjangan dan jumlahnya per tahun. Tab Evaluasi perpanjangan menampilkan ringkasan realisasi sebagai bukti saat menilai perpanjangan.',
    },
  ],
};

interface TourRule {
  match: RegExp;
  /** `tab` query value for pages whose content depends on it. */
  tab?: (tab: string | null) => boolean;
  tour: Tour;
}

const ID = '[^/]+';

/** First match wins: order specific routes before their parents. */
const TOUR_RULES: TourRule[] = [
  { match: /^\/realisasi\/?$/, tab: (t) => t === 'awards', tour: AWARDS_TOUR },
  { match: /^\/realisasi\/?$/, tour: DASHBOARD_TOUR },
  { match: /^\/realisasi\/kegiatan\/baru\/?$/, tour: NEW_ACTIVITY_TOUR },
  { match: new RegExp(`^/realisasi/kegiatan/${ID}/revisi/?$`), tour: REVISION_TOUR },
  { match: new RegExp(`^/realisasi/kegiatan/${ID}/?$`), tour: ACTIVITY_DETAIL_TOUR },
  { match: /^\/realisasi\/kegiatan\/?$/, tour: ACTIVITY_LIST_TOUR },
  { match: /^\/realisasi\/verifikasi\/mobilitas\/?$/, tour: VERIFY_TOUR },
  { match: /^\/realisasi\/laporan\/?$/, tour: REPORTS_TOUR },
  { match: /^\/realisasi\/pengaturan\/?$/, tab: (t) => t === 'kalender', tour: SETTINGS_KALENDER_TOUR },
  { match: /^\/realisasi\/pengaturan\/?$/, tab: (t) => t === 'jenis', tour: SETTINGS_JENIS_TOUR },
  { match: /^\/realisasi\/pengaturan\/?$/, tour: SETTINGS_UMUM_TOUR },
  { match: /^\/realisasi\/notifikasi\/?$/, tour: NOTIFICATIONS_TOUR },
  { match: new RegExp(`^/kerjasama/dokumen/${ID}(/realisasi|/evaluasi)?/?$`), tour: DOCUMENT_DETAIL_TOUR },
  { match: /^\/kerjasama\/dokumen\/?$/, tour: DOCUMENTS_TOUR },
];

export const ALL_TOURS: Tour[] = [LOGIN_TOUR, SHELL_TOUR, ...new Set(TOUR_RULES.map((r) => r.tour))];

/** The page tour for a route (`tab` = the `?tab=` query value), or null when the page has none. */
export function tourFor(pathname: string, tab: string | null = null): Tour | null {
  const rule = TOUR_RULES.find((r) => r.match.test(pathname) && (!r.tab || r.tab(tab)));
  return rule?.tour ?? null;
}
