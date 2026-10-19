-- 04_bulk_1: FTI (10) & Prodi Informatika (11) — computing, AI, data science, IoT, smart manufacturing, industrial engineering. RL-2026-0101..0125. Students: the 04_bulk_1 slice of 04_bulk_0_registry.sql.
\ir bulk/_helpers.inc

-- AY 2025/2026 Ganjil
select pg_temp.bulk_act(101, 'Kuliah Tamu Machine Learning untuk Visi Komputer dari Kyoto Institute of Technology', 11, 15, 'inbound', '2025-09-15', '2025-09-16', 'offline',
  'Auditorium Gedung P PCU', 'ID', 101, '{4,9}', 'Kuliah tamu dua hari tentang deep learning untuk inspeksi visual di industri manufaktur Jepang, disertai sesi praktik klasifikasi citra cacat produk bagi mahasiswa Informatika semester 5.',
  pg_temp.wib('2025-09-25'), null, null,
  p_ext => '[{"full_name":"Prof. Dr. Hiroshi Tanaka","institution":"Kyoto Institute of Technology","country_code":"JP","role":"visiting_lecturer","notes":"Laboratory of Intelligent Vision Systems"}]');

select pg_temp.bulk_act(102, 'Inbound Student Exchange Informatika Kyoto Institute of Technology Semester Ganjil 2025', 11, 2, 'inbound', '2025-09-01', '2025-12-19', 'offline',
  'Kampus PCU Siwalankerto', 'ID', 101, '{4,17}', 'Mahasiswa Kyoto Institute of Technology mengikuti satu semester perkuliahan Informatika di PCU (Pemrograman Web, Basis Data Lanjut, Kecerdasan Buatan) dengan pengakuan kredit di universitas asal.',
  pg_temp.wib('2026-01-08'), 'approved', pg_temp.wib('2026-01-15', '14:00'));
select pg_temp.bulk_pset(102, '{}', '{X01250509}', '{PG657970}');

select pg_temp.bulk_act(103, 'Riset Bersama Sensor IoT untuk Pertanian Presisi dengan UTM', 10, 4, 'outbound', '2025-10-13', '2025-10-17', 'offline',
  'UTM Johor Bahru Campus, Faculty of Electrical Engineering', 'MY', 107, '{2,9}', 'Tim dosen FTI melakukan kalibrasi bersama jaringan sensor kelembapan tanah berbasis LoRaWAN di kebun percobaan UTM serta menyusun rencana publikasi hasil uji lapangan.',
  pg_temp.wib('2025-10-28'), null, null,
  p_ext => '[{"full_name":"Assoc. Prof. Dr. Nurul Hidayah binti Ahmad","institution":"Universiti Teknologi Malaysia","country_code":"MY","role":"researcher"}]',
  p_co_units => '{12}');

select pg_temp.bulk_act(104, 'Short Program Data Science and Analytics di NTUST', 11, 23, 'outbound', '2025-10-20', '2025-11-07', 'offline',
  'NTUST Taipei Campus, Department of Computer Science and Information Engineering', 'TW', 103, '{4,9}', 'Program singkat tiga minggu berisi kuliah analitik big data, praktikum Python untuk machine learning, dan proyek kelompok analisis data transportasi publik kota Taipei.',
  pg_temp.wib('2025-11-20'), 'approved', pg_temp.wib('2025-11-27', '14:00'));
select pg_temp.bulk_pset(104, '{B11235038,B11245047,B11235071,B11235087}', '{}', '{PG488192}');

select pg_temp.bulk_act(105, 'Workshop Penyelarasan Kurikulum Rekayasa Perangkat Lunak bersama ITB', 10, 11, 'outbound', '2025-11-17', '2025-11-18', 'offline',
  'Kampus ITB Ganesha, Bandung', 'ID', 110, '{4}', 'Lokakarya penyelarasan capaian pembelajaran mata kuliah rekayasa perangkat lunak dan DevOps antara FTI PCU dan STEI ITB, menghasilkan draf peta mata kuliah setara untuk program pertukaran.',
  pg_temp.wib('2025-11-28'), null, null, p_co_units => '{11}');

select pg_temp.bulk_act(106, 'Inbound Short Program Industrial Automation Nanyang Polytechnic 2025', 10, 23, 'inbound', '2025-11-24', '2025-12-12', 'offline',
  'Laboratorium Sistem Manufaktur Gedung P PCU', 'ID', 113, '{4,9,17}', 'Mahasiswa Nanyang Polytechnic mengikuti program tiga minggu tentang otomasi lini produksi dengan PLC dan sistem MES, termasuk kunjungan industri ke kawasan SIER Surabaya.',
  pg_temp.wib('2025-12-22'), 'approved', pg_temp.wib('2026-01-05', '14:00'));
select pg_temp.bulk_pset(106, '{}', '{X01250523}', '{PG707752}');

select pg_temp.bulk_act(107, 'Kuliah Bersama Cloud Computing dengan Nanyang Polytechnic', 11, 34, 'inbound', '2025-09-08', '2025-12-12', 'online',
  'Microsoft Teams', null, 113, '{4,9}', 'Mata kuliah Cloud Computing diajarkan bersama secara daring oleh dosen Informatika PCU dan dosen Nanyang Polytechnic selama satu semester, mencakup arsitektur serverless dan kontainerisasi.',
  pg_temp.wib('2025-12-18'), null, null,
  p_ext => '[{"full_name":"Dr. Lim Wei Ming","institution":"Nanyang Polytechnic","country_code":"SG","role":"visiting_lecturer","notes":"School of Information Technology"}]');

select pg_temp.bulk_act(108, 'Magang Smart Factory di Kyoto Institute of Technology', 10, 21, 'outbound', '2026-01-05', '2026-01-30', 'offline',
  'Kyoto Institute of Technology, Matsugasaki Campus', 'JP', 115, '{8,9}', 'Mahasiswa Teknik Elektro magang di laboratorium robotika industri KIT, mengerjakan integrasi sensor dan kendali lengan robot untuk lini perakitan cerdas.',
  pg_temp.wib('2026-02-12'), 'approved', pg_temp.wib('2026-02-20', '14:00'));
select pg_temp.bulk_pset(108, '{B12245339,B12235372}', '{}', '{PG204517}');

-- AY 2025/2026 Genap
select pg_temp.bulk_act(109, 'Seminar Internasional AI for Smart Manufacturing bersama Kyoto Institute of Technology', 10, 35, 'inbound', '2026-02-24', '2026-02-25', 'hybrid',
  'Auditorium Gedung W PCU', 'ID', 115, '{8,9}', 'Seminar internasional dua hari membahas penerapan kecerdasan buatan pada pemeliharaan prediktif dan kendali kualitas, dihadiri 180 peserta luring dan daring dari kampus serta industri Jawa Timur.',
  pg_temp.wib('2026-03-06'), null, null,
  p_ext => '[{"full_name":"Prof. Dr. Kenji Yamamoto","institution":"Kyoto Institute of Technology","country_code":"JP","role":"speaker","notes":"Keynote speaker"},{"full_name":"Dr. Ayumi Sato","institution":"Kyoto Institute of Technology","country_code":"JP","role":"speaker"}]',
  p_co_units => '{11,12}');

select pg_temp.bulk_act(110, 'Student Exchange Informatika di NTUST Semester Genap 2026', 11, 2, 'outbound', '2026-02-16', '2026-06-19', 'offline',
  'NTUST Taipei Campus', 'TW', 103, '{4,17}', 'Tiga mahasiswa Informatika menempuh satu semester di NTUST dengan mata kuliah Deep Learning, Distributed Systems, dan Mandarin dasar; kredit diakui melalui skema transfer kredit.',
  pg_temp.wib('2026-07-02'), 'approved', pg_temp.wib('2026-07-10', '14:00'));
select pg_temp.bulk_pset(110, '{B11225012,B11235104,B11225120}', '{}', '{}');

select pg_temp.bulk_act(111, 'Inbound Credit Transfer NTUST di Prodi Informatika 2026', 11, 33, 'inbound', '2026-02-09', '2026-06-12', 'offline',
  'Kampus PCU Siwalankerto', 'ID', 103, '{4,17}', 'Mahasiswa NTUST mengambil 18 SKS mata kuliah Informatika PCU (Pengembangan Aplikasi Mobile, Interaksi Manusia dan Komputer) yang dikonversi ke kredit di NTUST.',
  pg_temp.wib('2026-06-24'), 'approved', pg_temp.wib('2026-07-03', '14:00'));
select pg_temp.bulk_pset(111, '{}', '{X02260512}', '{PG712740}');

select pg_temp.bulk_act(112, 'Riset Bersama Digital Twin Lini Produksi dengan UTM', 10, 4, 'inbound', '2026-03-09', '2026-05-29', 'hybrid',
  'Laboratorium Sistem Produksi Gedung P PCU', 'ID', 107, '{9,12}', 'Pengembangan purwarupa digital twin lini perakitan skala laboratorium untuk simulasi penjadwalan dan pengurangan limbah produksi, dengan pertemuan daring mingguan dan kunjungan peneliti UTM.',
  pg_temp.wib('2026-07-08'), null, null,
  p_ext => '[{"full_name":"Dr. Mohd Faizal bin Ismail","institution":"Universiti Teknologi Malaysia","country_code":"MY","role":"researcher","notes":"Faculty of Mechanical Engineering"}]');

select pg_temp.bulk_act(113, 'Academic Exchange Teknik Industri Universiti Teknologi Malaysia 2026', 10, 28, 'inbound', '2026-03-02', '2026-05-22', 'offline',
  'Laboratorium Optimasi dan Rekayasa Industri Gedung P PCU', 'ID', 107, '{4,9}', 'Mahasiswa UTM mengikuti perkuliahan Riset Operasi dan Ergonomi Industri serta terlibat dalam proyek optimasi tata letak gudang mitra industri FTI.',
  pg_temp.wib('2026-06-04'), 'approved', pg_temp.wib('2026-06-12', '14:00'));
select pg_temp.bulk_pset(113, '{}', '{X02260518}', '{}');

select pg_temp.bulk_act(114, 'Pelatihan dan Sertifikasi IoT Developer bersama Nanyang Polytechnic', 11, 44, 'inbound', '2026-04-20', '2026-04-24', 'offline',
  'Laboratorium Internet of Things Gedung P PCU', 'ID', 113, '{4,8}', 'Pelatihan lima hari pemrograman mikrokontroler, protokol MQTT, dan dashboard IoT yang ditutup dengan ujian sertifikasi IoT Developer berstandar Nanyang Polytechnic untuk 30 mahasiswa.',
  pg_temp.wib('2026-05-06'), null, null,
  p_ext => '[{"full_name":"Mr. Tan Jun Hao","institution":"Nanyang Polytechnic","country_code":"SG","role":"visiting_lecturer","notes":"Certified IoT trainer"}]');

select pg_temp.bulk_act(115, 'Kunjungan Akademik FTI ke Osaka University', 10, 27, 'outbound', '2026-04-13', '2026-04-16', 'offline',
  'Osaka University Suita Campus', 'JP', 905, '{9,17}', 'Delegasi pimpinan FTI meninjau laboratorium material dan rekayasa produksi Osaka University untuk menindaklanjuti perpanjangan kerja sama serta merancang skema riset bersama periode 2026-2031.',
  pg_temp.wib('2026-04-27'), null, null,
  p_ext => '[{"full_name":"Prof. Dr. Takeshi Nakamura","institution":"Osaka University","country_code":"JP","role":"other","notes":"Host, Graduate School of Engineering"}]');

select pg_temp.bulk_act(116, 'Pengabdian Masyarakat Smart Village Berbasis IoT bersama ITB', 10, 40, 'outbound', '2026-07-06', '2026-07-10', 'offline',
  'Desa Ketapanrame, Trawas, Mojokerto', 'ID', 110, '{1,9,11}', 'Pemasangan sistem pemantauan debit air dan panel informasi desa berbasis IoT bersama tim ITB, disertai pelatihan perawatan perangkat bagi karang taruna desa.',
  pg_temp.wib('2026-07-20'), null, null, p_co_units => '{11}');

select pg_temp.bulk_act(117, 'June Program Robotika dan Otomasi Industri di Nanyang Polytechnic', 10, 23, 'outbound', '2026-06-22', '2026-07-10', 'offline',
  'Nanyang Polytechnic, Ang Mo Kio Campus', 'SG', 113, '{4,9}', 'Program tiga minggu tentang pemrograman robot kolaboratif, machine vision, dan integrasi PLC di Smart Manufacturing Centre Nanyang Polytechnic, ditutup presentasi proyek otomasi.',
  pg_temp.wib('2026-07-22'), 'approved', pg_temp.wib('2026-07-30', '14:00'));
select pg_temp.bulk_pset(117, '{B11255177,B11235194,B12245398,B12235432}', '{}', '{PG707752}');

-- AY 2026/2027 Ganjil
select pg_temp.bulk_act(118, 'Inbound Short Program Industrial Engineering Chulalongkorn University 2026', 10, 23, 'inbound', '2026-08-03', '2026-08-28', 'offline',
  'Laboratorium Teknik Industri Gedung P PCU', 'ID', 901, '{4,9,17}', 'Mahasiswa Chulalongkorn University mengikuti program empat minggu tentang lean manufacturing dan rantai pasok UMKM Jawa Timur, termasuk studi lapangan di dua pabrik mitra.',
  pg_temp.wib('2026-09-07'), 'approved', pg_temp.wib('2026-09-15', '14:00'));
select pg_temp.bulk_pset(118, '{}', '{X02260528}', '{}');

select pg_temp.bulk_act(119, 'Guest Lecture Industry 4.0 Readiness dari Chulalongkorn University', 10, 7, 'inbound', '2026-08-19', '2026-08-19', 'online',
  'Zoom Meeting', null, 901, '{8,9}', 'Kuliah tamu daring mengenai pengukuran kesiapan Industri 4.0 pada industri manufaktur Thailand dan pelajaran yang relevan bagi industri Indonesia, diikuti 150 mahasiswa FTI.',
  pg_temp.wib('2026-08-26'), null, null,
  p_ext => '[{"full_name":"Assoc. Prof. Dr. Somchai Rattanakul","institution":"Chulalongkorn University","country_code":"TH","role":"speaker","notes":"Department of Industrial Engineering"}]');

select pg_temp.bulk_act(120, 'Studi Ekskursi Smart Manufacturing ke Kyoto Institute of Technology', 10, 24, 'outbound', '2026-09-14', '2026-09-19', 'offline',
  'Kyoto Institute of Technology, Matsugasaki Campus', 'JP', 115, '{4,9}', 'Studi ekskursi enam hari ke laboratorium mekatronika KIT dan dua pabrik otomotif di Kansai untuk mengamati penerapan sistem produksi cerdas dan otomasi.',
  pg_temp.daysago(6), 'pending', null);
select pg_temp.bulk_pset(120, '{B12245446,B12225474,B12245502,B11255215,B11245217}', '{}', '{PG703063}');

select pg_temp.bulk_act(121, 'Magang AI Engineering di NTUST Artificial Intelligence Center', 11, 21, 'outbound', '2026-07-20', '2026-09-11', 'offline',
  'NTUST Taipei Campus, Taiwan Building Technology Center', 'TW', 103, '{8,9}', 'Dua mahasiswa Informatika magang delapan minggu di pusat AI NTUST, mengembangkan pipeline pelabelan data dan model deteksi objek untuk inspeksi konstruksi.',
  pg_temp.daysago(12), 'pending', null);
select pg_temp.bulk_pset(121, '{B11235229,B11225257}', '{}', '{}');

select pg_temp.bulk_act(122, 'Short Program Cyber-Physical Systems di Universiti Teknologi Malaysia', 10, 23, 'outbound', '2026-08-10', '2026-08-28', 'offline',
  'UTM Johor Bahru Campus', 'MY', 107, '{4,9}', 'Program tiga minggu tentang sistem siber-fisik, edge computing, dan keamanan jaringan industri di UTM, dengan proyek kelompok pemantauan mesin berbasis sensor getaran.',
  pg_temp.daysago(15), 'revision_requested', pg_temp.daysago(9, '14:00'),
  p_mnote => 'Mohon unggah transkrip nilai UTM untuk B11255316 yang belum ada di berkas mobility, dan sesuaikan tanggal selesai dengan sertifikat (27 Agustus 2026).');
select pg_temp.bulk_pset(122, '{B11255280,B11255316,B11235318,B12245339}', '{}', '{PG378607}');

select pg_temp.bulk_act(123, 'Publikasi Bersama Material Cerdas untuk Manufaktur Aditif dengan Osaka University', 10, 37, 'outbound', '2026-08-03', '2026-09-18', 'online',
  'Microsoft Teams', null, 905, '{9,12}', 'Penulisan dan pengiriman artikel bersama ke jurnal internasional bereputasi tentang karakterisasi filamen komposit daur ulang untuk manufaktur aditif, melalui rapat daring dua mingguan.',
  pg_temp.wib('2026-09-24'), null, null,
  p_ext => '[{"full_name":"Assoc. Prof. Dr. Yuki Kobayashi","institution":"Osaka University","country_code":"JP","role":"researcher","notes":"Co-author"}]');

-- Drafts
select pg_temp.bulk_act(124, 'Kuliah Tamu Large Language Models untuk Rekayasa Perangkat Lunak dari NTUST', 11, 15, 'inbound', '2026-11-09', '2026-11-10', 'offline',
  'Auditorium Gedung P PCU', 'ID', 103, '{4,9}', 'Rencana kuliah tamu tentang pemanfaatan large language model untuk pembangkitan kode dan pengujian otomatis, disertai lokakarya praktik bagi mahasiswa Informatika.',
  null, null, null, p_files => '{ia}',
  p_ext => '[{"full_name":"Prof. Dr. Chen Yu-Ting","institution":"National Taiwan University of Science and Technology","country_code":"TW","role":"visiting_lecturer"}]');

select pg_temp.bulk_act(125, 'Penyusunan Joint Curriculum Industrial Engineering bersama Chulalongkorn University', 10, 32, 'inbound', '2026-12-07', '2026-12-09', 'hybrid',
  'Ruang Rapat Dekanat FTI Gedung P PCU', 'ID', 901, '{4,17}', 'Rencana lokakarya penyusunan kurikulum bersama program Industrial Engineering untuk skema double degree, mencakup pemetaan mata kuliah dan mekanisme penjaminan mutu.',
  null, null, null,
  p_ext => '[{"full_name":"Asst. Prof. Dr. Napat Wongsuwan","institution":"Chulalongkorn University","country_code":"TH","role":"staff_visitor"}]');

select pg_temp.bulk_verify(101, 125);
