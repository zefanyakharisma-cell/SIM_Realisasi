-- 04_bulk_2: Teknik Elektro & FTI (power systems, renewables, embedded, robotics, telecom, EV). RL-2026-0126..0150. Students: the 04_bulk_2 slice of 04_bulk_0_registry.sql.
\ir bulk/_helpers.inc

-- AY 2025/2026 Ganjil
select pg_temp.bulk_act(132, 'Riset Bersama Prakiraan Beban Listrik Berbasis Machine Learning dengan Osaka University', 10, 4, 'outbound', '2025-08-18', '2025-10-31', 'online',
  'Microsoft Teams', null, 904, '{7,9}', 'Riset daring bersama Osaka University untuk membangun model prakiraan beban listrik jangka pendek pada jaringan distribusi kampus. Data smart meter PCU dibandingkan dengan dataset kampus Suita; luaran berupa draf artikel jurnal dan model LSTM terbuka.',
  pg_temp.wib('2025-11-07'), null, null,
  p_ext => '[{"full_name":"Assoc. Prof. Hiroshi Tanaka","institution":"Osaka University","country_code":"JP","role":"researcher"}]');

select pg_temp.bulk_act(126, 'Inbound Exchange Teknik Elektro Hochschule Bremen 2025', 12, 2, 'inbound', '2025-09-01', '2025-12-19', 'offline',
  'Kampus PCU Siwalankerto', 'ID', 104, '{4,17}', 'Mahasiswa Hochschule Bremen mengikuti satu semester perkuliahan di Prodi Teknik Elektro PCU, termasuk mata kuliah Sistem Tenaga Listrik dan Energi Terbarukan serta proyek laboratorium konversi energi. Kredit ditransfer ke program Elektrotechnik di Bremen.',
  pg_temp.wib('2025-12-23'), 'approved', pg_temp.wib('2026-01-06', '14:00'));
select pg_temp.bulk_pset(126, '{}', '{X01250542}', '{}');

select pg_temp.bulk_act(127, 'Kuliah Tamu Proteksi Sistem Tenaga dari Kyoto Institute of Technology', 12, 15, 'inbound', '2025-09-17', '2025-09-17', 'hybrid',
  'Gedung P PCU', 'ID', 115, '{4,7}', 'Kuliah tamu mengenai koordinasi relai proteksi dan deteksi gangguan pada jaringan distribusi dengan penetrasi pembangkit tersebar tinggi. Diikuti mahasiswa mata kuliah Proteksi Sistem Tenaga secara luring dan daring.',
  pg_temp.wib('2025-09-24'), null, null,
  p_ext => '[{"full_name":"Prof. Dr. Hiroshi Takahashi","institution":"Kyoto Institute of Technology","country_code":"JP","role":"visiting_lecturer"}]');

select pg_temp.bulk_act(128, 'Riset Bersama Optimasi PLTS Atap Kampus dengan UTM', 10, 4, 'outbound', '2025-10-13', '2025-10-17', 'offline',
  'Universiti Teknologi Malaysia Johor Bahru', 'MY', 107, '{7,13}', 'Dosen FTI melakukan pengukuran dan pemodelan kinerja PLTS atap di kampus UTM sebagai pembanding instalasi PCU. Tim menyusun metodologi optimasi sudut kemiringan dan jadwal pembersihan panel untuk iklim tropis lembap.',
  pg_temp.wib('2025-10-28'), null, null,
  p_ext => '[{"full_name":"Assoc. Prof. Dr. Mohd Hafiz Abdullah","institution":"Universiti Teknologi Malaysia","country_code":"MY","role":"researcher"}]');

select pg_temp.bulk_act(129, 'Short Program Robotika Otonom di Kyoto Institute of Technology', 12, 23, 'outbound', '2025-11-03', '2025-11-14', 'offline',
  'Kyoto Institute of Technology Matsugasaki Campus', 'JP', 101, '{4,9}', 'Program singkat dua minggu tentang navigasi robot bergerak otonom, sensor LiDAR, dan ROS 2. Mahasiswa Teknik Elektro menyelesaikan proyek kelompok robot pengantar barang dan mempresentasikannya di laboratorium mitra.',
  pg_temp.wib('2025-11-21'), 'approved', pg_temp.wib('2025-12-01', '14:00'));
select pg_temp.bulk_pset(129, '{B12245534,B12225547,B12235574}', '{}', '{PG204517}');

select pg_temp.bulk_act(130, 'Seminar Teknologi Baterai Kendaraan Listrik bersama ITB', 10, 10, 'outbound', '2025-11-26', '2025-11-26', 'offline',
  'Institut Teknologi Bandung Kampus Ganesha', 'ID', 110, '{7,9,11}', 'Seminar bersama tentang sistem manajemen baterai (BMS), keamanan sel lithium-ion, dan infrastruktur pengisian kendaraan listrik di Indonesia. Dosen FTI menjadi pembicara sesi estimasi state-of-charge.',
  pg_temp.wib('2025-12-03'), null, null,
  p_ext => '[{"full_name":"Dr. Ir. Agus Purwadi","institution":"Institut Teknologi Bandung","country_code":"ID","role":"speaker"}]');

select pg_temp.bulk_act(131, 'Kunjungan Akademik Laboratorium Energi Osaka University', 10, 27, 'outbound', '2025-12-08', '2025-12-10', 'offline',
  'Osaka University Suita Campus', 'JP', 904, '{7,17}', 'Delegasi FTI mengunjungi laboratorium sistem energi dan elektronika daya Osaka University untuk menjajaki topik riset lanjutan dan rencana perpanjangan kerja sama. Hasilnya berupa daftar topik riset bersama 2026.',
  pg_temp.wib('2025-12-18'), null, null,
  p_ext => '[{"full_name":"Prof. Dr. Kenji Yamamoto","institution":"Osaka University","country_code":"JP","role":"staff_visitor"}]');

select pg_temp.bulk_act(133, 'Credit Transfer Inbound Teknik Elektro Kyoto Institute of Technology 2025', 12, 33, 'inbound', '2025-10-01', '2026-01-23', 'offline',
  'Laboratorium Sistem Tertanam PCU', 'ID', 101, '{4}', 'Mahasiswa Kyoto Institute of Technology mengambil mata kuliah Sistem Tertanam, Mikrokontroler, dan Internet of Things di PCU dengan pengakuan kredit di institusi asal. Proyek akhir berupa node sensor kualitas udara berdaya rendah.',
  pg_temp.wib('2026-02-25'), 'approved', pg_temp.wib('2026-03-05', '14:00'));
select pg_temp.bulk_pset(133, '{}', '{X01250545}', '{}');

-- AY 2025/2026 Genap
select pg_temp.bulk_act(134, 'Student Exchange Semester Genap Teknik Elektro di Hochschule Bremen', 12, 2, 'outbound', '2026-03-02', '2026-07-17', 'offline',
  'Hochschule Bremen Campus Neustadtswall', 'DE', 104, '{4,7,17}', 'Tiga mahasiswa Teknik Elektro mengikuti satu semester di program Elektrotechnik Hochschule Bremen dengan fokus energi terbarukan dan elektronika daya. Mata kuliah yang diambil dikonversi ke kurikulum PCU.',
  pg_temp.wib('2026-07-24'), 'approved', pg_temp.wib('2026-08-05', '14:00'));
select pg_temp.bulk_pset(134, '{B12235602,B12235626,B12245651}', '{}', '{}');

select pg_temp.bulk_act(135, 'Inbound Exchange Hochschule Bremen Semester Genap 2026', 12, 2, 'inbound', '2026-02-16', '2026-06-26', 'offline',
  'Kampus PCU Siwalankerto', 'ID', 104, '{4,17}', 'Mahasiswa Hochschule Bremen menjalani semester pertukaran di Teknik Elektro PCU dan bergabung dalam proyek mikrogrid tenaga surya laboratorium. Kegiatan juga mencakup kelas bahasa dan budaya Indonesia.',
  pg_temp.wib('2026-07-02'), 'approved', pg_temp.wib('2026-07-10', '14:00'));
select pg_temp.bulk_pset(135, '{}', '{X02260535}', '{}');

select pg_temp.bulk_act(136, 'Kuliah Tamu Keamanan Siber Smart Grid dari Hochschule Bremen', 12, 15, 'inbound', '2026-03-11', '2026-03-11', 'offline',
  'Gedung P PCU', 'ID', 104, '{4,9}', 'Kuliah tamu tentang ancaman siber pada sistem SCADA dan advanced metering infrastructure, termasuk standar IEC 62351. Mahasiswa melakukan studi kasus serangan pada gardu induk digital.',
  pg_temp.wib('2026-03-17'), null, null,
  p_ext => '[{"full_name":"Prof. Dr.-Ing. Katrin Hoffmann","institution":"Hochschule Bremen","country_code":"DE","role":"visiting_lecturer"}]');

select pg_temp.bulk_act(141, 'Pengabdian Masyarakat PLTS Off-Grid Desa bersama ITB', 10, 40, 'outbound', '2026-02-23', '2026-02-27', 'offline',
  'Desa Sidomulyo, Kabupaten Pacitan', 'ID', 110, '{1,7}', 'Dosen dan mahasiswa FTI bersama ITB memasang PLTS off-grid 3 kWp untuk balai desa dan pompa air, serta melatih warga melakukan perawatan dasar panel dan baterai. Luaran berupa sistem terpasang dan modul perawatan.',
  pg_temp.wib('2026-03-06'), null, null,
  p_ext => '[{"full_name":"Dr. Nanang Hariyanto","institution":"Institut Teknologi Bandung","country_code":"ID","role":"other","notes":"Koordinator lapangan tim ITB"}]');

select pg_temp.bulk_act(142, 'Joint Curriculum Telekomunikasi 5G dengan Kyoto Institute of Technology', 12, 32, 'inbound', '2026-04-13', '2026-04-15', 'hybrid',
  'Gedung P PCU', 'ID', 115, '{4,9}', 'Lokakarya penyusunan mata kuliah bersama Jaringan 5G dan Antena Gelombang Milimeter. Kedua prodi menyepakati capaian pembelajaran, modul praktikum, dan skema kuliah bersama mulai Ganjil 2026/2027.',
  pg_temp.wib('2026-04-21'), null, null,
  p_ext => '[{"full_name":"Assoc. Prof. Dr. Takeshi Nakamura","institution":"Kyoto Institute of Technology","country_code":"JP","role":"visiting_lecturer"}]');

select pg_temp.bulk_act(137, 'Riset Bersama Inverter Mikrogrid Berbasis Sistem Tertanam dengan Osaka University', 10, 4, 'outbound', '2026-04-20', '2026-04-24', 'offline',
  'Osaka University Suita Campus', 'JP', 905, '{7,9}', 'Riset lanjutan pertama di bawah perjanjian baru dengan Osaka University: pengembangan kontrol inverter grid-forming berbasis mikrokontroler DSP untuk mikrogrid kampus. Pengujian hardware-in-the-loop dilakukan di laboratorium mitra.',
  pg_temp.wib('2026-05-04'), null, null,
  p_ext => '[{"full_name":"Prof. Dr. Kenji Yamamoto","institution":"Osaka University","country_code":"JP","role":"researcher"}]');

select pg_temp.bulk_act(139, 'Magang Riset Laboratorium Robotika Kyoto Institute of Technology', 12, 21, 'outbound', '2026-06-01', '2026-07-24', 'offline',
  'Kyoto Institute of Technology Matsugasaki Campus', 'JP', 115, '{4,8,9}', 'Magang riset delapan minggu di laboratorium robotika KIT untuk pengembangan lengan robot kolaboratif dengan kendali berbasis visi komputer. Mahasiswa Teknik Elektro dan Informatika menyusun laporan teknis dan demo akhir.',
  pg_temp.wib('2026-07-29'), 'approved', pg_temp.wib('2026-08-07', '14:00'));
select pg_temp.bulk_pset(139, '{B12235660,B12235668,B11245948}', '{}', '{}');

select pg_temp.bulk_act(140, 'Inbound Short Program Energi Terbarukan UTM 2026', 10, 23, 'inbound', '2026-07-06', '2026-07-17', 'offline',
  'Laboratorium Konversi Energi PCU', 'ID', 107, '{4,7}', 'Program singkat dua minggu bagi mahasiswa UTM tentang sistem PLTS, turbin angin skala kecil, dan audit energi bangunan. Peserta melakukan kunjungan lapangan ke instalasi PLTS atap di Surabaya.',
  pg_temp.wib('2026-07-22'), 'approved', pg_temp.wib('2026-07-31', '14:00'));
select pg_temp.bulk_pset(140, '{}', '{X02260560}', '{}');

select pg_temp.bulk_act(143, 'Inbound Exchange Osaka University Semester Genap 2026', 10, 2, 'inbound', '2026-02-09', '2026-07-24', 'offline',
  'Kampus PCU Siwalankerto', 'ID', 905, '{4,17}', 'Mahasiswa Osaka University mengikuti satu semester di FTI PCU dengan mata kuliah Elektronika Daya dan Kendaraan Listrik serta proyek konversi sepeda motor listrik. Pengakuan kredit dilakukan oleh Osaka University.',
  pg_temp.wib('2026-08-04'), 'approved', pg_temp.wib('2026-08-12', '14:00'));
select pg_temp.bulk_pset(143, '{}', '{X01260551}', '{}');

-- AY 2026/2027 Ganjil
select pg_temp.bulk_act(147, 'Magang Industri Kendaraan Listrik melalui Hochschule Bremen', 12, 21, 'outbound', '2026-07-06', '2026-08-28', 'offline',
  'Hochschule Bremen Campus Neustadtswall', 'DE', 104, '{8,9,11}', 'Magang delapan minggu di laboratorium e-mobility Hochschule Bremen dan mitra industrinya, mencakup pengujian motor traksi dan pengisi daya DC cepat. Mahasiswa menyusun laporan magang dan poster hasil pengujian.',
  pg_temp.daysago(15), 'revision_requested', pg_temp.daysago(8, '14:00'),
  p_mnote => 'Sertifikat magang dari Hochschule Bremen dan transkrip konversi SKS belum diunggah untuk kedua mahasiswa. Mohon lengkapi berkas mobilitas sebelum diajukan ulang.');
select pg_temp.bulk_pset(147, '{B12255778,B12235798}', '{}', '{}');

select pg_temp.bulk_act(145, 'Summer Program Robotics and Automation di Chulalongkorn University', 10, 23, 'outbound', '2026-08-03', '2026-08-14', 'offline',
  'Chulalongkorn University Faculty of Engineering, Bangkok', 'TH', 901, '{4,9}', 'Program musim panas dua minggu tentang otomasi industri, PLC, dan robot industri. Mahasiswa FTI dari Teknik Elektro dan Informatika mengerjakan proyek sel manufaktur otomatis bersama mahasiswa Chulalongkorn.',
  pg_temp.daysago(6), 'pending', null);
select pg_temp.bulk_pset(145, '{B12255674,B12235707,B11245853,B11225880,B11225911}', '{}', '{PG707752}');

select pg_temp.bulk_act(138, 'Pelatihan PLC dan SCADA Daring bersama UTM', 10, 69, 'outbound', '2026-08-17', '2026-08-19', 'online',
  'Zoom Meeting', null, 107, '{4,9}', 'Pelatihan daring tiga hari oleh instruktur UTM tentang pemrograman PLC IEC 61131-3 dan perancangan HMI SCADA untuk dosen dan laboran FTI. Peserta menyelesaikan studi kasus kontrol stasiun pompa.',
  pg_temp.wib('2026-08-25'), null, null,
  p_ext => '[{"full_name":"Dr. Nurul Aini Ismail","institution":"Universiti Teknologi Malaysia","country_code":"MY","role":"speaker"}]');

select pg_temp.bulk_act(144, 'Kunjungan Akademik Fakultas Teknik Chulalongkorn University', 10, 27, 'outbound', '2026-08-24', '2026-08-26', 'offline',
  'Chulalongkorn University Faculty of Engineering, Bangkok', 'TH', 901, '{4,17}', 'Kunjungan pimpinan FTI ke Chulalongkorn University untuk menindaklanjuti MoU baru: peninjauan laboratorium smart grid dan telekomunikasi serta penyusunan rencana pertukaran mahasiswa dan dosen 2027.',
  pg_temp.wib('2026-09-02'), null, null,
  p_ext => '[{"full_name":"Assoc. Prof. Dr. Somchai Wongsiri","institution":"Chulalongkorn University","country_code":"TH","role":"staff_visitor"}]');

select pg_temp.bulk_act(146, 'Studi Ekskursi Teknologi Telekomunikasi ke Kyoto Institute of Technology', 12, 24, 'outbound', '2026-09-07', '2026-09-11', 'offline',
  'Kyoto Institute of Technology Matsugasaki Campus', 'JP', 115, '{4,9}', 'Studi ekskursi lima hari ke laboratorium komunikasi nirkabel KIT dan operator telekomunikasi di Kansai. Mahasiswa mengamati pengujian antena 5G dan menyusun laporan perbandingan infrastruktur jaringan.',
  pg_temp.daysago(12), 'pending', null);
select pg_temp.bulk_pset(146, '{B12225719,B12255726,B12255745}', '{}', '{PG413450}');

select pg_temp.bulk_act(148, 'Seminar Internasional Transisi Energi Terbarukan bersama UTM', 10, 10, 'inbound', '2026-09-16', '2026-09-16', 'hybrid',
  'Auditorium Gedung W PCU', 'ID', 107, '{7,13,17}', 'Seminar internasional tentang integrasi energi terbarukan ke jaringan listrik Indonesia dan Malaysia, penyimpanan energi, dan kebijakan net-zero. Menghadirkan pembicara UTM dan dosen FTI dengan lebih dari 200 peserta.',
  pg_temp.wib('2026-09-22'), null, null,
  p_ext => '[{"full_name":"Prof. Ir. Dr. Zainal Salam","institution":"Universiti Teknologi Malaysia","country_code":"MY","role":"speaker"}]');

-- Drafts
select pg_temp.bulk_act(149, 'Workshop Kompetisi Robot Sepak Bola bersama Chulalongkorn University', 10, 35, 'inbound', '2026-11-09', '2026-11-11', 'offline',
  'Laboratorium Robotika PCU', 'ID', 901, '{4,9}', 'Rencana lokakarya bersama persiapan kompetisi robot sepak bola beroda, meliputi desain mekanik, kendali motor, dan strategi multi-agen. Tim Chulalongkorn akan berbagi pengalaman kompetisi RoboCup.',
  null, null, null, p_files => '{ia}');

select pg_temp.bulk_act(150, 'Credit Transfer Teknik Elektro ke Hochschule Bremen Ganjil 2026/2027', 12, 33, 'outbound', '2026-10-05', '2027-01-29', 'offline',
  'Hochschule Bremen Campus Neustadtswall', 'DE', 104, '{4,7}', 'Rencana program transfer kredit satu semester di Hochschule Bremen untuk mata kuliah Sistem Tenaga Lanjut dan Penyimpanan Energi. Draf menunggu konfirmasi letter of acceptance dari mitra.',
  null, null, null, p_files => '{}');
select pg_temp.bulk_pset(150, '{B12245823,B12255583}', '{}', '{}');

select pg_temp.bulk_verify(126, 150);
