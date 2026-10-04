-- 04_bulk_5: Fakultas Seni & Desain — desain interior/produk, craft heritage (batik, wayang), pameran & lomba desain. RL-2026-0201..0225. Students: the 04_bulk_5 slice of 04_bulk_0_registry.sql.
\ir bulk/_helpers.inc

-- AY 2025/2026 Ganjil
select pg_temp.bulk_act(201, 'Student Exchange Industrial Design di NTUST Semester Ganjil 2025', 30, 2, 'outbound', '2025-09-08', '2025-12-26', 'offline',
  'Department of Design, NTUST, Taipei', 'TW', 103, '{4,9,17}', 'Pertukaran pelajar satu semester mahasiswa DKV di Department of Design NTUST dengan mata kuliah studio desain produk dan desain interaksi. Kredit yang diperoleh dikonversi ke kurikulum DKV PCU.',
  pg_temp.wib('2026-01-09'), 'approved', pg_temp.wib('2026-01-16', '14:00'));
select pg_temp.bulk_pset(201, '{C21236955,C21237024,C21237100}', '{}', '{}');

select pg_temp.bulk_act(202, 'Pameran dan Seminar Batik Kontemporer Motif Pesisiran Jawa Timur bersama ITB', 30, 35, 'inbound', '2025-10-02', '2025-10-03', 'offline',
  'Galeri Gedung P PCU', 'ID', 110, '{4,11,12}', 'Pameran karya batik kontemporer bermotif pesisiran Jawa Timur disertai seminar tentang reinterpretasi motif tradisional dalam desain tekstil modern, menghadirkan pembicara dari FSRD ITB.',
  pg_temp.wib('2025-10-20'), null, null,
  p_ext => '[{"full_name":"Dr. Ira Adriati, M.Sn.","institution":"Institut Teknologi Bandung","country_code":"ID","role":"speaker","notes":"Kelompok Keahlian Kriya, FSRD ITB"}]');

select pg_temp.bulk_act(203, 'Kuliah Tamu Desain Interior Adaptif Iklim Tropis oleh Dosen The University of Queensland', 30, 15, 'inbound', '2025-10-20', '2025-10-22', 'hybrid',
  'Studio Desain Interior Gedung P PCU', 'ID', 106, '{4,11,13}', 'Rangkaian kuliah tamu tiga hari tentang strategi desain interior pasif untuk iklim tropis lembap, termasuk studi kasus hunian di Queensland dan sesi kritik studio mahasiswa.',
  pg_temp.wib('2025-11-05'), null, null,
  p_ext => '[{"full_name":"Assoc. Prof. Sarah Whitfield","institution":"The University of Queensland","country_code":"AU","role":"visiting_lecturer","notes":"School of Architecture, Design and Planning"}]');

select pg_temp.bulk_act(204, 'Short Program Design Thinking for Social Innovation di KMUTT', 30, 23, 'outbound', '2025-11-03', '2025-11-21', 'offline',
  'School of Architecture and Design, KMUTT, Bangkok', 'TH', 108, '{4,10,17}', 'Program singkat tiga minggu di KMUTT yang melatih metode design thinking untuk inovasi sosial melalui proyek lapangan bersama komunitas di Bangkok. Luaran berupa prototipe layanan dan presentasi akhir.',
  pg_temp.wib('2025-12-05'), 'approved', pg_temp.wib('2025-12-12', '14:00'));
select pg_temp.bulk_pset(204, '{C21246975,C21247035,C21247102,C21227130}', '{}', '{PG452412}');

select pg_temp.bulk_act(205, 'Riset Bersama Dokumentasi Digital Wayang Kulit Jawa Timuran dengan De La Salle University', 30, 4, 'inbound', '2025-08-18', '2025-12-12', 'hybrid',
  'Laboratorium Desain Gedung P PCU', 'ID', 109, '{4,9,11}', 'Penelitian bersama untuk mendigitalkan koleksi wayang kulit gaya Jawa Timuran melalui fotogrametri dan pemodelan 3D, serta menyusun arsip daring yang dapat diakses peneliti di Indonesia dan Filipina.',
  pg_temp.wib('2026-01-12'), null, null,
  p_ext => '[{"full_name":"Dr. Maria Isabel Santos","institution":"De La Salle University","country_code":"PH","role":"researcher","notes":"Department of Communication, College of Liberal Arts"}]');

select pg_temp.bulk_act(206, 'Inbound Exchange Desain Interior dari The University of Queensland Semester Ganjil 2025', 30, 2, 'inbound', '2025-08-25', '2025-12-12', 'offline',
  'Kampus PCU Siwalankerto', 'ID', 106, '{4,17}', 'Mahasiswa pertukaran dari The University of Queensland mengikuti satu semester perkuliahan studio desain interior dan kelas budaya Indonesia di FSD PCU.',
  pg_temp.wib('2025-12-19'), 'approved', pg_temp.wib('2025-12-30', '14:00'));
select pg_temp.bulk_pset(206, '{}', '{X01250618}', '{}');

select pg_temp.bulk_act(207, 'Lomba Desain Produk Furnitur Rotan PCU–ITB 2025', 30, 35, 'inbound', '2025-11-24', '2025-11-28', 'offline',
  'Auditorium Gedung W PCU', 'ID', 110, '{8,9,12}', 'Kompetisi desain furnitur berbahan rotan untuk mahasiswa desain se-Jawa yang diselenggarakan bersama FSRD ITB, dengan penjurian prototipe dan pameran karya finalis.',
  pg_temp.wib('2025-12-10'), null, null,
  p_ext => '[{"full_name":"Dr. Andar Bagus Sriwarno, M.T.","institution":"Institut Teknologi Bandung","country_code":"ID","role":"other","notes":"Juri, Program Studi Desain Produk FSRD ITB"}]');

select pg_temp.bulk_act(208, 'Pengabdian Masyarakat Desain Kemasan Batik Tulis Tanjungbumi bersama ITB', 30, 40, 'outbound', '2026-01-12', '2026-01-16', 'offline',
  'Sentra Batik Tulis Tanjungbumi, Bangkalan', 'ID', 110, '{1,8,12}', 'Pendampingan perajin batik tulis Tanjungbumi dalam merancang kemasan dan identitas visual produk agar siap dipasarkan secara daring, bersama tim pengabdian FSRD ITB.',
  pg_temp.wib('2026-02-02'), null, null,
  p_ext => '[{"full_name":"Dr. Agus Sachari, M.Sn.","institution":"Institut Teknologi Bandung","country_code":"ID","role":"other","notes":"Pendamping pengabdian masyarakat, FSRD ITB"}]');

-- AY 2025/2026 Genap
select pg_temp.bulk_act(209, 'Student Exchange Desain Produk di De La Salle University Semester Genap 2026', 30, 2, 'outbound', '2026-02-02', '2026-05-29', 'offline',
  'De La Salle University, Taft Avenue, Manila', 'PH', 109, '{4,17}', 'Mahasiswa DKV menempuh satu semester di De La Salle University dengan fokus mata kuliah desain produk dan multimedia arts. Hasil studi dialihkreditkan ke kurikulum FSD PCU.',
  pg_temp.wib('2026-06-12'), 'approved', pg_temp.wib('2026-06-22', '14:00'));
select pg_temp.bulk_pset(209, '{C21257007,C21247065,C21247117}', '{}', '{}');

select pg_temp.bulk_act(210, 'Credit Transfer Industrial Design NTUST di FSD PCU Semester Genap 2026', 30, 33, 'inbound', '2026-02-09', '2026-06-19', 'offline',
  'Kampus PCU Siwalankerto', 'ID', 103, '{4,17}', 'Mahasiswa NTUST mengikuti program transfer kredit di FSD PCU, mengambil studio desain produk, kriya kayu, dan kelas Bahasa Indonesia untuk penutur asing.',
  pg_temp.wib('2026-06-30'), 'approved', pg_temp.wib('2026-07-08', '14:00'));
select pg_temp.bulk_pset(210, '{}', '{X02260610}', '{}');

select pg_temp.bulk_act(211, 'Pengembangan Kurikulum Bersama Desain Interior Berkelanjutan dengan The University of Queensland', 30, 32, 'outbound', '2026-02-16', '2026-04-24', 'online',
  'Zoom Meeting', null, 106, '{4,12}', 'Serangkaian lokakarya daring untuk menyusun mata kuliah bersama tentang desain interior berkelanjutan, mencakup capaian pembelajaran, rubrik penilaian studio, dan modul material ramah lingkungan.',
  pg_temp.wib('2026-05-06'), null, null,
  p_ext => '[{"full_name":"Dr. Lisa Harrington","institution":"The University of Queensland","country_code":"AU","role":"other","notes":"Koordinator program Interior Architecture"}]');

select pg_temp.bulk_act(212, 'Pameran Bersama Wayang Kontemporer Indonesia–Taiwan di NTUST', 30, 35, 'outbound', '2026-03-16', '2026-03-27', 'offline',
  'NTUST Design Gallery, Taipei', 'TW', 103, '{4,11,17}', 'Pameran karya dosen dan mahasiswa FSD yang menafsirkan ulang tokoh wayang dalam media ilustrasi, instalasi, dan produk, berdampingan dengan karya puppetry kontemporer mahasiswa NTUST.',
  pg_temp.wib('2026-04-10'), null, null,
  p_ext => '[{"full_name":"Prof. Chen Kuo-Hsiang","institution":"National Taiwan University of Science and Technology","country_code":"TW","role":"other","notes":"Kurator pendamping, Department of Design"}]');

select pg_temp.bulk_act(213, 'Studi Ekskursi Arsitektur Vernakular dan Interior Heritage ke ITB Bandung', 30, 24, 'outbound', '2026-04-06', '2026-04-10', 'offline',
  'Kampus ITB Ganesha, Bandung', 'ID', 110, '{4,11}', 'Kunjungan studi mahasiswa ke studio FSRD ITB dan bangunan heritage di Bandung untuk mempelajari arsitektur vernakular Sunda serta konservasi interior bangunan kolonial.',
  pg_temp.wib('2026-04-20'), 'approved', pg_temp.wib('2026-04-28', '14:00'));
select pg_temp.bulk_pset(213, '{C21247081,C21257133,C21227169,C21247195,C21257223,C21257247}', '{}', '{PG780858}');

select pg_temp.bulk_act(214, 'Workshop Rekayasa Bambu untuk Desain Produk bersama KMUTT', 30, 43, 'inbound', '2026-05-11', '2026-05-13', 'offline',
  'Workshop Kriya Gedung P PCU', 'ID', 108, '{9,12,13}', 'Pelatihan tiga hari teknik laminasi dan pembentukan bambu untuk furnitur dan produk rumah tangga, dipandu dosen KMUTT, dengan luaran prototipe kursi lipat bambu.',
  pg_temp.wib('2026-05-22'), null, null,
  p_ext => '[{"full_name":"Asst. Prof. Dr. Pornchai Wongsuwan","institution":'
          '"King Mongkut''s University of Technology Thonburi","country_code":"TH","role":"visiting_lecturer","notes":"School of Architecture and Design"}]');

select pg_temp.bulk_act(215, 'Cultural Exchange Batik dan Wayang untuk Mahasiswa De La Salle University 2026', 30, 29, 'inbound', '2026-07-06', '2026-07-24', 'offline',
  'Kampus PCU Siwalankerto', 'ID', 109, '{4,11,17}', 'Program budaya tiga minggu bagi mahasiswa De La Salle University: kelas membatik, pembuatan wayang kardus, kunjungan ke sanggar di Surabaya, dan pameran karya di akhir program.',
  pg_temp.wib('2026-08-05'), 'approved', pg_temp.wib('2026-08-12', '14:00'));
select pg_temp.bulk_pset(215, '{}', '{X01260635,X01260636}', '{}');

select pg_temp.bulk_act(216, 'Guest Lecture Speculative Product Design dari KMUTT', 30, 7, 'inbound', '2026-03-04', '2026-03-04', 'online',
  'Microsoft Teams', null, 108, '{4,9}', 'Kuliah tamu daring tentang pendekatan desain spekulatif dalam pengembangan produk masa depan, disertai diskusi proyek mahasiswa studio desain produk.',
  pg_temp.wib('2026-03-12'), null, null,
  p_ext => '[{"full_name":"Dr. Nattapong Srisuk","institution":"King Mongkut''s University of Technology Thonburi","country_code":"TH","role":"speaker","notes":"Industrial Design Program"}]');

select pg_temp.bulk_act(217, 'Design Immersion Program Brisbane bersama The University of Queensland', 31, 22, 'outbound', '2026-06-29', '2026-07-17', 'offline',
  'UQ School of Architecture, Design and Planning, St Lucia, Brisbane', 'AU', 106, '{4,11}', 'Program imersi tiga minggu di UQ: studio desain ruang publik, kunjungan ke museum dan studio desain di Brisbane, serta presentasi proyek kolaboratif bersama mahasiswa UQ.',
  pg_temp.wib('2026-07-31'), 'approved', pg_temp.wib('2026-08-10', '14:00'));
select pg_temp.bulk_pset(217, '{C21237263,C21227287,C21247300,C21227326,C21247339}', '{}', '{PG761401}');

-- AY 2026/2027 Ganjil
select pg_temp.bulk_act(218, 'Magang Desain Interior di Design Lab KMUTT Bangkok', 30, 21, 'outbound', '2026-08-03', '2026-09-11', 'offline',
  'KMUTT Bangmod Campus, Bangkok', 'TH', 108, '{4,8}', 'Magang enam minggu di Design Lab KMUTT yang menangani proyek interior ruang belajar kampus, meliputi survei pengguna, gambar kerja, dan visualisasi 3D.',
  pg_temp.daysago(8), 'pending', null);
select pg_temp.bulk_pset(218, '{C21257365,C21247387}', '{}', '{}');

select pg_temp.bulk_act(219, 'Inbound Short Program Kriya Nusantara untuk Mahasiswa KMUTT', 30, 23, 'inbound', '2026-08-10', '2026-08-28', 'offline',
  'Kampus PCU Siwalankerto', 'ID', 108, '{4,17}', 'Program singkat tiga minggu bagi mahasiswa KMUTT untuk mempelajari kriya Nusantara (batik, anyaman, ukir kayu) melalui kelas praktik dan kunjungan ke sentra kerajinan Jawa Timur.',
  pg_temp.daysago(15), 'revision_requested', pg_temp.daysago(9, '14:00'),
  p_mnote => 'Transkrip nilai peserta belum diunggah dan poster kegiatan masih memakai logo lama. Mohon lengkapi bundel transkrip/poster/dokumentasi lalu ajukan ulang.');
select pg_temp.bulk_pset(219, '{}', '{X02260627}', '{}');

select pg_temp.bulk_act(220, 'Riset Bersama Material Daur Ulang untuk Interior Ruang Publik dengan NTUST', 30, 4, 'inbound', '2026-08-03', '2026-09-18', 'hybrid',
  'Laboratorium Material Desain Gedung P PCU', 'ID', 103, '{9,11,12}', 'Penelitian bersama pengembangan panel interior dari limbah plastik dan serbuk kayu untuk ruang publik, termasuk uji ketahanan dan purwarupa panel akustik.',
  pg_temp.wib('2026-09-25'), null, null,
  p_ext => '[{"full_name":"Assoc. Prof. Lin Yu-Ting","institution":"National Taiwan University of Science and Technology","country_code":"TW","role":"researcher","notes":"Department of Architecture"}]');

select pg_temp.bulk_act(221, 'Kompetisi Poster Warisan Budaya Asia Tenggara bersama De La Salle University', 30, 35, 'outbound', '2026-08-17', '2026-09-04', 'online',
  'Zoom Meeting', null, 109, '{4,11,17}', 'Kompetisi poster daring bertema warisan budaya takbenda Asia Tenggara yang dijuri bersama dosen FSD PCU dan De La Salle University, ditutup dengan pengumuman pemenang dan pameran virtual.',
  pg_temp.wib('2026-09-14'), null, null,
  p_ext => '[{"full_name":"Prof. Ramon Villanueva","institution":"De La Salle University","country_code":"PH","role":"other","notes":"Juri, Multimedia Arts Program"}]');

select pg_temp.bulk_act(222, 'Academic Exchange Desain Pameran dan Kuratorial di NTUST', 30, 28, 'outbound', '2026-08-24', '2026-09-18', 'offline',
  'Department of Design, NTUST, Taipei', 'TW', 103, '{4,17}', 'Pertukaran akademik empat minggu untuk mempelajari desain pameran dan praktik kuratorial di NTUST, termasuk keterlibatan dalam penyiapan pameran tahunan mahasiswa desain.',
  pg_temp.daysago(4), 'pending', null);
select pg_temp.bulk_pset(222, '{C21227418,C21237442,C21227130}', '{}', '{}');

select pg_temp.bulk_act(223, 'Seminar Nasional Pelestarian Interior Bangunan Kolonial Surabaya bersama ITB', 30, 10, 'inbound', '2026-09-09', '2026-09-10', 'offline',
  'Auditorium Gedung W PCU', 'ID', 110, '{4,11}', 'Seminar dua hari tentang konservasi dan adaptasi interior bangunan kolonial di Surabaya, menghadirkan akademisi ITB dan praktisi cagar budaya, disertai tur lapangan ke kawasan Kota Lama.',
  pg_temp.wib('2026-09-21'), null, null,
  p_ext => '[{"full_name":"Dr. Ir. Bambang Setia Budi, M.T.","institution":"Institut Teknologi Bandung","country_code":"ID","role":"speaker","notes":"Sekolah Arsitektur, Perencanaan dan Pengembangan Kebijakan"}]');

-- Drafts
select pg_temp.bulk_act(224, 'Winter Program Craft Heritage dan Desain Kriya di NTUST 2027', 30, 23, 'outbound', '2027-01-11', '2027-01-29', 'offline',
  'Department of Design, NTUST, Taipei', 'TW', 103, '{4,8,11}', 'Rencana program musim dingin di NTUST untuk mempelajari pengembangan kriya tradisional menjadi produk desain kontemporer, termasuk kunjungan ke sentra kerajinan di Taiwan.',
  null, null, null, p_files => '{ia}');
select pg_temp.bulk_pset(224, '{C21247035,C21247065}', '{}', '{}');

select pg_temp.bulk_act(225, 'Pameran Dies Natalis FSD Craft Heritage Batik dan Wayang bersama ITB', 30, 35, 'inbound', '2026-11-16', '2026-11-20', 'offline',
  'Galeri Gedung P PCU', 'ID', 110, '{4,11}', 'Rencana pameran Dies Natalis FSD yang menampilkan karya batik dan wayang kontemporer hasil kolaborasi dosen dan mahasiswa FSD PCU dengan FSRD ITB.',
  null, null, null, p_files => '{}');

select pg_temp.bulk_verify(201, 225);
