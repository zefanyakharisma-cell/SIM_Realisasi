-- 04_bulk_7: cross-unit / multi-unit programs (joint faculties, faculty + prodi, university-wide). RL-2026-0251..0275. Students: the 04_bulk_7 slice of 04_bulk_0_registry.sql.
\ir bulk/_helpers.inc

-- AY 2025/2026 Ganjil
select pg_temp.bulk_act(251, 'Immersion Program Design Thinking & Business Innovation di KMUTT', 20, 22, 'outbound', '2025-08-11', '2025-08-22', 'offline',
  'KMUTT Bang Mod Campus, Bangkok', 'TH', 108, '{4,8,9}', 'Program imersi gabungan FBE dan FSD di King Mongkut''s University of Technology Thonburi: mahasiswa Manajemen, Akuntansi, dan DKV bekerja dalam tim lintas disiplin merancang prototipe bisnis kreatif dengan metode design thinking, ditutup dengan pitching di depan mentor KMUTT.',
  pg_temp.wib('2025-08-29'), 'approved', pg_temp.wib('2025-09-05', '14:00'), p_co_units => '{30}');
select pg_temp.bulk_pset(251, '{D31248081,D31238088,D32248164,C21258276,C21258296}', '{}', '{PG818524}');

select pg_temp.bulk_act(252, 'Pameran Bersama Desain Produk Berkelanjutan FTI–FSD bersama ITB', 10, 35, 'inbound', '2025-09-15', '2025-09-19', 'offline',
  'Galeri Gedung P PCU', 'ID', 110, '{9,12}', 'Pameran karya bersama mahasiswa Teknik Industri, Teknik Elektro, dan Desain Produk PCU dengan Fakultas Seni Rupa dan Desain ITB yang menampilkan 40 prototipe produk ramah lingkungan, dilengkapi sesi kurasi dan diskusi panel tentang material daur ulang.',
  pg_temp.wib('2025-09-25'), null, null, p_co_units => '{30,12}',
  p_ext => '[{"full_name":"Dr. Andar Bagus Sriwarno, M.Ds.","institution":"Institut Teknologi Bandung (ITB)","country_code":"ID","role":"speaker","notes":"Kurator dan panelis diskusi material daur ulang"},
             {"full_name":"Prof. Dr. Imam Santosa, M.Sn.","institution":"Institut Teknologi Bandung (ITB)","country_code":"ID","role":"speaker"}]');

select pg_temp.bulk_act(253, 'International Conference on Applied Computing and Embedded Systems (ICACES) 2025 bersama Nanyang Polytechnic', 10, 10, 'inbound', '2025-10-08', '2025-10-09', 'hybrid',
  'Auditorium Gedung W PCU', 'ID', 113, '{4,9,17}', 'Konferensi internasional tingkat universitas yang diselenggarakan FTI bersama Prodi Informatika dan International Office dengan Nanyang Polytechnic; menghadirkan 62 makalah tentang sistem tertanam, IoT, dan komputasi terapan serta keynote dari School of Engineering NYP.',
  pg_temp.wib('2025-10-20'), null, null, p_co_units => '{11,2}',
  p_ext => '[{"full_name":"Dr. Lim Wei Sheng","institution":"Nanyang Polytechnic","country_code":"SG","role":"speaker","notes":"Keynote: Edge AI for Smart Manufacturing"},
             {"full_name":"Ms. Tan Hui Min","institution":"Nanyang Polytechnic","country_code":"SG","role":"speaker","notes":"Panel industri 4.0"}]');

select pg_temp.bulk_act(254, 'Student Exchange Semester Ganjil Informatika dan Desain di NTUST', 11, 2, 'outbound', '2025-09-01', '2026-01-16', 'offline',
  'NTUST Gongguan Campus, Taipei', 'TW', 103, '{4,9}', 'Pertukaran satu semester bagi mahasiswa Informatika dan DKV di National Taiwan University of Science and Technology; peserta mengambil mata kuliah Human-Computer Interaction dan Interactive Media Design yang diakui melalui transfer kredit.',
  pg_temp.wib('2026-01-26'), 'approved', pg_temp.wib('2026-02-04', '14:00'), p_co_units => '{30,31}');
select pg_temp.bulk_pset(254, '{B11257857,B11257886,C21258305}', '{}', '{}');

select pg_temp.bulk_act(255, 'Inbound Academic Exchange Kyoto Institute of Technology di Laboratorium Sistem Kontrol FTI', 10, 28, 'inbound', '2025-10-01', '2025-12-19', 'offline',
  'Laboratorium Sistem Kontrol Gedung P PCU', 'ID', 101, '{4,9}', 'Mahasiswa Kyoto Institute of Technology mengikuti pertukaran akademik di FTI dengan pembimbingan bersama dosen Teknik Elektro dan Informatika, mengerjakan proyek sistem kontrol robot pemindah barang berbasis visi komputer.',
  pg_temp.wib('2025-12-29'), 'approved', pg_temp.wib('2026-01-08', '14:00'), p_co_units => '{11,12}');
select pg_temp.bulk_pset(255, '{}', '{X01250671}', '{PG413450}');

select pg_temp.bulk_act(256, 'Kuliah Bersama Brand Strategy & Visual Identity dengan Hanyang University', 20, 34, 'inbound', '2025-11-04', '2025-11-25', 'online',
  'Zoom Meeting', null, 102, '{4,8}', 'Empat sesi kuliah bersama daring antara FBE, Prodi Manajemen, dan Prodi DKV dengan Hanyang University Business School tentang strategi merek dan identitas visual; mahasiswa lintas prodi menyusun brand audit untuk UMKM Surabaya.',
  pg_temp.wib('2025-12-02'), null, null, p_co_units => '{21,31}',
  p_ext => '[{"full_name":"Prof. Kim Ji-hoon","institution":"Hanyang University","country_code":"KR","role":"visiting_lecturer","notes":"Pengampu sesi brand strategy"}]');

select pg_temp.bulk_act(257, 'Inbound Cultural Exchange UQ: Batik dan Desain Nusantara', 30, 29, 'inbound', '2025-11-10', '2025-11-28', 'offline',
  'Kampus PCU Siwalankerto', 'ID', 106, '{4,11}', 'Program pertukaran budaya tiga minggu untuk mahasiswa The University of Queensland yang dikelola FSD, Prodi DKV, dan International Office: lokakarya batik, kunjungan sentra kriya Madura, dan proyek desain motif kontemporer bersama mahasiswa DKV.',
  pg_temp.wib('2025-12-05'), 'approved', pg_temp.wib('2025-12-12', '14:00'), p_co_units => '{31,2}');
select pg_temp.bulk_pset(257, '{}', '{X01250685}', '{PG780858}');

select pg_temp.bulk_act(258, 'Service Learning Digitalisasi UMKM Kampung Lontong bersama Universitas Airlangga', 20, 40, 'outbound', '2025-12-01', '2025-12-12', 'offline',
  'Kampung Lontong Banyu Urip, Surabaya', 'ID', 112, '{1,8,17}', 'Pengabdian masyarakat bersama FBE, Prodi Manajemen, dan Prodi Informatika dengan FEB Universitas Airlangga: pendampingan pencatatan keuangan sederhana, katalog digital, dan pembayaran QRIS bagi 25 pelaku UMKM lontong.',
  pg_temp.wib('2025-12-18'), null, null, p_co_units => '{21,11}',
  p_ext => '[{"full_name":"Dr. Rahmat Setiawan, S.E., M.M.","institution":"Universitas Airlangga","country_code":"ID","role":"other","notes":"Koordinator lapangan dari FEB Unair"}]');

-- AY 2025/2026 Genap
select pg_temp.bulk_act(259, 'Winter Short Program Smart Factory & Electrical Engineering di Kyoto Institute of Technology', 10, 23, 'outbound', '2026-02-02', '2026-02-20', 'offline',
  'Kyoto Institute of Technology Matsugasaki Campus', 'JP', 115, '{4,7,9}', 'Program singkat tiga minggu bagi mahasiswa Teknik Elektro dan Informatika di KIT: kuliah otomasi pabrik, praktikum PLC dan sensor, serta kunjungan ke fasilitas manufaktur di Kansai.',
  pg_temp.wib('2026-03-02'), 'approved', pg_temp.wib('2026-03-10', '14:00'), p_co_units => '{12,11}');
select pg_temp.bulk_pset(259, '{B12237949,B12257959,B12257992,B11227896}', '{}', '{PG204517}');

select pg_temp.bulk_act(260, 'Inbound Student Exchange Hanyang University Genap 2026 Manajemen', 21, 2, 'inbound', '2026-02-09', '2026-06-26', 'offline',
  'Gedung T PCU', 'ID', 102, '{4,17}', 'Mahasiswa Hanyang University mengikuti satu semester di Prodi Manajemen dengan mata kuliah pilihan dari FBE (Pemasaran Digital, Kewirausahaan Asia Tenggara) dan didampingi buddy mahasiswa Manajemen.',
  pg_temp.wib('2026-07-06'), 'approved', pg_temp.wib('2026-07-15', '14:00'), p_co_units => '{20}');
select pg_temp.bulk_pset(260, '{}', '{X01260674}', '{PG295222}');

select pg_temp.bulk_act(261, 'Inbound Study Abroad Fontys: International Business in Southeast Asia', 20, 20, 'inbound', '2026-02-16', '2026-06-12', 'offline',
  'Gedung T PCU', 'ID', 105, '{4,8,17}', 'Program study abroad satu semester untuk mahasiswa Fontys yang dikelola FBE, Prodi Manajemen, dan International Office; mencakup modul bisnis internasional Asia Tenggara, kunjungan industri Surabaya, dan proyek konsultasi bersama mahasiswa lokal.',
  pg_temp.wib('2026-06-22'), 'approved', pg_temp.wib('2026-07-01', '14:00'), p_co_units => '{21,2}');
select pg_temp.bulk_pset(261, '{}', '{X01260677}', '{PG974721}');

select pg_temp.bulk_act(262, 'Petra–KMUTT International Week 2026: Sustainable Business and Creative Economy', 30, 10, 'inbound', '2026-03-09', '2026-03-13', 'hybrid',
  'Auditorium Gedung W PCU', 'ID', 108, '{8,12,17}', 'Pekan internasional tingkat universitas yang diselenggarakan FSD, FBE, International Office, dan Rektorat bersama KMUTT: seminar ekonomi kreatif, lokakarya kemasan berkelanjutan, dan pameran startup mahasiswa kedua kampus.',
  pg_temp.wib('2026-03-20'), null, null, p_co_units => '{20,2,1}',
  p_ext => '[{"full_name":"Assoc. Prof. Dr. Suthep Wongsawat","institution":"King Mongkut''s University of Technology Thonburi (KMUTT)","country_code":"TH","role":"speaker","notes":"Keynote sustainable business models"},
             {"full_name":"Dr. Pimchanok Rattanakul","institution":"King Mongkut''s University of Technology Thonburi (KMUTT)","country_code":"TH","role":"speaker","notes":"Lokakarya desain kemasan"}]');

select pg_temp.bulk_act(263, 'Riset Bersama Antarmuka Augmented Reality untuk Museum dengan NTUST', 11, 4, 'inbound', '2026-02-02', '2026-06-30', 'hybrid',
  'Laboratorium Multimedia Gedung P PCU', 'ID', 103, '{9,11}', 'Penelitian bersama Prodi Informatika, FSD, dan DKV dengan NTUST untuk merancang antarmuka AR pemandu koleksi Museum House of Sampoerna; luaran berupa prototipe aplikasi, uji pengguna dengan 60 pengunjung, dan draf artikel jurnal.',
  pg_temp.wib('2026-08-05'), null, null, p_co_units => '{30,31}',
  p_ext => '[{"full_name":"Prof. Dr. Chen Yu-Ting","institution":"National Taiwan University of Science and Technology (NTUST)","country_code":"TW","role":"researcher","notes":"Peneliti utama dari Department of Design"}]');

select pg_temp.bulk_act(264, 'Magang Industri Kreatif dan Teknologi di Nanyang Polytechnic', 11, 21, 'outbound', '2026-06-01', '2026-07-24', 'offline',
  'Nanyang Polytechnic, Ang Mo Kio Campus', 'SG', 113, '{4,8}', 'Magang delapan minggu bagi mahasiswa Informatika dan DKV di pusat inovasi Nanyang Polytechnic, mengerjakan proyek aplikasi interaktif untuk klien industri di bawah supervisi bersama FTI dan Prodi DKV.',
  pg_temp.wib('2026-08-03'), 'approved', pg_temp.wib('2026-08-12', '14:00'), p_co_units => '{10,31}');
select pg_temp.bulk_pset(264, '{B11257931,B11237941,C21248336}', '{}', '{PG564518}');

select pg_temp.bulk_act(265, 'Pengembangan Kurikulum Bersama Minor Technopreneurship FTI–FBE dengan UTM', 10, 11, 'inbound', '2026-04-06', '2026-04-08', 'online',
  'Microsoft Teams', null, 107, '{4,8,9}', 'Lokakarya daring tiga hari antara FTI, FBE, dan Prodi Manajemen dengan Universiti Teknologi Malaysia untuk menyusun capaian pembelajaran dan struktur 20 SKS minor technopreneurship lintas fakultas.',
  pg_temp.wib('2026-04-15'), null, null, p_co_units => '{20,21}',
  p_ext => '[{"full_name":"Assoc. Prof. Dr. Nor Haslinda Ismail","institution":"Universiti Teknologi Malaysia (UTM)","country_code":"MY","role":"other","notes":"Narasumber desain kurikulum kewirausahaan teknologi"}]');

select pg_temp.bulk_act(266, 'Workshop Bersama Desain Kriya dan Rekayasa Material di ITB', 30, 35, 'outbound', '2026-05-11', '2026-05-13', 'offline',
  'Kampus ITB Ganesha, Bandung', 'ID', 110, '{9,12}', 'Lokakarya tiga hari dosen FSD, Prodi DKV, dan FTI bersama FSRD dan Teknik Material ITB tentang pemanfaatan limbah tekstil dan bambu sebagai material desain, menghasilkan rencana proyek bersama 2026/2027.',
  pg_temp.wib('2026-05-20'), null, null, p_co_units => '{31,10}',
  p_ext => '[{"full_name":"Dr. Ratna Panggabean, M.Ds.","institution":"Institut Teknologi Bandung (ITB)","country_code":"ID","role":"speaker"}]');

select pg_temp.bulk_act(267, 'Pelatihan Akuntansi Digital dan Analitik Bisnis bersama Universitas Airlangga', 20, 43, 'outbound', '2026-07-13', '2026-07-17', 'offline',
  'FEB Universitas Airlangga, Kampus B Surabaya', 'ID', 112, '{4,8}', 'Pelatihan lima hari bagi dosen dan asisten FBE serta Prodi Manajemen di FEB Unair tentang otomasi akuntansi berbasis cloud dan dashboard analitik bisnis, ditutup dengan sertifikasi internal.',
  pg_temp.wib('2026-07-27'), null, null, p_co_units => '{21}',
  p_ext => '[{"full_name":"Prof. Dr. Iswajuni, S.E., M.M., Ak.","institution":"Universitas Airlangga","country_code":"ID","role":"speaker"}]');

-- AY 2026/2027 Ganjil
select pg_temp.bulk_act(268, 'Hanyang International Summer School 2026 Business and Culture Track', 20, 23, 'outbound', '2026-08-03', '2026-08-21', 'offline',
  'Hanyang University Seoul Campus', 'KR', 102, '{4,8,17}', 'Summer school internasional tingkat universitas yang dikoordinasikan International Office bersama FBE dan Prodi Manajemen; mahasiswa Manajemen dan Akuntansi mengikuti modul Korean business culture dan corporate visit ke Seoul.',
  pg_temp.wib('2026-08-28'), 'approved', pg_temp.wib('2026-09-07', '14:00'), p_co_units => '{21,2}');
select pg_temp.bulk_pset(268, '{D31258117,D31228120,D32248200,D32258220}', '{}', '{PG214411}');

select pg_temp.bulk_act(269, 'Inbound Summer Program Tunghai University: Akuntansi dan Bisnis Digital Indonesia', 20, 23, 'inbound', '2026-08-03', '2026-08-28', 'offline',
  'Gedung T PCU', 'ID', 114, '{4,8}', 'Program singkat empat minggu untuk mahasiswa Tunghai University yang diselenggarakan FBE, Prodi Manajemen, dan International Office: kuliah akuntansi dan ekosistem bisnis digital Indonesia serta kunjungan ke startup Surabaya.',
  pg_temp.daysago(12), 'pending', null, p_co_units => '{21,2}');
select pg_temp.bulk_pset(269, '{}', '{X02250692}', '{PG637448}');

select pg_temp.bulk_act(270, 'Immersion Program Teknologi Energi Terbarukan di UTM', 10, 22, 'outbound', '2026-08-24', '2026-09-04', 'offline',
  'Universiti Teknologi Malaysia, Johor Bahru', 'MY', 107, '{4,7,13}', 'Program imersi dua minggu bagi mahasiswa Teknik Elektro dan Informatika di UTM tentang sistem panel surya, manajemen energi berbasis IoT, dan kunjungan ke pembangkit tenaga surya Johor.',
  pg_temp.daysago(8), 'pending', null, p_co_units => '{12,11}');
select pg_temp.bulk_pset(270, '{B12237949,B12238054,B11227896}', '{}', '{PG703063}');

select pg_temp.bulk_act(271, 'Cultural Exchange Desain dan Bisnis Kreatif di De La Salle University', 30, 29, 'outbound', '2026-08-10', '2026-08-21', 'offline',
  'De La Salle University, Taft Avenue Manila', 'PH', 109, '{4,8,11}', 'Pertukaran budaya dua minggu mahasiswa DKV, Manajemen, dan Akuntansi di De La Salle University dengan lokakarya ekonomi kreatif Filipina, kunjungan komunitas seniman Intramuros, dan presentasi proyek kolaboratif.',
  pg_temp.daysago(15), 'revision_requested', pg_temp.daysago(9, '14:00'), p_co_units => '{31,20}',
  p_mnote => 'Sertifikat partisipasi dari De La Salle University untuk D31238132 dan D32248247 belum ada di bundel mobilitas, dan dosen pendamping belum dicantumkan; mohon lengkapi lalu ajukan ulang.');
select pg_temp.bulk_pset(271, '{C21238349,C21248336,D31238132,D32248247}', '{}', '{}');

select pg_temp.bulk_act(272, 'Kuliah Tamu Internet of Things untuk Smart Building dari Chulalongkorn University', 10, 15, 'inbound', '2026-09-08', '2026-09-08', 'hybrid',
  'Auditorium Gedung P PCU', 'ID', 901, '{7,9,11}', 'Kuliah tamu gabungan FTI, Prodi Teknik Elektro, dan Prodi Informatika tentang integrasi IoT dan sistem manajemen energi gedung, dihadiri 180 mahasiswa luring dan daring.',
  pg_temp.wib('2026-09-14'), null, null, p_co_units => '{12,11}',
  p_ext => '[{"full_name":"Asst. Prof. Dr. Kittipong Srisuk","institution":"Chulalongkorn University","country_code":"TH","role":"speaker","notes":"Faculty of Engineering, Department of Electrical Engineering"}]');

select pg_temp.bulk_act(273, 'Kunjungan Akademik Pimpinan Universitas ke Osaka University untuk Penjajakan Joint Lab', 10, 27, 'outbound', '2026-09-14', '2026-09-17', 'offline',
  'Osaka University Suita Campus', 'JP', 905, '{9,17}', 'Kunjungan delegasi FTI bersama Rektorat dan International Office ke Osaka University untuk meninjau fasilitas riset material dan robotika serta menyepakati rencana joint laboratory sebagai tindak lanjut perpanjangan MoU.',
  pg_temp.wib('2026-09-24'), null, null, p_co_units => '{1,2}',
  p_ext => '[{"full_name":"Prof. Dr. Takahiro Nakamura","institution":"Osaka University","country_code":"JP","role":"other","notes":"Tuan rumah, Graduate School of Engineering"}]');

-- Drafts
select pg_temp.bulk_act(274, 'Joint Exhibition Petra–UQ Visual Storytelling 2026', 30, 35, 'inbound', '2026-11-16', '2026-11-20', 'offline',
  'Galeri Gedung P PCU', 'ID', 106, '{4,11}', 'Rencana pameran bersama karya visual storytelling mahasiswa DKV PCU dan The University of Queensland, didukung International Office, dengan sesi artist talk dan lokakarya komik digital.',
  null, null, null, p_files => '{ia}', p_co_units => '{31,2}');

select pg_temp.bulk_act(275, 'Fontys Winter School International Marketing 2027', 20, 23, 'outbound', '2027-01-11', '2027-01-22', 'offline',
  'Fontys University of Applied Sciences, Eindhoven', 'NL', 105, '{4,8}', 'Rencana winter school dua minggu di Fontys bagi mahasiswa Manajemen dan Akuntansi yang dikoordinasikan FBE dan International Office, berfokus pada pemasaran internasional dan riset pasar Eropa.',
  null, null, null, p_co_units => '{21,2}');
select pg_temp.bulk_pset(275, '{D31248081,D32228248}', '{}', '{}');

select pg_temp.bulk_verify(251, 275);
