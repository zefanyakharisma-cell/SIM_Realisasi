/**
 * Demo guide content ("Mode Demo" on /login and the in-app "Panduan" sheet). Pure data, safe to
 * import anywhere. Wording follows the UI labels; behaviour follows docs/spec/Rules.md (Revisi V.1).
 */
import type { Role } from '@/lib/session';

export type GuideIcon =
  | 'welcome'
  | 'concepts'
  | 'roles'
  | 'submit'
  | 'revision'
  | 'verify'
  | 'dashboard'
  | 'reports'
  | 'settings'
  | 'agreements'
  | 'scenarios'
  | 'tips';

export interface GuidePoint {
  /** Short bold lead-in (optional). */
  term?: string;
  text: string;
}

export interface GuideStep {
  id: string;
  title: string;
  icon: GuideIcon;
  intro: string;
  points: GuidePoint[];
  /** Demo accounts with these roles are highlighted on the login page for this step. */
  roles?: Role[];
  /** Numbered "Coba sendiri" walkthrough. */
  tryIt?: string[];
}

export const GUIDE_STEPS: GuideStep[] = [
  {
    id: 'selamat-datang',
    title: 'Selamat datang di SIM Realisasi',
    icon: 'welcome',
    intro:
      'SIM Realisasi mencatat, memverifikasi, dan melaporkan setiap realisasi (pelaksanaan) MoU/MoA Petra Christian University yang tersimpan di SIM Kerjasama.',
    points: [
      { term: 'Untuk unit', text: 'Unit Akademik melaporkan kegiatan yang sudah selesai dalam satu halaman: detail, peserta, dan berkas.' },
      { term: 'Untuk International Office', text: 'Tim Mobilitas memverifikasi peserta, memutuskan mahasiswa duplikat, dan IO Admin mengatur kalender serta pembekuan semester.' },
      { term: 'Untuk pimpinan', text: 'Dashboard Capaian RENSTRA dan International Awards dihitung otomatis dari kegiatan terverifikasi, lengkap dengan rincian dan ekspor Excel.' },
      { term: 'Mockup', text: 'Semua data adalah data contoh. Tidak ada kata sandi: pilih akun demo untuk masuk sebagai peran tertentu.' },
    ],
    tryIt: [
      'Gunakan tombol Berikutnya untuk membaca panduan langkah demi langkah, atau lompat lewat daftar bab.',
      'Panduan tetap tersedia setelah masuk: klik tombol "Panduan" di pojok kanan bawah aplikasi.',
    ],
  },
  {
    id: 'konsep',
    title: 'Konsep inti',
    icon: 'concepts',
    intro: 'Beberapa istilah yang muncul di seluruh aplikasi.',
    points: [
      { term: 'Kegiatan', text: 'Satu realisasi kerja sama, didokumentasikan oleh tepat satu IA (Implementation Arrangement) dan satu IR (Implementation Report).' },
      { term: 'Kerja sama', text: 'Setiap kegiatan terhubung ke satu MoU/MoA dari SIM Kerjasama yang berlaku pada tanggal kegiatan, termasuk dokumen yang kini sudah diarsipkan.' },
      { term: 'Rantai perpanjangan', text: 'Sebuah dokumen beserta seluruh perpanjangannya dihitung sebagai satu kerja sama, sehingga perpanjangan di tengah tahun tidak terhitung ganda.' },
      { term: 'Kegiatan mobilitas', text: 'Jenis Kegiatan dengan kategori mobilitas (JD/DD, Student Exchange, Short/Summer, mobilitas lain) wajib berisi peserta dan satu PDF transkrip + poster + dokumentasi, lalu diverifikasi Tim Mobilitas.' },
      { term: 'Kegiatan non-mobilitas', text: 'Seminar, riset bersama, kuliah tamu, dan sejenisnya langsung berstatus Terverifikasi saat diajukan.' },
      { term: 'Inbound / Outbound', text: 'Setiap kegiatan memilih satu arah. Outbound menghitung mahasiswa PETRA; inbound menghitung mahasiswa inbound (wajib punya NRP).' },
      { term: 'Versi peserta', text: 'Daftar peserta diberi versi. Revisi membuat versi baru; versi lama tetap bisa dibaca dan dibandingkan.' },
      { term: 'Snapshot', text: 'Nilai RENSTRA yang dibekukan pada cutoff semester. Angka beku tidak pernah berubah; kegiatan susulan dicatat terpisah.' },
    ],
  },
  {
    id: 'peran',
    title: 'Peran & akun demo',
    icon: 'roles',
    intro: 'Setiap akun demo mewakili satu peran. Menu yang tampil menyesuaikan peran yang sedang dipakai.',
    points: [
      { term: 'Unit (submitter)', text: 'Membuat, mengajukan, dan merevisi kegiatan unitnya sendiri. Unit lain yang terlibat mendapat akses baca.' },
      { term: 'Staf IO, Tim Mobilitas', text: 'Memverifikasi daftar peserta kegiatan mobilitas, meminta revisi, memutuskan mahasiswa duplikat, dan mengunduh data peserta.' },
      { term: 'IO Admin', text: 'Semua akses di atas, ditambah Pengaturan: kalender akademik, cutoff, simulasi tanggal, aturan Jenis Kegiatan, dan pembekuan snapshot.' },
      { term: 'Viewer (pimpinan)', text: 'Melihat dashboard, rincian RENSTRA, dan kegiatan terverifikasi tanpa data pribadi peserta.' },
    ],
    roles: ['submitter', 'io_staff', 'io_admin', 'viewer'],
    tryIt: [
      'Akun bertanda pada daftar di bawah cocok dengan bab yang sedang dibuka.',
      'Untuk berganti peran setelah masuk, buka menu akun di kanan atas lalu pilih "Ganti akun".',
    ],
  },
  {
    id: 'lapor-kegiatan',
    title: 'Unit: melaporkan kegiatan baru',
    icon: 'submit',
    intro: 'Kegiatan dilaporkan setelah selesai (Tanggal Selesai tidak boleh melewati hari ini) dalam satu halaman Kegiatan Baru.',
    points: [
      { term: 'Detail & Kerja sama', text: 'Isi nama, Jenis Kegiatan, Inbound/Outbound, tanggal, moda, tempat, deskripsi, lalu pilih kerja sama yang berlaku pada tanggal kegiatan. Semester dan tahun akademik terisi otomatis.' },
      { term: 'Peserta', text: 'Tempel atau unggah NRP mahasiswa dan NIP pegawai; nama, fakultas, dan prodi terisi dari data BAAK/HR. NRP yang tidak dikenal menghalangi pengajuan.' },
      { term: 'Berkas', text: 'IA dan IR (PDF) wajib. Kegiatan mobilitas juga wajib satu PDF gabungan transkrip, poster, dan dokumentasi. Bukti tambahan boleh foto, PDF, atau tautan.' },
      { term: 'Ajukan', text: 'Daftar periksa menunjukkan apa yang masih kurang. Batas pelaporan = Tanggal Selesai + 30 hari; pengajuan setelahnya tetap diterima dengan tanda Terlambat.' },
      { term: 'Simpan otomatis', text: 'Peserta dan Berkas terbuka setelah Detail disimpan sebagai draf. Draf boleh dihapus; kegiatan yang sudah diajukan tidak pernah dihapus.' },
    ],
    roles: ['submitter'],
    tryIt: [
      'Masuk sebagai akun Unit, lalu buka menu "Kegiatan Baru".',
      'Isi bagian Detail & Kerja sama, lalu klik "Simpan Draf & lanjut isi peserta/berkas".',
      'Tambahkan peserta dan unggah IA/IR (PDF apa pun berukuran ≤ 10 MB cukup untuk demo).',
      'Buka bagian Ajukan, pastikan semua butir daftar periksa hijau, lalu klik "Ajukan".',
    ],
  },
  {
    id: 'revisi',
    title: 'Unit: menanggapi permintaan revisi',
    icon: 'revision',
    intro: 'Jika Tim Mobilitas meminta revisi, kegiatan kembali ke unit dengan catatan.',
    points: [
      { term: 'Kotak masuk revisi', text: 'Menu Kegiatan menampilkan lencana jumlah kegiatan yang perlu direvisi; notifikasi juga dikirim ke unit.' },
      { term: 'Ruang revisi', text: 'Catatan IO tampil di atas. Perbaiki daftar peserta atau berkas, lalu klik "Ajukan ulang". Versi peserta baru dibuat; versi lama tetap tersimpan.' },
      { term: 'Pengingat', text: 'Unit mendapat pengingat bila revisi belum dikerjakan setelah 7 hari (dapat diatur IO Admin).' },
    ],
    roles: ['submitter'],
    tryIt: [
      'Masuk sebagai akun Unit yang memiliki kegiatan berstatus "Perlu Revisi" (lihat lencana di menu Kegiatan).',
      'Buka kegiatan tersebut, baca catatan revisi, perbaiki, lalu klik "Ajukan ulang".',
    ],
  },
  {
    id: 'verifikasi',
    title: 'Tim Mobilitas: verifikasi & duplikat',
    icon: 'verify',
    intro: 'Menu Verifikasi Mobilitas berisi semua yang perlu diproses tim: antrean kegiatan dan mahasiswa duplikat.',
    points: [
      { term: 'Antrean Verifikasi Mobilitas', text: 'Kegiatan menunggu verifikasi, terlama di atas. Buka sebuah baris untuk melihat peserta, PDF mobilitas, dan perbandingan dengan versi sebelumnya.' },
      { term: 'Setujui peserta', text: 'Versi peserta disetujui dan kegiatan menjadi Terverifikasi, sehingga mulai dihitung di RENSTRA.' },
      { term: 'Minta revisi peserta', text: 'Wajib menyertakan satu catatan umum. Kegiatan kembali ke unit; tidak ada penolakan permanen.' },
      { term: 'Duplikat Mahasiswa', text: 'NRP yang sama diklaim dua unit berbeda pada tanggal yang tumpang tindih. Bandingkan kedua kegiatan lalu klik "Pilih kegiatan ini". Selama belum diputuskan, mahasiswa tidak dihitung di mana pun dan kegiatan tidak bisa disetujui.' },
      { term: 'Unit yang sama', text: 'Satu unit yang mengklaim satu mahasiswa di dua kegiatan bukan duplikat: mahasiswa dihitung di keduanya.' },
    ],
    roles: ['io_staff', 'io_admin'],
    tryIt: [
      'Masuk sebagai Staf IO (Tim Mobilitas), lalu buka "Verifikasi Mobilitas".',
      'Di bagian Duplikat Mahasiswa, bandingkan dua kegiatan dan pilih salah satu untuk setiap mahasiswa.',
      'Di antrean, buka kegiatan lalu klik "Setujui peserta" atau "Minta revisi peserta".',
    ],
  },
  {
    id: 'dashboard',
    title: 'Dashboard: Capaian RENSTRA & International Awards',
    icon: 'dashboard',
    intro: 'Dashboard hanya menghitung kegiatan Terverifikasi. Pilih periode di kanan atas.',
    points: [
      { term: 'RENSTRA 1.1', text: 'Jumlah mahasiswa inbound & outbound: pasangan (NRP, kegiatan) dari daftar peserta yang disetujui.' },
      { term: 'RENSTRA 1.19.S1', text: 'Jumlah kegiatan internasional dengan mitra luar negeri; angka domestik ditampilkan sebagai pembanding.' },
      { term: 'RENSTRA 1.19.24', text: 'Persen MoU & MoA terlaksana: rantai kerja sama dengan minimal satu kegiatan dibagi rantai yang aktif. Kerja sama baru dalam masa tenggang 6 bulan dikeluarkan dan ditampilkan terpisah.' },
      { term: 'Periode', text: 'Ganjil, Genap, Setahun (kumulatif), dan YTD. Periode yang sudah dibekukan membaca snapshot dan diberi tanda "Dibekukan".' },
      { term: 'Rincian', text: 'Klik kartu indikator untuk melihat setiap kegiatan atau kerja sama di balik angka tersebut.' },
      { term: 'International Awards', text: 'Papan peringkat per unit: Inbound, Outbound Dalam Negeri, Outbound Internasional, dan Inisiatif Internasional.' },
    ],
    roles: ['viewer', 'io_admin'],
    tryIt: [
      'Buka Dashboard, ganti periode antara Ganjil, Genap, Setahun, dan YTD.',
      'Klik salah satu kartu RENSTRA untuk membuka rinciannya.',
      'Pindah ke tab "International Awards" untuk melihat peringkat unit.',
    ],
  },
  {
    id: 'laporan',
    title: 'Laporan & Ekspor Excel',
    icon: 'reports',
    intro: 'Setiap laporan dan daftar dapat diunduh sebagai Excel; isi workbook sama persis dengan baris yang tampil setelah difilter.',
    points: [
      { term: 'Daftar laporan', text: 'Ringkasan RENSTRA, rincian per indikator, daftar kegiatan, daftar peserta, International Awards, realisasi per kerja sama, dan arsip snapshot.' },
      { term: 'Filter', text: 'Atur periode, unit, status, dan filter lain; lembar Info di workbook mencatat filter yang dipakai.' },
      { term: 'Data pribadi', text: 'Daftar peserta hanya untuk unit pemilik, Tim Mobilitas, dan IO Admin. Setiap unduhan data pribadi dicatat.' },
      { term: 'Arsip snapshot', text: 'Setiap snapshot beku, termasuk yang sudah digantikan, selalu dapat diunduh beserta tambahan susulan dan perubahan pasca-beku.' },
    ],
    tryIt: ['Buka "Laporan & Ekspor", pilih laporan di kiri, atur filter, lalu klik "Unduh Excel".'],
  },
  {
    id: 'pengaturan',
    title: 'IO Admin: pengaturan & pembekuan',
    icon: 'settings',
    intro: 'Menu Pengaturan hanya untuk IO Admin.',
    points: [
      { term: 'Umum', text: 'Batas pelaporan, masa tenggang, pengingat revisi, dan Simulasi tanggal (demo): ubah "hari ini" untuk mendemokan cutoff, batas pelaporan, dan pengingat. Hari ini demo adalah 1 Oktober 2026.' },
      { term: 'Kalender Akademik', text: 'Tahun akademik, rentang semester, dan tanggal cutoff. Snapshot dibekukan otomatis pada cutoff; IO Admin dapat membekukan manual atau membekukan ulang dengan alasan.' },
      { term: 'Jenis Kegiatan', text: 'Aturan per Agenda Kerjasama: kategori mobilitas dan apakah dihitung untuk 1.19.S1.' },
    ],
    roles: ['io_admin'],
    tryIt: [
      'Masuk sebagai IO Admin, buka Pengaturan → Umum, lalu atur Simulasi tanggal ke tanggal lain.',
      'Perhatikan spanduk kuning di seluruh aplikasi yang menandai mode simulasi tanggal.',
      'Kembalikan simulasi tanggal setelah selesai agar demo berikutnya tetap konsisten.',
    ],
  },
  {
    id: 'kerjasama',
    title: 'Integrasi SIM Kerjasama',
    icon: 'agreements',
    intro: 'SIM Realisasi membaca dokumen MoU/MoA dari SIM Kerjasama tanpa pernah mengubahnya.',
    points: [
      { term: 'Dokumen', text: 'Menu SIM Kerjasama → Dokumen menampilkan daftar kerja sama dengan tanda "Belum ada realisasi tahun akademik ini" (dengan memperhitungkan masa tenggang).' },
      { term: 'Tab Realisasi', text: 'Detail dokumen menampilkan kegiatan terverifikasi di seluruh rantai perpanjangan, jumlah per tahun, dan tanggal kegiatan terakhir.' },
      { term: 'Evaluasi perpanjangan', text: 'Ringkasan realisasi ditampilkan sebagai bukti saat mengevaluasi perpanjangan kerja sama.' },
    ],
    tryIt: ['Buka SIM Kerjasama → Dokumen, pilih sebuah dokumen, lalu buka tab Realisasi.'],
  },
  {
    id: 'skenario',
    title: 'Skenario demo siap pakai',
    icon: 'scenarios',
    intro: 'Data contoh sudah memuat kasus berikut. Gunakan untuk presentasi singkat.',
    points: [
      { term: 'Duplikat antar unit', text: 'Program musim panas yang sama diklaim FTI dan Prodi Informatika dengan 12 mahasiswa yang sama; Tim Mobilitas menyimpan mereka di FTI sehingga hanya dihitung sekali.' },
      { term: 'Duplikat terbuka', text: 'Prodi Informatika mengklaim dua mahasiswa yang juga ada di kegiatan FTI pada tanggal tumpang tindih. Kegiatan itu tidak bisa disetujui sebelum diputuskan.' },
      { term: 'Satu unit, dua kegiatan', text: 'Satu mahasiswa ikut dua kegiatan dari unit yang sama dan dihitung 2.' },
      { term: 'Revisi peserta', text: 'Sebuah kegiatan mobilitas berstatus Perlu Revisi; setelah versi 2 disetujui menjadi Terverifikasi dan versi 1 tetap tersimpan.' },
      { term: 'Non-mobilitas', text: 'Seminar atau kuliah tamu langsung Terverifikasi saat diajukan.' },
      { term: 'Masa tenggang & perpanjangan', text: 'Kerja sama baru dikeluarkan dari penyebut 1.19.24; kerja sama yang diperpanjang dihitung sekali.' },
      { term: 'Tambahan susulan', text: 'Kegiatan Ganjil yang diverifikasi setelah pembekuan tidak mengubah snapshot Ganjil, tetapi muncul di Setahun dengan tanda "Tambahan susulan".' },
    ],
    roles: ['io_staff', 'submitter'],
  },
  {
    id: 'tips',
    title: 'Tips & langkah berikutnya',
    icon: 'tips',
    intro: 'Hal-hal kecil yang memudahkan demo.',
    points: [
      { term: 'Notifikasi', text: 'Ikon lonceng di kanan atas menampilkan pengajuan baru, permintaan revisi, pengingat, dan snapshot beku.' },
      { term: 'Status', text: 'Arahkan kursor atau fokus keyboard ke lencana status untuk melihat penjelasannya.' },
      { term: 'Panduan per halaman', text: 'Selama Mode Demo aktif, tombol "Panduan" di aplikasi menampilkan tips untuk halaman yang sedang dibuka.' },
      { term: 'Menonaktifkan', text: 'Matikan sakelar Mode Demo di halaman masuk atau di panel Panduan. Pilihan ini hanya tersimpan di peramban Anda.' },
    ],
    tryIt: ['Pilih akun di bawah untuk mulai. Selamat mencoba!'],
  },
];

export interface PageGuide {
  title: string;
  tips: string[];
  /** Related full-guide step. */
  stepId: string;
}

interface PageGuideRule extends PageGuide {
  match: RegExp;
}

const ID = '[^/]+';

/** First match wins: order specific routes before their parents. */
const PAGE_GUIDES: PageGuideRule[] = [
  {
    match: /^\/realisasi\/?$/,
    title: 'Dashboard',
    stepId: 'dashboard',
    tips: [
      'Pilih periode (Ganjil, Genap, Setahun, YTD) di kanan atas; periode beku membaca snapshot.',
      'Klik kartu RENSTRA untuk melihat kegiatan atau kerja sama di balik angkanya.',
      'Tab "International Awards" menampilkan peringkat unit.',
      'Tim Mobilitas melihat kartu "Perlu diproses" berisi antrean dan duplikat yang belum diputuskan.',
    ],
  },
  {
    match: /^\/realisasi\/kegiatan\/baru\/?$/,
    title: 'Kegiatan Baru',
    stepId: 'lapor-kegiatan',
    tips: [
      'Mulai dari Detail & Kerja sama; Peserta dan Berkas terbuka setelah draf disimpan.',
      'Tanggal Selesai tidak boleh melewati hari ini. Hanya kerja sama yang berlaku pada tanggal kegiatan yang dapat dipilih.',
      'Kegiatan mobilitas memerlukan peserta dan PDF gabungan transkrip, poster, dan dokumentasi.',
      'Bagian Ajukan menampilkan daftar periksa yang masih kurang.',
    ],
  },
  {
    match: new RegExp(`^/realisasi/kegiatan/${ID}/revisi/?$`),
    title: 'Ruang revisi',
    stepId: 'revisi',
    tips: [
      'Baca catatan revisi dari IO di bagian atas.',
      'Perbaiki peserta atau berkas, lalu klik "Ajukan ulang". Versi peserta lama tetap tersimpan.',
    ],
  },
  {
    match: new RegExp(`^/realisasi/kegiatan/${ID}/(edit|peserta-edit)/?$`),
    title: 'Ubah kegiatan',
    stepId: 'konsep',
    tips: [
      'Perubahan pada kegiatan terverifikasi hanya untuk IO dan dicatat di Riwayat dengan perbandingan per kolom.',
      'Perubahan pada periode yang sudah beku tidak mengubah snapshot; tercatat sebagai Perubahan Pasca-Beku.',
    ],
  },
  {
    match: new RegExp(`^/realisasi/kegiatan/${ID}/?$`),
    title: 'Detail kegiatan',
    stepId: 'konsep',
    tips: [
      'Tab Detail, Peserta, Berkas, dan Riwayat menampilkan seluruh data kegiatan.',
      'Gunakan pemilih versi untuk membandingkan versi daftar peserta.',
      'Duplikat mahasiswa yang menyangkut kegiatan ini ditampilkan di halaman ini juga.',
    ],
  },
  {
    match: /^\/realisasi\/kegiatan\/?$/,
    title: 'Daftar kegiatan',
    stepId: 'lapor-kegiatan',
    tips: [
      'Filter per kolom dan pencarian mempersempit daftar; "Unduh Excel" mengikuti filter yang sama.',
      'Unit melihat kegiatan sendiri dan unit lain yang melibatkannya; IO melihat semua; viewer hanya yang terverifikasi.',
      'Tanda Terlambat berarti pengajuan melewati batas pelaporan (Tanggal Selesai + 30 hari).',
    ],
  },
  {
    match: /^\/realisasi\/verifikasi\/mobilitas\/?$/,
    title: 'Verifikasi Mobilitas',
    stepId: 'verifikasi',
    tips: [
      'Selesaikan Duplikat Mahasiswa terlebih dahulu: kegiatan dengan duplikat terbuka tidak bisa disetujui.',
      'Buka baris antrean untuk melihat peserta, PDF mobilitas, dan perbandingan versi.',
      '"Minta revisi peserta" wajib disertai catatan; kegiatan kembali ke unit.',
    ],
  },
  {
    match: /^\/realisasi\/laporan\/?$/,
    title: 'Laporan & Ekspor',
    stepId: 'laporan',
    tips: [
      'Pilih laporan di kiri, atur filter, lalu "Unduh Excel". Lembar Info mencatat filter yang dipakai.',
      'Arsip snapshot memuat semua snapshot beku, termasuk tambahan susulan dan perubahan pasca-beku.',
    ],
  },
  {
    match: /^\/realisasi\/pengaturan\/?$/,
    title: 'Pengaturan',
    stepId: 'pengaturan',
    tips: [
      'Umum → Simulasi tanggal mengubah "hari ini" untuk mendemokan cutoff dan pengingat.',
      'Kalender Akademik mengatur semester, cutoff, dan pembekuan snapshot.',
      'Jenis Kegiatan menentukan kategori mobilitas dan penghitungan 1.19.S1.',
    ],
  },
  {
    match: /^\/realisasi\/notifikasi\/?$/,
    title: 'Notifikasi',
    stepId: 'tips',
    tips: ['Notifikasi mencakup pengajuan, revisi, pengingat batas pelaporan, dan snapshot beku. Email hanya dicatat di mockup ini.'],
  },
  {
    match: new RegExp(`^/kerjasama/dokumen/${ID}(/realisasi|/evaluasi)?/?$`),
    title: 'Detail dokumen kerja sama',
    stepId: 'kerjasama',
    tips: [
      'Tab Realisasi menampilkan kegiatan terverifikasi di seluruh rantai perpanjangan.',
      'Tab Evaluasi perpanjangan menampilkan ringkasan realisasi sebagai bukti evaluasi perpanjangan.',
    ],
  },
  {
    match: /^\/kerjasama\/dokumen\/?$/,
    title: 'Dokumen kerja sama',
    stepId: 'kerjasama',
    tips: ['Tanda "Belum ada realisasi" menandai kerja sama aktif tanpa kegiatan terverifikasi pada tahun akademik ini (masa tenggang diperhitungkan).'],
  },
];

/** Page-specific tips for the in-app guide, or null when the route has none. */
export function pageGuideFor(pathname: string): PageGuide | null {
  const rule = PAGE_GUIDES.find((r) => r.match.test(pathname));
  if (!rule) return null;
  return { title: rule.title, tips: rule.tips, stepId: rule.stepId };
}

export function guideStepIndex(id: string): number {
  return GUIDE_STEPS.findIndex((s) => s.id === id);
}
