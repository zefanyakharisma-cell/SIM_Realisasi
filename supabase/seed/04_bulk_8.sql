-- 04_bulk_8: workflow edge cases across all units (queue, revisions, late, out-of-scope, archived/renewed docs, drafts). RL-2026-0276..0300. Students: the 04_bulk_8 slice of 04_bulk_0_registry.sql.
\ir bulk/_helpers.inc

-- AY 2025/2026 Ganjil
-- archived Osaka agreement (904), ended before its 2026-03-31 expiry
select pg_temp.bulk_act(276, 'Riset Bersama Sensor Getaran Struktur Jembatan dengan Osaka University', 10, 4, 'outbound', '2025-10-06', '2026-01-30', 'offline',
  'Suita Campus, Osaka University', 'JP', 904, '{9,11}', 'Riset bersama pengembangan sensor getaran berbasis MEMS untuk pemantauan kesehatan struktur jembatan. Tim FTI melakukan kalibrasi prototipe di laboratorium Osaka University dan menyusun draf artikel bersama.',
  pg_temp.wib('2026-02-12'), null, null,
  p_ext => '[{"full_name":"Prof. Dr. Hiroshi Tanaka","institution":"Osaka University","country_code":"JP","role":"researcher","notes":"Ketua tim riset mitra"}]');

-- archived-chain coverage lives on 904/905 below (Saxion 119 was terminated 2025-06-30, before AY 2025/2026)
select pg_temp.bulk_act(277, 'Kuliah Tamu Lean Production 4.0 dari Kyoto Institute of Technology', 10, 7, 'inbound', '2025-11-12', '2025-11-12', 'offline',
  'Auditorium Gedung P PCU', 'ID', 115, '{8,9}', 'Kuliah tamu tentang penerapan lean production yang terintegrasi dengan sensor IoT di industri manufaktur Jepang, diikuti mahasiswa Teknik Industri dan Informatika FTI.',
  pg_temp.wib('2025-11-20'), null, null,
  p_ext => '[{"full_name":"Prof. Dr. Takeshi Morimoto","institution":"Kyoto Institute of Technology","country_code":"JP","role":"speaker"}]');

-- late submission (end + 81 days), still before the Ganjil freeze
select pg_temp.bulk_act(278, 'Short Program Power Electronics di Hochschule Bremen', 12, 23, 'outbound', '2025-10-13', '2025-10-31', 'offline',
  'Hochschule Bremen, Campus Neustadtswall', 'DE', 104, '{4,7}', 'Program singkat tiga minggu tentang desain konverter daya dan inverter untuk sistem energi terbarukan. Mahasiswa Teknik Elektro mengikuti kuliah, praktikum laboratorium, dan kunjungan ke industri turbin angin di Bremerhaven.',
  pg_temp.wib('2026-01-20'), 'approved', pg_temp.wib('2026-01-29', '14:00'));
select pg_temp.bulk_pset(278, '{B12248507,B12248531}', '{}', '{PG204517}');

-- fully online
select pg_temp.bulk_act(279, 'Kuliah Tamu Daring Motion Graphics untuk Kampanye Sosial bersama The University of Queensland', 31, 7, 'inbound', '2025-12-03', '2025-12-03', 'online',
  'Zoom Meeting', null, 106, '{4,17}', 'Kuliah tamu daring tentang perancangan motion graphics untuk kampanye kesadaran sosial, termasuk studi kasus kampanye kesehatan publik di Queensland dan sesi tanya jawab portofolio.',
  pg_temp.wib('2025-12-10'), null, null,
  p_ext => '[{"full_name":"Dr. Emma Fitzgerald","institution":"The University of Queensland","country_code":"AU","role":"speaker"}]');

select pg_temp.bulk_act(280, 'Inbound Exchange Tunghai University Semester Ganjil 2025/2026', 20, 2, 'inbound', '2025-09-01', '2026-01-16', 'offline',
  'Kampus PCU Siwalankerto', 'ID', 114, '{4,17}', 'Mahasiswa pertukaran dari Tunghai University mengikuti satu semester perkuliahan reguler FBE, termasuk mata kuliah Bisnis Internasional dan kelas Bahasa Indonesia untuk penutur asing.',
  pg_temp.wib('2026-01-26'), 'approved', pg_temp.wib('2026-02-04', '14:00'));
select pg_temp.bulk_pset(280, '{}', '{X01250694}', '{PG818524}');

-- out of scope: Prodi Manajemen (21) on KMUTT (scope 20, 30)
select pg_temp.bulk_act(281, 'Joint Webinar Manajemen Operasi Rantai Halal Asia Tenggara bersama KMUTT', 21, 10, 'inbound', '2025-11-25', '2025-11-25', 'hybrid',
  'Ruang Seminar Gedung T PCU', 'ID', 108, '{8,12}', 'Webinar hibrida yang membahas tantangan sertifikasi dan logistik produk halal di Thailand dan Indonesia, dengan pembicara dari KMUTT dan dosen Manajemen PCU.',
  pg_temp.wib('2025-12-02'), null, null,
  p_ext => '[{"full_name":"Assoc. Prof. Dr. Somchai Prasertsri","institution":"King Mongkut''s University of Technology Thonburi","country_code":"TH","role":"speaker"}]');

-- AY 2025/2026 Genap
-- renewal of the Osaka agreement (905)
select pg_temp.bulk_act(282, 'Staff Exchange Laboratorium Mekatronika ke Osaka University', 10, 3, 'outbound', '2026-05-11', '2026-05-22', 'offline',
  'Suita Campus, Osaka University', 'JP', 905, '{4,9}', 'Dua dosen FTI menjalani program pertukaran staf di laboratorium mekatronika Osaka University untuk mempelajari tata kelola laboratorium riset dan merancang praktikum bersama pada perjanjian yang diperbarui.',
  pg_temp.wib('2026-06-03'), null, null,
  p_ext => '[{"full_name":"Assoc. Prof. Kenji Morimoto","institution":"Osaka University","country_code":"JP","role":"staff_visitor","notes":"Tuan rumah program di Osaka"}]');

-- late submission (end + 45 days)
select pg_temp.bulk_act(283, 'Cultural Exchange Seni Tradisi Jawa untuk Mahasiswa De La Salle University', 30, 29, 'inbound', '2026-02-09', '2026-03-20', 'offline',
  'Studio Desain Gedung P PCU', 'ID', 109, '{4,11}', 'Mahasiswa De La Salle University mengikuti program enam minggu tentang batik, wayang, dan ragam hias Jawa Timur, ditutup dengan pameran karya kolaboratif bersama mahasiswa FSD.',
  pg_temp.wib('2026-05-04'), 'approved', pg_temp.wib('2026-05-12', '14:00'));
select pg_temp.bulk_pset(283, '{}', '{X01260708}', '{PG761401}');

-- fully online
select pg_temp.bulk_act(284, 'Online Course Cloud Native Development dari Nanyang Polytechnic', 11, 79, 'inbound', '2026-03-02', '2026-04-24', 'online',
  'Microsoft Teams', null, 113, '{4,9}', 'Kursus daring delapan minggu tentang container, Kubernetes, dan CI/CD yang diampu dosen Nanyang Polytechnic untuk mahasiswa Informatika, dengan proyek akhir deployment aplikasi mikroservis.',
  pg_temp.wib('2026-05-06'), null, null,
  p_ext => '[{"full_name":"Mr. Lim Wei Jie","institution":"Nanyang Polytechnic","country_code":"SG","role":"visiting_lecturer"}]');

-- out of scope: Prodi DKV (31) on ITB (scope 10, 30)
select pg_temp.bulk_act(285, 'Pameran Bersama Tipografi Nusantara bersama ITB', 31, 35, 'outbound', '2026-04-20', '2026-04-25', 'offline',
  'Galeri Soemardja, Institut Teknologi Bandung', 'ID', 110, '{4,11}', 'Pameran karya tipografi berbasis aksara daerah hasil kolaborasi mahasiswa DKV PCU dan FSRD ITB, disertai diskusi kuratorial tentang digitalisasi aksara Nusantara.',
  pg_temp.wib('2026-05-02'), null, null,
  p_ext => '[{"full_name":"Dr. Andi Wiranata, M.Sn.","institution":"Institut Teknologi Bandung","country_code":"ID","role":"other","notes":"Kurator pameran"}]');

-- late submission (end + 52 days), before the Genap freeze
select pg_temp.bulk_act(286, 'Pengabdian Masyarakat Pembukuan Digital UMKM Kampung Lawas Maspati bersama Universitas Airlangga', 20, 40, 'outbound', '2026-06-15', '2026-06-19', 'offline',
  'Kampung Lawas Maspati, Surabaya', 'ID', 112, '{1,8}', 'Dosen dan mahasiswa FBE bersama tim Universitas Airlangga mendampingi pelaku UMKM kampung wisata dalam pencatatan keuangan sederhana menggunakan aplikasi kasir digital.',
  pg_temp.wib('2026-08-10'), null, null,
  p_ext => '[{"full_name":"Dr. Rahmawati Santoso, S.E., M.Ak.","institution":"Universitas Airlangga","country_code":"ID","role":"other","notes":"Koordinator tim Unair"}]');

-- AY 2026/2027 Ganjil — Mobility queue (pending)
select pg_temp.bulk_act(287, 'Inbound Credit Transfer Informatika NTUST Musim Panas 2026', 11, 33, 'inbound', '2026-07-20', '2026-09-11', 'offline',
  'Laboratorium Informatika Gedung P PCU', 'ID', 103, '{4,9}', 'Mahasiswa NTUST mengambil dua mata kuliah Informatika (Pemrograman Mobile dan Data Mining) dengan pengakuan kredit di kampus asal.',
  pg_temp.daysago(2), 'pending', null);
select pg_temp.bulk_pset(287, '{}', '{X02260704}', '{PG564518}');

select pg_temp.bulk_act(288, 'Academic Exchange Sistem Kendali Cerdas Hochschule Bremen 2026', 12, 28, 'inbound', '2026-08-03', '2026-09-25', 'offline',
  'Laboratorium Teknik Elektro Gedung W PCU', 'ID', 104, '{4,7}', 'Mahasiswa Hochschule Bremen melakukan pertukaran akademik di laboratorium Teknik Elektro, mengerjakan proyek kendali cerdas untuk sistem panel surya skala kecil.',
  pg_temp.daysago(5), 'pending', null);
select pg_temp.bulk_pset(288, '{}', '{X01260711}', '{PG703063}');

select pg_temp.bulk_act(289, 'Magang Akuntansi dan Logistik Internasional di KMUTT Bangkok', 20, 21, 'outbound', '2026-08-03', '2026-09-11', 'offline',
  'KMUTT Bang Mod Campus, Bangkok', 'TH', 108, '{8,17}', 'Mahasiswa Akuntansi magang enam minggu di unit keuangan dan logistik KMUTT serta mitra industrinya, mempelajari pelaporan biaya rantai pasok lintas negara.',
  pg_temp.daysago(8), 'pending', null);
select pg_temp.bulk_pset(289, '{D32238670,D32238688}', '{}', '{PG818524}');

select pg_temp.bulk_act(290, 'Short Program Animation and Game Art di The University of Queensland', 31, 23, 'outbound', '2026-08-17', '2026-09-11', 'offline',
  'St Lucia Campus, The University of Queensland', 'AU', 106, '{4,9}', 'Program singkat empat minggu tentang animasi 3D dan desain aset gim, ditutup dengan presentasi prototipe gim pendek di depan dosen UQ.',
  pg_temp.daysago(11), 'pending', null);
select pg_temp.bulk_pset(290, '{C21248762,C21248785,C21238790}', '{}', '{PG452412}');

select pg_temp.bulk_act(291, 'Studi Ekskursi Industri Otomotif Thailand bersama Chulalongkorn University', 10, 24, 'outbound', '2026-08-24', '2026-08-29', 'offline',
  'Faculty of Engineering, Chulalongkorn University', 'TH', 901, '{9,12}', 'Kunjungan studi ke Chulalongkorn University dan kawasan industri otomotif Rayong untuk mempelajari otomasi lini perakitan dan sistem informasi manufaktur.',
  pg_temp.daysago(12), 'pending', null);
select pg_temp.bulk_pset(291, '{B11238368,B11258405,B12238545}', '{}', '{PG707752}');

-- Revision requested
select pg_temp.bulk_act(292, 'Credit Transfer Kewirausahaan Sosial di Universitas Gadjah Mada', 21, 33, 'outbound', '2026-08-10', '2026-09-11', 'offline',
  'Kampus Bulaksumur UGM, Yogyakarta', 'ID', 111, '{4,8}', 'Mahasiswa Manajemen mengikuti mata kuliah Kewirausahaan Sosial di UGM selama lima minggu dengan pengakuan kredit, termasuk proyek lapangan bersama koperasi petani di Sleman.',
  pg_temp.daysago(15), 'revision_requested', pg_temp.daysago(6, '14:00'),
  p_mnote => 'NRP peserta D31238650 pada daftar peserta tidak sama dengan NRP di surat tugas (tertulis D31238605). Mohon periksa kembali NRP dan unggah ulang surat tugas yang benar.');
select pg_temp.bulk_pset(292, '{D31238647,D31238650}', '{}', '{PG295222}');

select pg_temp.bulk_act(293, 'Immersion Program Filipino Visual Culture di De La Salle University', 30, 22, 'outbound', '2026-08-17', '2026-09-04', 'offline',
  'De La Salle University, Taft Avenue, Manila', 'PH', 109, '{4,11}', 'Program imersi tiga minggu tentang budaya visual Filipina: kunjungan museum, lokakarya ilustrasi jeepney art, dan kolaborasi poster dengan mahasiswa DLSU.',
  pg_temp.daysago(18), 'revision_requested', pg_temp.daysago(9, '14:00'),
  p_mnote => 'Transkrip nilai C21258839 hanya memuat halaman 1 dari 2; halaman rincian mata kuliah dan tanda tangan registrar DLSU belum ada. Mohon unggah transkrip lengkap.');
select pg_temp.bulk_pset(293, '{C21238809,C21258839}', '{}', '{PG780858}');

select pg_temp.bulk_act(294, 'Academic Exchange Laboratorium Robotika Kyoto Institute of Technology', 12, 28, 'outbound', '2026-08-31', '2026-09-18', 'offline',
  'Matsugasaki Campus, Kyoto Institute of Technology', 'JP', 101, '{4,9}', 'Mahasiswa Teknik Elektro bergabung dengan laboratorium robotika KIT selama tiga minggu untuk mengembangkan pengendali lengan robot berbasis visi komputer.',
  pg_temp.daysago(9), 'revision_requested', pg_temp.daysago(3, '14:00'),
  p_mnote => 'Tanggal kegiatan (31 Agustus - 18 September 2026) tidak sesuai dengan surat tugas No. 412/FTI/VIII/2026 yang mencantumkan 1 - 19 September 2026. Mohon sesuaikan tanggal kegiatan atau unggah surat tugas revisi.');
select pg_temp.bulk_pset(294, '{B12248565,B12238571}', '{}', '{PG413450}');

-- fully online
select pg_temp.bulk_act(295, 'Pelatihan Daring Analitik Data Pelanggan bersama PT Telkom Indonesia', 21, 69, 'inbound', '2026-08-18', '2026-08-20', 'online',
  'Microsoft Teams', null, 117, '{4,8}', 'Pelatihan daring tiga hari tentang segmentasi pelanggan dan analitik churn menggunakan data telekomunikasi anonim, dibawakan praktisi PT Telkom Indonesia untuk mahasiswa dan dosen Manajemen.',
  pg_temp.wib('2026-08-27'), null, null,
  p_ext => '[{"full_name":"Ir. Bambang Hartono, M.M.","institution":"PT Telkom Indonesia","country_code":"ID","role":"speaker"}]');

-- Drafts
-- past its reporting deadline (ended 2026-08-12, deadline 2026-09-11)
select pg_temp.bulk_act(296, 'Kuliah Tamu Cybersecurity Operations Center dari Nanyang Polytechnic', 11, 15, 'inbound', '2026-08-12', '2026-08-12', 'offline',
  'Auditorium Gedung P PCU', 'ID', 113, '{4,9}', 'Kuliah tamu tentang operasional Security Operations Center, simulasi penanganan insiden, dan jalur karier keamanan siber bagi mahasiswa Informatika.',
  null, null, null,
  p_ext => '[{"full_name":"Mr. Tan Kok Wee","institution":"Nanyang Polytechnic","country_code":"SG","role":"speaker"}]');

-- missing IR
select pg_temp.bulk_act(297, 'Seminar Bersama Ekonomi Digital Korea-Indonesia dengan Hanyang University', 20, 10, 'inbound', '2026-09-22', '2026-09-22', 'hybrid',
  'Ruang Seminar Gedung T PCU', 'ID', 102, '{8,17}', 'Seminar hibrida yang membandingkan ekosistem platform digital dan regulasi e-commerce di Korea Selatan dan Indonesia, dengan pembicara dari Hanyang University.',
  null, null, null, p_files => '{ia}',
  p_ext => '[{"full_name":"Prof. Dr. Park Ji-hoon","institution":"Hanyang University","country_code":"KR","role":"speaker"}]');

-- missing IR
select pg_temp.bulk_act(298, 'Penyusunan Kurikulum Bersama Desain Interaktif dengan The University of Queensland', 31, 32, 'inbound', '2026-09-14', '2026-09-25', 'offline',
  'Ruang Rapat Gedung P PCU', 'ID', 106, '{4,17}', 'Lokakarya penyusunan kurikulum bersama mata kuliah Desain Interaktif dan UX, menyelaraskan capaian pembelajaran DKV PCU dengan program UQ untuk rencana pengakuan kredit.',
  null, null, null, p_files => '{ia}',
  p_ext => '[{"full_name":"Assoc. Prof. Daniel O''Connor","institution":"The University of Queensland","country_code":"AU","role":"visiting_lecturer"}]');

-- upcoming Nov-Dec 2026
select pg_temp.bulk_act(299, 'Winter Program Renewable Energy Systems di Kyoto Institute of Technology', 12, 23, 'outbound', '2026-11-23', '2026-12-04', 'offline',
  'Matsugasaki Campus, Kyoto Institute of Technology', 'JP', 115, '{7,13}', 'Program musim dingin dua minggu tentang integrasi energi surya dan penyimpanan baterai, termasuk praktikum laboratorium dan kunjungan ke fasilitas smart grid di Kyoto.',
  null, null, null, p_files => '{}');
select pg_temp.bulk_pset(299, '{B12248507,B12248531}', '{}', '{PG204517}');

-- upcoming Dec 2026 on the future Stuttgart agreement (902)
select pg_temp.bulk_act(300, 'Kuliah Tamu Model Bisnis Industrie 4.0 dari Universität Stuttgart', 20, 7, 'inbound', '2026-12-08', '2026-12-08', 'offline',
  'Auditorium Gedung W PCU', 'ID', 902, '{8,9}', 'Kuliah tamu perdana dalam kerja sama dengan Universität Stuttgart tentang model bisnis berbasis Industrie 4.0 dan transformasi digital UKM manufaktur Jerman.',
  null, null, null, p_files => '{}',
  p_ext => '[{"full_name":"Prof. Dr. Thomas Weber","institution":"Universität Stuttgart","country_code":"DE","role":"speaker"}]');

select pg_temp.bulk_verify(276, 300);
