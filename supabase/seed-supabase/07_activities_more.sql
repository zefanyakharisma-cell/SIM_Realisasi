-- seed-supabase/07_activities_more (simks-partnership): 100 more kegiatan (RL-xxxx-0301 … 0400) from AY 2024/2025 to
-- today, on REAL SIMKS documents, written only into realisasi.*. Idempotent: an existing activity is skipped, participant
-- lists are filled up to their target, snapshots are re-frozen only when stale.
--   22 in AY 2024/2025 (all on document 11, the only agreement valid before 2025-10-17), 50 in AY 2025/2026, 28 in
--   AY 2026/2027 up to today; 35 mobility kegiatan (student exchange, credit transfer, double degree, short/summer,
--   immersion, cultural exchange, magang, studi ekskursi, academic exchange) and 65 others (kuliah tamu, joint research,
--   COIL joint lectures, seminars, workshops, pelatihan, academic visits, staff exchange, pengabdian, rekrutmen).
--   ~45 units incl. FKG, Kedokteran, FKIP, LPPM, BPM, ELTC, CIRD, Perpustakaan, PPMG; co-units; external persons
--   named for the agreement's partner.
--   States: verified (on submit, or approved by Mobility; two after a revision round), late reports and late additions
--   after a freeze, three in the Mobility queue, one revision still open, ongoing semester exchanges and planned events
--   as drafts, two abandoned drafts.
--   Participants are picked by pg_temp.h_fill (p_auto): prodi of the submitting unit / students of the partner, intake
--   that fits the dates, never claimed by another unit on overlapping dates.
-- Generated from a reviewed table of 100 rows: every row's dates were checked against its document's validity, R-08
-- (submitted after the end date) and the Mobility timeline before writing; h_act re-checks R-04 against live SIMKS.
-- Ids: activities c5000000-0000-4000-8000-0000000003NN, event groups f5000000-…; codes RL-<year created>-03NN.

\ir lib/activity_helpers.inc

do $$
declare d int;
begin
  foreach d in array array[11, 12, 15, 17, 19, 21, 23, 25, 27, 28, 29, 30, 31, 32, 33, 36, 38, 42, 44, 51] loop
    if not exists (select 1 from kerjasama.documents where id = d and status not in ('in_process', 'rejected') and start_date is not null) then
      raise exception 'SIMKS document % missing or not selectable; adjust supabase/seed-supabase/07_activities_more.sql', d;
    end if;
  end loop;
end $$;

-- ==== AY 2024/2025 (document 11 is the only agreement valid before 2025-10-17) =================================
select pg_temp.h_act(301, 'Academic Visit Delegasi Kyoto Sangyo University ke PCU', 2, 27, 'inbound',
  '2024-08-26', '2024-08-27', 'offline', 'Gedung W PCU', 'ID', 11, '{4,17}',
  'Kunjungan pimpinan Kyoto Sangyo University untuk meluncurkan rencana implementasi MoU: pertukaran mahasiswa, riset bersama, dan kelas kolaboratif.',
  pg_temp.h_wib('2024-09-02', '09:00'), p_ext => '[{"full_name":"Prof. Masaru Ikeda","institution":"Kyoto Sangyo University","country_code":"JP","role":"staff_visitor"},{"full_name":"Naoko Fujita, M.A.","institution":"Kyoto Sangyo University","country_code":"JP","role":"staff_visitor"}]');

select pg_temp.h_act(302, 'Riset Bersama Perilaku Wisatawan Jepang di Bali', 46, 4, 'outbound',
  '2024-09-02', '2025-01-24', 'online', 'Zoom Meeting', null, 11, '{8,11}',
  'Survei dan wawancara wisatawan Jepang di Bali untuk merumuskan strategi pariwisata kreatif berbasis komunitas.',
  pg_temp.h_wib('2025-02-02', '09:00'), p_ext => '[{"full_name":"Dr. Kenji Watanabe","institution":"Kyoto Sangyo University","country_code":"JP","role":"researcher"}]');

select pg_temp.h_act(303, 'Kuliah Tamu Manajemen Rantai Pasok Industri Otomotif Jepang', 67, 15, 'inbound',
  '2024-09-18', '2024-09-18', 'offline', 'Gedung T PCU', 'ID', 11, '{9,12}',
  'Kuliah tamu praktik just-in-time dan kaizen pada pemasok otomotif Jepang untuk mahasiswa Teknik Industri.',
  pg_temp.h_wib('2024-09-23', '09:00'), p_ext => '[{"full_name":"Prof. Takuya Ono","institution":"Kyoto Sangyo University","country_code":"JP","role":"visiting_lecturer"}]');

select pg_temp.h_act(304, 'Short Program Autumn Japanese Design and Culture di Kyoto Sangyo University', 59, 23, 'outbound',
  '2024-10-07', '2024-10-18', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{4,11}',
  'Program dua minggu tentang desain ruang tradisional Jepang, kunjungan kuil dan machiya, serta studio desain bersama mahasiswa mitra.',
  pg_temp.h_wib('2024-10-26', '09:00'), 'approved', pg_temp.h_wib('2024-11-02', '14:00'), p_auto => 12, p_auto_staff => 1);

select pg_temp.h_act(305, 'Workshop Desain Kemasan Produk UMKM bersama Kyoto Sangyo University', 63, 35, 'inbound',
  '2024-10-23', '2024-10-24', 'hybrid', 'Lab DKV Gedung P PCU', 'ID', 11, '{8,9,12}',
  'Lokakarya desain kemasan ramah lingkungan untuk 25 UMKM binaan, difasilitasi dosen mitra dan mahasiswa DKV.',
  pg_temp.h_wib('2024-10-28', '09:00'), p_ext => '[{"full_name":"Assoc. Prof. Rie Kobayashi","institution":"Kyoto Sangyo University","country_code":"JP","role":"speaker"}]');

select pg_temp.h_act(306, 'Student Exchange Semester Ganjil 2024 Teknik Industri di Kyoto Sangyo University', 67, 2, 'outbound',
  '2024-09-16', '2025-01-24', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{4,9}',
  'Mahasiswa Teknik Industri mengikuti satu semester perkuliahan sistem produksi dan ergonomi di Faculty of Science and Engineering.',
  pg_temp.h_wib('2025-02-03', '09:00'), 'approved', pg_temp.h_wib('2025-02-11', '14:00'), p_auto => 3);

select pg_temp.h_act(307, 'Seminar Internasional Pendidikan Karakter di Asia Timur', 36, 35, 'inbound',
  '2024-11-06', '2024-11-06', 'hybrid', 'Auditorium PCU', 'ID', 11, '{4,16}',
  'Seminar perbandingan pendidikan karakter di sekolah Jepang dan Indonesia bagi guru mitra dan mahasiswa FKIP.',
  pg_temp.h_wib('2024-11-13', '09:00'), p_ext => '[{"full_name":"Prof. Hiroko Saito","institution":"Kyoto Sangyo University","country_code":"JP","role":"speaker"}]');

select pg_temp.h_act(308, 'Kuliah Tamu Bahasa Jepang untuk Perhotelan', 8, 15, 'inbound',
  '2024-11-19', '2024-11-21', 'offline', 'Hotel Laboratorium PCU', 'ID', 11, '{4,8}',
  'Tiga sesi bahasa Jepang layanan tamu (omotenashi) untuk mahasiswa Hotel Management.',
  pg_temp.h_wib('2024-11-27', '09:00'), p_ext => '[{"full_name":"Yumi Takeda, M.Ed.","institution":"Kyoto Sangyo University","country_code":"JP","role":"visiting_lecturer"}]');

select pg_temp.h_act(309, 'Riset Bersama Smart Grid Kampus Hijau dengan Kyoto Sangyo University', 65, 4, 'inbound',
  '2024-12-02', '2025-01-31', 'hybrid', 'Lab Sistem Tenaga PCU', 'ID', 11, '{7,13}',
  'Pemodelan beban listrik kampus dan simulasi integrasi panel surya atap; peneliti mitra berkunjung satu minggu.',
  pg_temp.h_wib('2025-02-12', '09:00'), p_ext => '[{"full_name":"Dr. Shinji Hayashi","institution":"Kyoto Sangyo University","country_code":"JP","role":"researcher"}]');

select pg_temp.h_act(310, 'Webinar Kesehatan Mental Mahasiswa Internasional', 30, 35, 'inbound',
  '2025-01-15', '2025-01-15', 'online', 'Zoom Meeting', null, 11, '{3}',
  'Webinar strategi dukungan kesehatan mental bagi mahasiswa pertukaran; dilaporkan terlambat.',
  pg_temp.h_wib('2025-02-24', '09:00'), p_ext => '[{"full_name":"Dr. Ayaka Mori","institution":"Kyoto Sangyo University","country_code":"JP","role":"speaker"}]');

select pg_temp.h_act(311, 'Studi Ekskursi Bisnis Kuliner ke Kyoto dan Osaka', 41, 24, 'outbound',
  '2025-01-13', '2025-01-22', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{2,8,12}',
  'Kunjungan pasar Nishiki, dapur pusat restoran, dan kelas manajemen kuliner di Kyoto Sangyo University.',
  pg_temp.h_wib('2025-01-31', '09:00'), 'approved', pg_temp.h_wib('2025-02-06', '14:00'), p_auto => 18, p_auto_staff => 2);

select pg_temp.h_act(312, 'Inbound Short Program Batik and Javanese Culture 2025', 60, 29, 'inbound',
  '2025-02-17', '2025-02-28', 'offline', 'Kampus PCU Siwalankerto', 'ID', 11, '{4,11}',
  'Mahasiswa Kyoto Sangyo University belajar membatik, tata busana tradisional, dan budaya Jawa Timur selama dua minggu.',
  pg_temp.h_wib('2025-03-07', '09:00'), 'approved', pg_temp.h_wib('2025-03-13', '14:00'), p_auto => 12);

select pg_temp.h_act(313, 'Joint Lecture Pemasaran Digital Lintas Negara (COIL)', 42, 34, 'inbound',
  '2025-02-24', '2025-05-30', 'online', 'Zoom Meeting', null, 11, '{4,17}',
  'Kelas kolaboratif daring 12 pertemuan; mahasiswa PCU dan Kyoto Sangyo menyusun kampanye pemasaran untuk produk lokal.',
  pg_temp.h_wib('2025-06-07', '09:00'), p_ext => '[{"full_name":"Assoc. Prof. Daisuke Matsumoto","institution":"Kyoto Sangyo University","country_code":"JP","role":"visiting_lecturer"}]');

select pg_temp.h_act(314, 'Credit Transfer Informatika di Kyoto Sangyo University', 68, 33, 'outbound',
  '2025-04-01', '2025-07-25', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{4,9}',
  'Mahasiswa Informatika mengambil mata kuliah kecerdasan buatan dan sistem terdistribusi yang diakui penuh di PCU.',
  pg_temp.h_wib('2025-08-01', '09:00'), 'approved', pg_temp.h_wib('2025-08-10', '14:00'), p_auto => 3);

select pg_temp.h_act(315, 'Pengabdian Masyarakat Pemetaan Risiko Banjir bersama Mahasiswa Kyoto Sangyo', 55, 40, 'outbound',
  '2025-03-10', '2025-03-21', 'offline', 'Kelurahan Kebraon, Surabaya', 'ID', 11, '{11,13}',
  'Pemetaan partisipatif titik genangan dan jalur evakuasi bersama warga, mahasiswa Teknik Sipil, dan mahasiswa mitra.',
  pg_temp.h_wib('2025-03-31', '09:00'), p_co => '{20}');

select pg_temp.h_act(316, 'Kuliah Tamu Etika Bisnis Jepang untuk Akuntan', 44, 15, 'inbound',
  '2025-03-12', '2025-03-12', 'offline', 'Gedung P PCU', 'ID', 11, '{8,16}',
  'Kuliah tamu tata kelola perusahaan dan etika profesi akuntan di Jepang.',
  pg_temp.h_wib('2025-03-17', '09:00'), p_ext => '[{"full_name":"Prof. Ichiro Nakagawa","institution":"Kyoto Sangyo University","country_code":"JP","role":"visiting_lecturer"}]');

select pg_temp.h_act(317, 'Lomba Desain Poster Internasional PCU–Kyoto Sangyo 2025', 63, 35, 'inbound',
  '2025-04-14', '2025-05-16', 'hybrid', 'Galeri DKV PCU', 'ID', 11, '{4,17}',
  'Kompetisi poster bertema keberlanjutan dengan 140 karya dari mahasiswa kedua universitas dan pameran hasil.',
  pg_temp.h_wib('2025-05-28', '09:00'), p_co => '{32}');

select pg_temp.h_act(318, 'Staff Exchange Pengelolaan Perpustakaan Digital ke Kyoto Sangyo University', 24, 31, 'outbound',
  '2025-04-21', '2025-04-25', 'offline', 'Kyoto Sangyo University Library', 'JP', 11, '{4,16}',
  'Pustakawan PCU mempelajari layanan repositori digital dan literasi informasi di perpustakaan mitra.',
  pg_temp.h_wib('2025-05-13', '09:00'));

select pg_temp.h_act(319, 'Summer Program Japanese Technology and Society di Kyoto Sangyo University', 28, 23, 'outbound',
  '2025-06-30', '2025-07-18', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{4,9}',
  'Program musim panas tiga minggu: robotika, kota cerdas, kunjungan pabrik di Kansai, dan proyek tim lintas negara.',
  pg_temp.h_wib('2025-07-23', '09:00'), 'approved', pg_temp.h_wib('2025-08-03', '14:00'), p_rev => jsonb_build_object('note', 'Transkrip satu peserta belum ada di PDF gabungan; mohon lengkapi dan ajukan ulang.', 'at', pg_temp.h_wib('2025-07-27', '10:00'), 'resubmit', pg_temp.h_wib('2025-07-31', '15:00')), p_auto => 22, p_auto_staff => 2);

select pg_temp.h_act(320, 'Riset Bersama Pengajaran Bahasa Inggris Berbasis Proyek', 61, 4, 'outbound',
  '2025-02-03', '2025-06-27', 'online', 'Microsoft Teams', null, 11, '{4}',
  'Studi kelas pembelajaran berbasis proyek di dua universitas; dilaporkan terlambat.',
  pg_temp.h_wib('2025-08-24', '09:00'));

select pg_temp.h_act(321, 'Magang Hospitality di Hotel Mitra Kyoto', 8, 21, 'outbound',
  '2025-05-05', '2025-07-25', 'offline', 'Hotel mitra Kyoto Sangyo University, Kyoto', 'JP', 11, '{8}',
  'Magang dua belas minggu di departemen front office dan F&B hotel mitra di Kyoto.',
  pg_temp.h_wib('2025-07-31', '09:00'), 'approved', pg_temp.h_wib('2025-08-08', '14:00'), p_auto => 6);

select pg_temp.h_act(322, 'Seminar Kebijakan Pariwisata Berkelanjutan Jepang–Indonesia', 46, 35, 'inbound',
  '2025-06-18', '2025-06-18', 'online', 'Zoom Meeting', null, 11, '{8,11}',
  'Seminar daring kebijakan pariwisata berkelanjutan (draf tidak dilanjutkan).',
  null, p_files => '{ia}');

-- ==== AY 2025/2026 Ganjil ===========================================================================================
select pg_temp.h_act(323, 'Kuliah Tamu Animasi dan Industri Kreatif Jepang', 62, 15, 'inbound',
  '2025-08-27', '2025-08-28', 'hybrid', 'Gedung P PCU', 'ID', 11, '{4,8,9}',
  'Dua sesi tentang alur produksi anime dan peluang kerja industri kreatif bagi mahasiswa International Program in Digital Media.',
  pg_temp.h_wib('2025-09-03', '09:00'), p_ext => '[{"full_name":"Takashi Endo, M.F.A.","institution":"Kyoto Sangyo University","country_code":"JP","role":"visiting_lecturer"}]');

select pg_temp.h_act(324, 'Student Exchange Semester Ganjil 2025 Desain Interior di Kyoto Sangyo University', 59, 2, 'outbound',
  '2025-09-15', '2026-01-23', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{4,11}',
  'Mahasiswa Desain Interior mengikuti satu semester studio desain dan sejarah arsitektur Jepang.',
  pg_temp.h_wib('2026-02-01', '09:00'), 'approved', pg_temp.h_wib('2026-02-08', '14:00'), p_auto => 2);

select pg_temp.h_act(325, 'Riset Bersama Material Bangunan Rendah Karbon', 54, 4, 'inbound',
  '2025-09-01', '2025-12-19', 'hybrid', 'Lab Struktur dan Material PCU', 'ID', 11, '{9,11,13}',
  'Uji karakteristik bata dan panel berbahan limbah pertanian untuk rumah tropis; peneliti mitra berkunjung dua minggu.',
  pg_temp.h_wib('2025-12-30', '09:00'), p_co => '{55}', p_ext => '[{"full_name":"Dr. Hideo Kimura","institution":"Kyoto Sangyo University","country_code":"JP","role":"researcher"}]');

select pg_temp.h_act(326, 'Workshop Penulisan Proposal Hibah Internasional', 20, 43, 'inbound',
  '2025-09-24', '2025-09-25', 'offline', 'Ruang Seminar LPPM PCU', 'ID', 11, '{4,17}',
  'Lokakarya dua hari penyusunan proposal hibah riset internasional untuk 40 dosen.',
  pg_temp.h_wib('2025-09-30', '09:00'), p_ext => '[{"full_name":"Prof. Yoshiko Arai","institution":"Kyoto Sangyo University","country_code":"JP","role":"speaker"}]');

select pg_temp.h_act(327, 'Seminar Nasional Ekonomi Kreatif bersama UGM', 4, 35, 'inbound',
  '2025-10-22', '2025-10-22', 'offline', 'Auditorium PCU', 'ID', 28, '{8}',
  'Seminar nasional peran ekonomi kreatif dalam pertumbuhan daerah dengan 300 peserta.',
  pg_temp.h_wib('2025-10-28', '09:00'), p_ext => '[{"full_name":"Dr. Rina Kartikasari","institution":"Universitas Gadjah Mada","country_code":"ID","role":"speaker"}]');

select pg_temp.h_act(328, 'Riset Bersama Kesehatan Masyarakat Pesisir dengan UGM', 76, 4, 'outbound',
  '2025-11-03', '2026-02-27', 'hybrid', 'Puskesmas Kenjeran dan Zoom', 'ID', 28, '{3,14}',
  'Studi status gizi dan kesehatan lingkungan keluarga nelayan di pesisir Kenjeran bersama peneliti UGM.',
  pg_temp.h_wib('2026-03-09', '09:00'));

select pg_temp.h_act(329, 'Kuliah Tamu Hukum Bisnis Thailand', 43, 15, 'inbound',
  '2025-10-29', '2025-10-29', 'online', 'Zoom Meeting', null, 29, '{8,16}',
  'Kuliah tamu regulasi investasi dan perdagangan Thailand untuk program International Trade and Finance.',
  pg_temp.h_wib('2025-11-02', '09:00'), p_ext => '[{"full_name":"Asst. Prof. Pongsak Thongchai","institution":"Chulalongkorn University","country_code":"TH","role":"visiting_lecturer"}]');

select pg_temp.h_act(330, 'Academic Visit Prodi Teknik Mesin ke National Taiwan University', 69, 27, 'outbound',
  '2025-11-10', '2025-11-14', 'offline', 'National Taiwan University, Taipei', 'TW', 30, '{9}',
  'Kunjungan laboratorium manufaktur presisi dan penjajakan program magang riset mahasiswa Teknik Mesin.',
  pg_temp.h_wib('2025-11-21', '09:00'), p_co => '{28}');

select pg_temp.h_act(331, 'Student Exchange Akuntansi di Yonsei University Semester Spring 2026', 6, 2, 'outbound',
  '2026-02-23', '2026-06-19', 'offline', 'Yonsei University, Sinchon Campus', 'KR', 31, '{4}',
  'Mahasiswa Akuntansi mengikuti Spring Semester di Yonsei School of Business.',
  pg_temp.h_wib('2026-06-28', '09:00'), 'approved', pg_temp.h_wib('2026-07-06', '14:00'), p_auto => 3);

select pg_temp.h_act(332, 'Winter Immersion K-Culture di Yonsei University', 57, 22, 'outbound',
  '2026-01-05', '2026-01-16', 'offline', 'Yonsei University', 'KR', 31, '{4,10}',
  'Program imersi dua minggu tentang media dan budaya populer Korea bagi mahasiswa Ilmu Komunikasi.',
  pg_temp.h_wib('2026-01-22', '09:00'), 'approved', pg_temp.h_wib('2026-01-31', '14:00'), p_auto => 14, p_auto_staff => 1);

select pg_temp.h_act(333, 'Joint Webinar Circular Fashion bersama University of Amsterdam', 60, 35, 'inbound',
  '2025-11-26', '2025-11-26', 'online', 'Zoom Meeting', null, 32, '{12}',
  'Webinar mode sirkular dan daur ulang tekstil untuk mahasiswa Textile and Fashion Design.',
  pg_temp.h_wib('2025-12-01', '09:00'), p_ext => '[{"full_name":"Dr. Lotte Visser","institution":"University of Amsterdam","country_code":"NL","role":"speaker"}]');

select pg_temp.h_act(334, 'Inbound Exchange Semester Ganjil dari National Taiwan University', 28, 2, 'inbound',
  '2025-10-20', '2026-01-16', 'offline', 'Kampus PCU Siwalankerto', 'ID', 30, '{4,9}',
  'Mahasiswa NTU mengikuti perkuliahan teknik berbahasa Inggris dan proyek lab di FTI.',
  pg_temp.h_wib('2026-01-24', '09:00'), 'approved', pg_temp.h_wib('2026-01-30', '14:00'), p_auto => 6);

select pg_temp.h_act(335, 'Pelatihan Lean Six Sigma bersama PT Astra International', 67, 69, 'inbound',
  '2025-12-09', '2025-12-11', 'offline', 'Lab Sistem Industri PCU', 'ID', 12, '{8,9}',
  'Pelatihan sabuk kuning Lean Six Sigma untuk 45 mahasiswa tingkat akhir oleh praktisi Astra.',
  pg_temp.h_wib('2025-12-16', '09:00'), p_ext => '[{"full_name":"Ir. Hendro Saputro, M.T.","institution":"PT Astra International Tbk","country_code":"ID","role":"other"}]');

select pg_temp.h_act(336, 'Pengabdian Masyarakat Gizi Anak bersama UGM', 76, 40, 'outbound',
  '2025-12-01', '2025-12-12', 'offline', 'Kabupaten Sidoarjo', 'ID', 28, '{2,3}',
  'Skrining gizi balita dan edukasi menu sehat bagi kader posyandu di empat desa.',
  pg_temp.h_wib('2025-12-20', '09:00'), p_co => '{20}');

select pg_temp.h_act(337, 'Seminar Internasional Akuntansi Keberlanjutan ASEAN', 6, 35, 'inbound',
  '2025-11-19', '2025-11-20', 'hybrid', 'Auditorium PCU', 'ID', 29, '{12,13}',
  'Seminar pelaporan keberlanjutan dan standar ISSB di ASEAN dengan pembicara Chulalongkorn.',
  pg_temp.h_wib('2025-11-29', '09:00'), p_ext => '[{"full_name":"Asst. Prof. Kanokwan Rattanakul","institution":"Chulalongkorn University","country_code":"TH","role":"speaker"}]');

select pg_temp.h_act(338, 'Rekrutmen Management Trainee bersama PT Astra International', 18, 39, 'inbound',
  '2025-12-15', '2025-12-16', 'offline', 'Gedung W PCU', 'ID', 12, '{8}',
  'Presentasi perusahaan, tes, dan wawancara program management trainee bagi lulusan PCU.',
  pg_temp.h_wib('2025-12-20', '09:00'));

select pg_temp.h_act(339, 'Kuliah Tamu Arsitektur Tropis Asia dari National Taiwan University', 53, 15, 'inbound',
  '2026-01-14', '2026-01-15', 'offline', 'Gedung P PCU', 'ID', 30, '{11,13}',
  'Kuliah tamu desain pasif bangunan tropis untuk mahasiswa Magister Arsitektur.',
  pg_temp.h_wib('2026-01-22', '09:00'), p_ext => '[{"full_name":"Prof. Huang Shu-fen","institution":"National Taiwan University","country_code":"TW","role":"visiting_lecturer"}]');

select pg_temp.h_act(340, 'Magang Data Analytics di PT Astra International', 68, 21, 'outbound',
  '2026-01-05', '2026-02-27', 'offline', 'PT Astra International Tbk, Jakarta', 'ID', 12, '{8,9}',
  'Mahasiswa Informatika magang delapan minggu membangun dasbor analitik penjualan.',
  pg_temp.h_wib('2026-03-05', '09:00'), 'approved', pg_temp.h_wib('2026-03-12', '14:00'), p_auto => 5);

select pg_temp.h_act(341, 'Riset Bersama Kebijakan Fiskal Daerah dengan UGM', 43, 4, 'outbound',
  '2025-10-27', '2026-01-30', 'online', 'Zoom Meeting', null, 28, '{8,16}',
  'Analisis efektivitas transfer dana desa; dilaporkan setelah batas Ganjil (penambahan terlambat).',
  pg_temp.h_wib('2026-03-16', '09:00'));

select pg_temp.h_act(342, 'Student Exchange Semester Ganjil 2025 Sastra Inggris di Kyoto Sangyo University', 61, 2, 'outbound',
  '2025-09-22', '2026-01-23', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{4}',
  'Mahasiswa Sastra Inggris mengikuti program studi bahasa dan budaya di Faculty of Foreign Studies.',
  pg_temp.h_wib('2026-02-02', '09:00'), 'approved', pg_temp.h_wib('2026-02-08', '14:00'), p_auto => 2);

select pg_temp.h_act(343, 'Kuliah Tamu Teknologi Pangan Fungsional', 41, 15, 'inbound',
  '2025-09-10', '2025-09-10', 'offline', 'Lab Kuliner PCU', 'ID', 11, '{2,3}',
  'Kuliah tamu pengembangan produk pangan fungsional untuk program Culinary Business Management.',
  pg_temp.h_wib('2025-09-15', '09:00'), p_ext => '[{"full_name":"Dr. Mayumi Ishikawa","institution":"Kyoto Sangyo University","country_code":"JP","role":"visiting_lecturer"}]');

select pg_temp.h_act(344, 'Workshop Kepemimpinan Mahasiswa Asia', 23, 43, 'inbound',
  '2025-10-01', '2025-10-03', 'offline', 'Gedung W PCU', 'ID', 11, '{4,16}',
  'Pelatihan kepemimpinan dan kerja lintas budaya untuk 60 pengurus organisasi mahasiswa.',
  pg_temp.h_wib('2025-10-09', '09:00'), p_ext => '[{"full_name":"Sota Yamamoto, M.A.","institution":"Kyoto Sangyo University","country_code":"JP","role":"speaker"}]');

-- ==== AY 2025/2026 Genap ============================================================================================
select pg_temp.h_act(345, 'Short Program Spring Business di National University of Singapore', 45, 23, 'outbound',
  '2026-03-02', '2026-03-13', 'offline', 'National University of Singapore', 'SG', 19, '{4,8}',
  'Program dua minggu keuangan dan investasi Asia, kunjungan SGX dan perusahaan fintech.',
  pg_temp.h_wib('2026-03-19', '09:00'), 'approved', pg_temp.h_wib('2026-03-27', '14:00'), p_auto => 12, p_auto_staff => 1);

select pg_temp.h_act(346, 'Inbound Exchange Semester Genap dari Chulalongkorn University', 4, 2, 'inbound',
  '2026-02-23', '2026-06-26', 'offline', 'Kampus PCU Siwalankerto', 'ID', 25, '{4,17}',
  'Mahasiswa Chulalongkorn mengikuti satu semester di SBM dengan program buddy dan kelas bahasa Indonesia.',
  pg_temp.h_wib('2026-07-03', '09:00'), 'approved', pg_temp.h_wib('2026-07-09', '14:00'), p_auto => 7);

select pg_temp.h_act(347, 'Riset Bersama Air Bersih Perkotaan dengan University of Amsterdam', 56, 4, 'outbound',
  '2026-03-02', '2026-06-30', 'online', 'Microsoft Teams', null, 17, '{6,11}',
  'Pemodelan kebocoran jaringan air kota dan skenario pengurangan air tak berekening.',
  pg_temp.h_wib('2026-07-12', '09:00'), p_ext => '[{"full_name":"Dr. Thijs Mulder","institution":"University of Amsterdam","country_code":"NL","role":"researcher"}]');

select pg_temp.h_act(348, 'Seminar Internasional Hospitality Asia Tenggara 2026', 8, 35, 'inbound',
  '2026-03-18', '2026-03-19', 'offline', 'Auditorium PCU', 'ID', 25, '{8,17}',
  'Seminar dan kompetisi studi kasus hospitaliti dengan 12 kampus dari Asia Tenggara.',
  pg_temp.h_wib('2026-03-25', '09:00'), p_ext => '[{"full_name":"Asst. Prof. Warut Phromma","institution":"Chulalongkorn University","country_code":"TH","role":"speaker"}]');

select pg_temp.h_act(349, 'Double Degree Teknik Elektro dengan National Taiwan University', 65, 17, 'outbound',
  '2026-02-23', '2026-07-17', 'offline', 'National Taiwan University, Taipei', 'TW', 15, '{4,9}',
  'Mahasiswa Teknik Elektro menempuh semester pertama program gelar ganda di NTU.',
  pg_temp.h_wib('2026-07-24', '09:00'), 'approved', pg_temp.h_wib('2026-07-30', '14:00'), p_auto => 2);

select pg_temp.h_act(350, 'Kuliah Tamu Kewirausahaan Sosial dari Unilever Indonesia', 50, 15, 'inbound',
  '2026-03-25', '2026-03-25', 'offline', 'Gedung P PCU', 'ID', 21, '{8,12}',
  'Kuliah tamu model bisnis sosial dan program pemberdayaan UMKM perusahaan.',
  pg_temp.h_wib('2026-03-30', '09:00'), p_ext => '[{"full_name":"Dewi Anggraini, M.B.A.","institution":"PT Unilever Indonesia Tbk","country_code":"ID","role":"speaker"}]');

select pg_temp.h_act(351, 'Magang Supply Chain di PT Unilever Indonesia', 67, 21, 'outbound',
  '2026-03-02', '2026-05-29', 'offline', 'PT Unilever Indonesia Tbk, Rungkut Surabaya', 'ID', 21, '{8,12}',
  'Magang tiga bulan di perencanaan produksi dan logistik pabrik Rungkut.',
  pg_temp.h_wib('2026-06-04', '09:00'), 'approved', pg_temp.h_wib('2026-06-11', '14:00'), p_auto => 6, p_auto_staff => 1);

select pg_temp.h_act(352, 'Studi Ekskursi Arsitektur Tropis ke Singapura', 53, 24, 'outbound',
  '2026-04-06', '2026-04-11', 'offline', 'National University of Singapore', 'SG', 19, '{11}',
  'Studi lapangan bangunan hijau dan perencanaan kota di Singapura bersama School of Design and Environment NUS.',
  pg_temp.h_wib('2026-04-16', '09:00'), 'approved', pg_temp.h_wib('2026-04-22', '14:00'), p_auto => 10, p_auto_staff => 1);

select pg_temp.h_act(353, 'Joint Lecture Machine Learning (COIL) bersama National Taiwan University', 68, 34, 'inbound',
  '2026-02-23', '2026-05-29', 'online', 'Microsoft Teams', null, 15, '{4,9}',
  'Kelas kolaboratif daring pembelajaran mesin; tim campuran mengerjakan proyek data kesehatan.',
  pg_temp.h_wib('2026-06-06', '09:00'), p_ext => '[{"full_name":"Asst. Prof. Chen Po-han","institution":"National Taiwan University","country_code":"TW","role":"visiting_lecturer"}]');

select pg_temp.h_act(354, 'Pengabdian Masyarakat Literasi Keuangan Pekerja Migran bersama UGM', 40, 40, 'outbound',
  '2026-04-13', '2026-04-24', 'offline', 'Kabupaten Ponorogo', 'ID', 28, '{1,8,10}',
  'Pelatihan pengelolaan remitansi dan pencegahan penipuan keuangan bagi keluarga pekerja migran.',
  pg_temp.h_wib('2026-05-03', '09:00'), p_co => '{20}');

select pg_temp.h_act(355, 'Riset Bersama Material Gigi Biokompatibel dengan Chulalongkorn University', 74, 4, 'inbound',
  '2026-03-09', '2026-06-26', 'hybrid', 'Lab Biomaterial FKG PCU', 'ID', 25, '{3,9}',
  'Uji sitotoksisitas bahan tambal gigi berbasis nano-hidroksiapatit; peneliti mitra berkunjung dua minggu.',
  pg_temp.h_wib('2026-07-06', '09:00'), p_ext => '[{"full_name":"Dr. Chayanin Boonmee","institution":"Chulalongkorn University","country_code":"TH","role":"researcher"}]');

select pg_temp.h_act(356, 'Student Exchange Semester Genap Hotel Management di Chulalongkorn University', 8, 2, 'outbound',
  '2026-02-23', '2026-06-12', 'offline', 'Chulalongkorn University', 'TH', 25, '{4,8}',
  'Mahasiswa Hotel Management mengikuti satu semester di Faculty of Commerce and Accountancy.',
  pg_temp.h_wib('2026-06-20', '09:00'), 'approved', pg_temp.h_wib('2026-06-27', '14:00'), p_auto => 3);

select pg_temp.h_act(357, 'Webinar Internasional Pendidikan Anak Usia Dini', 72, 35, 'inbound',
  '2026-04-22', '2026-04-22', 'online', 'Zoom Meeting', null, 17, '{4,5}',
  'Webinar pembelajaran berbasis bermain dan kesetaraan gender di PAUD.',
  pg_temp.h_wib('2026-04-28', '09:00'), p_ext => '[{"full_name":"Dr. Emma de Jong","institution":"University of Amsterdam","country_code":"NL","role":"speaker"}]');

select pg_temp.h_act(358, 'Summer Program Engineering Innovation di National Taiwan University', 69, 23, 'outbound',
  '2026-07-06', '2026-07-24', 'offline', 'National Taiwan University', 'TW', 15, '{9}',
  'Program musim panas tiga minggu desain produk dan manufaktur aditif.',
  pg_temp.h_wib('2026-07-31', '09:00'), 'approved', pg_temp.h_wib('2026-08-08', '14:00'), p_auto => 10, p_auto_staff => 1);

select pg_temp.h_act(359, 'Inbound Short Program Indonesian Language and Culture 2026', 32, 29, 'inbound',
  '2026-07-13', '2026-07-24', 'offline', 'Kampus PCU Siwalankerto', 'ID', 31, '{4,10}',
  'Mahasiswa Yonsei belajar bahasa Indonesia, gamelan, dan kuliner Jawa Timur selama dua minggu.',
  pg_temp.h_wib('2026-07-30', '09:00'), 'approved', pg_temp.h_wib('2026-08-05', '14:00'), p_auto => 12);

select pg_temp.h_act(360, 'Academic Visit Delegasi Chulalongkorn University ke Fakultas Kedokteran Gigi', 34, 27, 'inbound',
  '2026-05-11', '2026-05-12', 'offline', 'Gedung FKG PCU', 'ID', 25, '{3,17}',
  'Kunjungan dekanat mitra untuk merancang pertukaran klinis dan riset biomaterial.',
  pg_temp.h_wib('2026-05-17', '09:00'), p_ext => '[{"full_name":"Assoc. Prof. Siriporn Kaewkla","institution":"Chulalongkorn University","country_code":"TH","role":"staff_visitor"},{"full_name":"Dr. Thanawat Srisuk","institution":"Chulalongkorn University","country_code":"TH","role":"staff_visitor"}]');

select pg_temp.h_act(361, 'Seminar Nasional Teknologi Otomotif bersama PT Astra International', 69, 35, 'inbound',
  '2026-05-20', '2026-05-20', 'offline', 'Auditorium PCU', 'ID', 23, '{9}',
  'Seminar kendaraan listrik dan rantai pasok baterai dengan praktisi industri.',
  pg_temp.h_wib('2026-05-25', '09:00'), p_ext => '[{"full_name":"Ir. Agus Wibisono","institution":"PT Astra International Tbk","country_code":"ID","role":"speaker"}]');

select pg_temp.h_act(362, 'Kuliah Tamu Perpajakan Internasional dari National University of Singapore', 47, 15, 'inbound',
  '2026-04-15', '2026-04-15', 'online', 'Zoom Meeting', null, 19, '{8,16}',
  'Kuliah tamu pajak lintas batas dan BEPS untuk program Tax Accounting.',
  pg_temp.h_wib('2026-04-19', '09:00'), p_ext => '[{"full_name":"Dr. Arjun Nair","institution":"National University of Singapore","country_code":"SG","role":"visiting_lecturer"}]');

select pg_temp.h_act(363, 'Staff Exchange Penjaminan Mutu ke Chulalongkorn University', 15, 31, 'outbound',
  '2026-05-25', '2026-05-29', 'offline', 'Chulalongkorn University', 'TH', 25, '{4,16}',
  'Staf Badan Penjaminan Mutu mempelajari sistem akreditasi internasional di mitra.',
  pg_temp.h_wib('2026-06-06', '09:00'));

select pg_temp.h_act(364, 'Student Exchange Ilmu Komunikasi di University of Amsterdam', 57, 2, 'outbound',
  '2026-02-02', '2026-06-26', 'offline', 'University of Amsterdam', 'NL', 32, '{4}',
  'Mahasiswa Ilmu Komunikasi mengikuti semester di Graduate School of Communication.',
  pg_temp.h_wib('2026-07-05', '09:00'), 'approved', pg_temp.h_wib('2026-07-18', '14:00'), p_rev => jsonb_build_object('note', 'Learning agreement belum ditandatangani mitra; mohon unggah ulang PDF.', 'at', pg_temp.h_wib('2026-07-10', '10:00'), 'resubmit', pg_temp.h_wib('2026-07-14', '15:00')), p_auto => 2);

select pg_temp.h_act(365, 'Workshop Pembelajaran Berbasis Proyek bersama Kyoto Sangyo University', 17, 43, 'inbound',
  '2026-02-25', '2026-02-26', 'offline', 'Gedung T PCU', 'ID', 27, '{4}',
  'Lokakarya desain mata kuliah berbasis proyek untuk 50 dosen lintas fakultas.',
  pg_temp.h_wib('2026-03-03', '09:00'), p_ext => '[{"full_name":"Prof. Kaito Yamamoto","institution":"Kyoto Sangyo University","country_code":"JP","role":"speaker"}]');

select pg_temp.h_act(366, 'Riset Bersama Pemasaran Pariwisata Halal dengan Chulalongkorn University', 46, 4, 'outbound',
  '2026-03-02', '2026-06-30', 'online', 'Zoom Meeting', null, 25, '{8}',
  'Studi preferensi wisatawan muslim di Thailand dan Indonesia; dilaporkan setelah batas Genap (penambahan terlambat).',
  pg_temp.h_wib('2026-09-08', '09:00'));

select pg_temp.h_act(367, 'Konser Kolaborasi Musik Gerejawi Thailand–Indonesia', 21, 35, 'inbound',
  '2026-05-29', '2026-05-29', 'offline', 'Auditorium PCU', 'ID', 25, '{4,10}',
  'Konser dan lokakarya paduan suara bersama musisi Chulalongkorn.',
  pg_temp.h_wib('2026-06-04', '09:00'), p_ext => '[{"full_name":"Napat Saengthong","institution":"Chulalongkorn University","country_code":"TH","role":"other"}]');

select pg_temp.h_act(368, 'Kuliah Tamu Manajemen Rumah Sakit dari National University of Singapore', 30, 15, 'inbound',
  '2026-06-03', '2026-06-03', 'hybrid', 'Gedung Fakultas Kedokteran PCU', 'ID', 19, '{3}',
  'Kuliah tamu mutu layanan dan keselamatan pasien di rumah sakit pendidikan.',
  pg_temp.h_wib('2026-06-08', '09:00'), p_ext => '[{"full_name":"Assoc. Prof. Goh Hui Min","institution":"National University of Singapore","country_code":"SG","role":"visiting_lecturer"}]');

select pg_temp.h_act(369, 'Workshop Ekspor UMKM bersama PT Astra International', 43, 35, 'inbound',
  '2026-06-17', '2026-06-17', 'offline', 'Gedung P PCU', 'ID', 23, '{8}',
  'Lokakarya kesiapan ekspor UMKM binaan (draf belum diajukan).',
  null, p_files => '{ia}');

select pg_temp.h_act(370, 'Summer Program Sustainable Cities di University of Amsterdam', 35, 23, 'outbound',
  '2026-07-06', '2026-07-17', 'offline', 'University of Amsterdam', 'NL', 17, '{11,13}',
  'Program musim panas dua minggu perencanaan kota berkelanjutan dan pengelolaan air di Amsterdam.',
  pg_temp.h_wib('2026-07-25', '09:00'), 'approved', pg_temp.h_wib('2026-07-31', '14:00'), p_auto => 12, p_auto_staff => 1);

select pg_temp.h_act(371, 'Riset Bersama AI untuk Diagnosis Medis dengan National Taiwan University', 68, 4, 'outbound',
  '2026-03-16', '2026-07-31', 'online', 'Microsoft Teams', null, 15, '{3,9}',
  'Pengembangan model deteksi retinopati diabetik dari citra fundus bersama peneliti NTU.',
  pg_temp.h_wib('2026-08-10', '09:00'), p_co => '{76}');

select pg_temp.h_act(372, 'Pelatihan Guru Bahasa Inggris Sekolah Mitra', 73, 63, 'inbound',
  '2026-06-22', '2026-06-26', 'offline', 'Gedung T PCU', 'ID', 27, '{4}',
  'Pelatihan lima hari metode komunikatif untuk 35 guru SD mitra, difasilitasi dosen Kyoto Sangyo.',
  pg_temp.h_wib('2026-07-02', '09:00'), p_ext => '[{"full_name":"Yui Kato, M.Ed.","institution":"Kyoto Sangyo University","country_code":"JP","role":"speaker"}]');

-- ==== AY 2026/2027 Ganjil (to today) ================================================================================
select pg_temp.h_act(373, 'Inbound Exchange Semester Ganjil 2026 dari National Taiwan University', 28, 2, 'inbound',
  '2026-08-24', '2026-12-18', 'offline', 'Kampus PCU Siwalankerto', 'ID', 30, '{4,9}',
  'Mahasiswa NTU mengikuti semester di FTI (kegiatan masih berjalan).',
  null, p_auto => 6, p_files => '{ia}');

select pg_temp.h_act(374, 'Student Exchange Semester Fall 2026 di Yonsei University', 4, 2, 'outbound',
  '2026-08-31', '2026-12-18', 'offline', 'Yonsei University', 'KR', 31, '{4}',
  'Mahasiswa SBM mengikuti Fall Semester di Yonsei (kegiatan masih berjalan).',
  null, p_auto => 3, p_files => '{ia}');

select pg_temp.h_act(375, 'Kuliah Tamu Smart Logistics dari LMU Munich', 67, 15, 'inbound',
  '2026-09-02', '2026-09-02', 'offline', 'Gedung T PCU', 'ID', 42, '{9}',
  'Kuliah tamu digitalisasi logistik dan rantai pasok di Eropa.',
  pg_temp.h_daysago(26, '09:00'), p_ext => '[{"full_name":"Prof. Dr. Jonas Wagner","institution":"Ludwig Maximilian University of Munich","country_code":"DE","role":"visiting_lecturer"}]');

select pg_temp.h_act(376, 'Short Program Sustainable Business di Chulalongkorn University', 49, 23, 'outbound',
  '2026-08-03', '2026-08-14', 'offline', 'Chulalongkorn University', 'TH', 25, '{4,8}',
  'Program dua minggu transformasi digital bisnis berkelanjutan di Sasin School of Management.',
  pg_temp.h_daysago(40, '09:00'), 'approved', pg_temp.h_daysago(33, '14:00'), p_auto => 10, p_auto_staff => 1);

select pg_temp.h_act(377, 'Magang Riset Energi Terbarukan di LMU Munich', 65, 21, 'outbound',
  '2026-08-31', '2026-09-25', 'offline', 'Ludwig Maximilian University of Munich', 'DE', 42, '{7,9}',
  'Magang riset empat minggu di laboratorium fotovoltaik mitra.',
  pg_temp.h_daysago(5, '09:00'), 'pending', pg_temp.h_daysago(5, '09:00'), p_auto => 2);

select pg_temp.h_act(378, 'Seminar Internasional Pendidikan Inklusif ASEAN', 36, 35, 'inbound',
  '2026-09-16', '2026-09-17', 'hybrid', 'Auditorium PCU', 'ID', 44, '{4,10}',
  'Seminar praktik baik sekolah inklusif di Filipina dan Indonesia.',
  pg_temp.h_daysago(12, '09:00'), p_ext => '[{"full_name":"Dr. Bianca Torres","institution":"Ateneo de Manila University","country_code":"PH","role":"speaker"}]');

select pg_temp.h_act(379, 'Riset Bersama Diaspora dan Identitas Budaya dengan Ateneo de Manila University', 61, 4, 'outbound',
  '2026-09-01', '2026-09-30', 'online', 'Zoom Meeting', null, 44, '{10,16}',
  'Tahap awal riset narasi diaspora Filipina dan Indonesia: desain instrumen dan wawancara pilot.',
  pg_temp.h_daysago(2, '09:00'));

select pg_temp.h_act(380, 'Inbound Short Program Southeast Asian Business 2026 dari NUS', 5, 23, 'inbound',
  '2026-08-17', '2026-08-28', 'offline', 'Kampus PCU Siwalankerto', 'ID', 19, '{4,17}',
  'Mahasiswa NUS mengikuti program dua minggu bisnis keluarga dan UMKM Jawa Timur.',
  pg_temp.h_daysago(30, '09:00'), 'approved', pg_temp.h_daysago(24, '14:00'), p_auto => 10);

select pg_temp.h_act(381, 'Academic Visit Delegasi University of Sydney ke PCU', 2, 27, 'inbound',
  '2026-09-28', '2026-09-28', 'offline', 'Gedung W PCU', 'ID', 51, '{4,17}',
  'Kunjungan untuk menindaklanjuti MoU: penjajakan program bersama dan beasiswa.',
  pg_temp.h_daysago(3, '09:00'), p_ext => '[{"full_name":"Prof. Charlotte Wilson","institution":"University of Sydney","country_code":"AU","role":"staff_visitor"},{"full_name":"Jack Taylor, M.Ed.","institution":"University of Sydney","country_code":"AU","role":"staff_visitor"}]');

select pg_temp.h_act(382, 'Kuliah Tamu Digital Health dari University of Sydney', 76, 15, 'inbound',
  '2026-09-30', '2026-09-30', 'online', 'Zoom Meeting', null, 51, '{3}',
  'Kuliah tamu telemedisin dan rekam medis elektronik.',
  pg_temp.h_daysago(1, '09:00'), p_ext => '[{"full_name":"Dr. Olivia Brown","institution":"University of Sydney","country_code":"AU","role":"visiting_lecturer"}]');

select pg_temp.h_act(383, 'Workshop Tata Kelola Data Riset bersama UGM', 20, 43, 'inbound',
  '2026-09-23', '2026-09-24', 'offline', 'Ruang Seminar LPPM PCU', 'ID', 33, '{9,16}',
  'Lokakarya rencana pengelolaan data riset dan repositori terbuka.',
  pg_temp.h_daysago(6, '09:00'), p_ext => '[{"full_name":"Dr. Bayu Pratama","institution":"Universitas Gadjah Mada","country_code":"ID","role":"speaker"}]');

select pg_temp.h_act(384, 'Pengabdian Masyarakat Sekolah Siaga Bencana bersama UGM', 72, 40, 'outbound',
  '2026-08-17', '2026-08-28', 'offline', 'Kabupaten Malang', 'ID', 28, '{4,11,13}',
  'Simulasi evakuasi dan modul kesiapsiagaan bencana untuk 12 PAUD dan SD.',
  pg_temp.h_daysago(28, '09:00'));

select pg_temp.h_act(385, 'Academic Exchange Klinik Kedokteran Gigi di Chulalongkorn University', 74, 28, 'outbound',
  '2026-08-24', '2026-09-18', 'offline', 'Chulalongkorn University', 'TH', 25, '{3,4}',
  'Mahasiswa Kedokteran Gigi mengikuti rotasi klinik empat minggu di Faculty of Dentistry.',
  pg_temp.h_daysago(9, '09:00'), 'revision_requested', pg_temp.h_daysago(4, '11:00'), p_mnote => 'Surat keterangan klinik mitra dan transkrip belum ada di PDF; mohon unggah ulang.', p_auto => 3);

select pg_temp.h_act(386, 'Short Program Manufacturing 4.0 di National Taiwan University', 66, 23, 'outbound',
  '2026-08-17', '2026-08-28', 'offline', 'National Taiwan University', 'TW', 15, '{9}',
  'Program dua minggu pabrik cerdas dan otomasi untuk International Business Engineering.',
  pg_temp.h_daysago(25, '09:00'), 'approved', pg_temp.h_daysago(18, '14:00'), p_auto => 12, p_auto_staff => 1);

select pg_temp.h_act(387, 'Magang Desain Interior di Studio Mitra Bangkok', 59, 21, 'outbound',
  '2026-08-03', '2026-09-25', 'offline', 'Chulalongkorn University, Bangkok', 'TH', 38, '{9,11}',
  'Magang delapan minggu di studio desain mitra Chulalongkorn.',
  pg_temp.h_daysago(6, '09:00'), 'pending', pg_temp.h_daysago(6, '09:00'), p_auto => 3);

select pg_temp.h_act(388, 'Seminar Nasional Keuangan Berkelanjutan bersama PT Astra International', 45, 35, 'inbound',
  '2026-09-09', '2026-09-09', 'offline', 'Auditorium PCU', 'ID', 23, '{8,13}',
  'Seminar pembiayaan hijau dan pelaporan emisi perusahaan.',
  pg_temp.h_daysago(18, '09:00'), p_ext => '[{"full_name":"Rina Hapsari, CFA","institution":"PT Astra International Tbk","country_code":"ID","role":"speaker"}]');

select pg_temp.h_act(389, 'Kuliah Tamu Hukum Kesehatan Internasional dari NUS', 30, 15, 'inbound',
  '2026-09-14', '2026-09-14', 'online', 'Zoom Meeting', null, 36, '{3,16}',
  'Kuliah tamu etika dan regulasi kesehatan global.',
  pg_temp.h_daysago(15, '09:00'), p_ext => '[{"full_name":"Prof. Marcus Ong","institution":"National University of Singapore","country_code":"SG","role":"visiting_lecturer"}]');

select pg_temp.h_act(390, 'Joint Webinar Water Governance bersama University of Amsterdam', 55, 35, 'inbound',
  '2026-09-10', '2026-09-10', 'online', 'Zoom Meeting', null, 17, '{6}',
  'Webinar tata kelola air perkotaan di delta Belanda dan Surabaya.',
  pg_temp.h_daysago(20, '09:00'), p_ext => '[{"full_name":"Dr. Daan Bakker","institution":"University of Amsterdam","country_code":"NL","role":"speaker"}]');

select pg_temp.h_act(391, 'Credit Transfer Semester Ganjil 2026 di Kyoto Sangyo University', 7, 33, 'outbound',
  '2026-09-14', '2026-12-18', 'offline', 'Kyoto Sangyo University', 'JP', 27, '{4}',
  'Program transfer kredit satu semester (kegiatan masih berjalan).',
  null, p_auto => 2, p_files => '{ia}');

select pg_temp.h_act(392, 'Pelatihan Penulisan Artikel Bereputasi bersama LMU Munich', 20, 43, 'inbound',
  '2026-09-29', '2026-09-30', 'hybrid', 'Ruang Seminar LPPM PCU', 'ID', 42, '{4,9}',
  'Pelatihan dua hari strategi publikasi di jurnal internasional bereputasi.',
  pg_temp.h_daysago(0, '09:00'), p_ext => '[{"full_name":"Dr. Lena Becker","institution":"Ludwig Maximilian University of Munich","country_code":"DE","role":"speaker"}]');

select pg_temp.h_act(393, 'Inbound Exchange Semester Ganjil 2026 dari Ateneo de Manila University', 36, 2, 'inbound',
  '2026-08-31', '2026-12-11', 'offline', 'Kampus PCU Siwalankerto', 'ID', 44, '{4}',
  'Mahasiswa Ateneo mengikuti semester di FKIP (kegiatan masih berjalan).',
  null, p_auto => 4, p_files => '{ia}');

select pg_temp.h_act(394, 'Studi Ekskursi Teknik Sipil ke Singapura', 55, 24, 'outbound',
  '2026-09-21', '2026-09-25', 'offline', 'National University of Singapore', 'SG', 36, '{9,11}',
  'Kunjungan proyek MRT, Marina Barrage, dan laboratorium struktur NUS.',
  pg_temp.h_daysago(2, '09:00'), 'pending', pg_temp.h_daysago(2, '09:00'), p_auto => 16, p_auto_staff => 2);

select pg_temp.h_act(395, 'Kuliah Tamu Brand Management dari PT Astra International', 42, 15, 'inbound',
  '2026-09-22', '2026-09-22', 'offline', 'Gedung P PCU', 'ID', 23, '{8}',
  'Kuliah tamu pengelolaan merek otomotif di pasar Indonesia.',
  pg_temp.h_daysago(8, '09:00'), p_ext => '[{"full_name":"Yudha Prakoso, M.M.","institution":"PT Astra International Tbk","country_code":"ID","role":"speaker"}]');

select pg_temp.h_act(396, 'Riset Bersama Energi Surya Atap Kampus dengan NUS', 65, 4, 'inbound',
  '2026-08-03', '2026-09-30', 'hybrid', 'Lab Teknik Elektro PCU', 'ID', 19, '{7,13}',
  'Pengukuran kinerja panel surya atap dan model prediksi produksi energi.',
  pg_temp.h_daysago(1, '09:00'), p_ext => '[{"full_name":"Dr. Ryan Tan","institution":"National University of Singapore","country_code":"SG","role":"researcher"}]');

select pg_temp.h_act(397, 'Seminar Internasional Desain Asia 2026', 63, 35, 'inbound',
  '2026-10-21', '2026-10-22', 'hybrid', 'Gedung P PCU', 'ID', 44, '{4,9}',
  'Seminar internasional desain (direncanakan).',
  null, p_files => '{}');

select pg_temp.h_act(398, 'Kuliah Tamu Kebijakan Publik dari UGM', 33, 15, 'inbound',
  '2026-10-14', '2026-10-14', 'offline', 'Gedung T PCU', 'ID', 33, '{16}',
  'Kuliah tamu mata kuliah wajib kewarganegaraan (direncanakan).',
  null, p_files => '{}');

select pg_temp.h_act(399, 'Academic Exchange DKV di Ateneo de Manila University', 63, 28, 'outbound',
  '2026-08-31', '2026-09-25', 'offline', 'Ateneo de Manila University', 'PH', 44, '{4}',
  'Mahasiswa DKV mengikuti studio desain dan proyek komunitas empat minggu di Ateneo.',
  pg_temp.h_daysago(7, '09:00'), 'approved', pg_temp.h_daysago(2, '14:00'), p_auto => 4);

select pg_temp.h_act(400, 'Joint Seminar Teknologi Pendidikan bersama Ateneo de Manila University', 36, 35, 'inbound',
  '2026-09-29', '2026-09-29', 'online', 'Zoom Meeting', null, 44, '{4}',
  'Seminar daring pemanfaatan AI dalam pembelajaran di sekolah.',
  pg_temp.h_daysago(1, '09:00'), p_ext => '[{"full_name":"Dr. Carlo Mendoza","institution":"Ateneo de Manila University","country_code":"PH","role":"speaker"}]');
select setval('realisasi.activity_code_seq', greatest(400, (select last_value from realisasi.activity_code_seq)));

-- no unintended rule 2.1 conflicts anywhere
select pg_temp.h_assert_no_conflicts();

-- snapshots that no longer match what the scheduled job would freeze (oldest period first)
select pg_temp.h_refreeze_stale('Data historis kegiatan dan peserta ditambahkan (seed).');
select pg_temp.h_date_freeze_notifications();
