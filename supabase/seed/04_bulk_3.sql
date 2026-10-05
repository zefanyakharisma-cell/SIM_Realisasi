-- 04_bulk_3: FBE (akuntansi, keuangan, bisnis internasional, kewirausahaan, pajak, sustainability reporting, hospitality). RL-2026-0151..0175. Students: the 04_bulk_3 slice of 04_bulk_0_registry.sql.
\ir bulk/_helpers.inc

-- AY 2025/2026 Ganjil
select pg_temp.bulk_act(151, 'Riset Bersama Sustainability Reporting UMKM Jawa Timur dengan Universitas Airlangga', 20, 4, 'outbound',
  '2025-09-01', '2025-12-15', 'offline', 'Fakultas Ekonomi dan Bisnis Universitas Airlangga, Surabaya', 'ID', 112, '{12,8,17}',
  'Penelitian bersama untuk menyusun model pelaporan keberlanjutan sederhana berbasis standar GRI bagi UMKM manufaktur di Jawa Timur. Luaran berupa instrumen pengungkapan ESG dan draf artikel jurnal bersama.',
  pg_temp.wib('2025-12-19'), null, null,
  p_ext => '[{"full_name":"Dr. Rizky Aditya Wibisono, S.E., M.Ak.","institution":"Universitas Airlangga","country_code":"ID","role":"researcher","notes":"Peneliti utama dari Departemen Akuntansi FEB Unair"}]');

select pg_temp.bulk_act(152, 'Student Exchange Akuntansi Hanyang School of Business Fall 2025', 20, 2, 'outbound',
  '2025-09-01', '2025-12-19', 'offline', 'Hanyang University Seoul Campus', 'KR', 102, '{4,17}',
  'Tiga mahasiswa Akuntansi mengikuti satu semester perkuliahan di Hanyang School of Business, termasuk mata kuliah International Financial Reporting dan Managerial Accounting. Nilai dikonversi ke kurikulum Prodi Akuntansi PCU.',
  pg_temp.wib('2026-01-06'), 'approved', pg_temp.wib('2026-01-15', '14:00'));
select pg_temp.bulk_pset(152, '{D32246262,D32246272,D32236314}', '{}', '{}');

select pg_temp.bulk_act(153, 'Kuliah Tamu International Taxation and Transfer Pricing dari Tunghai University', 20, 15, 'inbound',
  '2025-10-08', '2025-10-08', 'offline', 'Auditorium Gedung W PCU', 'ID', 114, '{4,8,17}',
  'Kuliah tamu bagi mahasiswa Akuntansi dan Manajemen tentang perpajakan internasional, BEPS, dan dokumentasi transfer pricing pada grup usaha Taiwan–Indonesia. Diikuti sekitar 180 mahasiswa.',
  pg_temp.wib('2025-10-20'), null, null,
  p_ext => '[{"full_name":"Assoc. Prof. Chen Wei-Ting","institution":"Tunghai University","country_code":"TW","role":"speaker","notes":"Department of Accounting, College of Management"}]');

select pg_temp.bulk_act(154, 'Short Program Hospitality & Tourism Management di KMUTT Bangkok', 20, 23, 'outbound',
  '2025-11-10', '2025-11-21', 'offline', 'KMUTT Bangmod Campus, Bangkok', 'TH', 108, '{8,4}',
  'Program singkat dua minggu tentang manajemen hospitality, revenue management hotel, dan pariwisata berkelanjutan di Thailand, dilengkapi kunjungan industri ke hotel dan operator wisata di Bangkok.',
  pg_temp.wib('2025-12-02'), 'approved', pg_temp.wib('2025-12-10', '14:00'));
select pg_temp.bulk_pset(154, '{D31246061,D31236090,D31236107,D31226115}', '{}', '{PG214411}');

select pg_temp.bulk_act(155, 'Online Course Sustainable Finance and ESG Investing bersama Fontys', 20, 79, 'outbound',
  '2025-10-01', '2025-11-26', 'online', 'Microsoft Teams', null, 105, '{13,8,4}',
  'Kursus daring delapan pertemuan mengenai keuangan berkelanjutan, analisis skor ESG, dan green bonds yang diampu dosen Fontys International Business School. Peserta menyusun analisis portofolio ESG sebagai tugas akhir.',
  pg_temp.wib('2025-12-05'), null, null,
  p_ext => '[{"full_name":"Dr. Maarten de Vries","institution":"Fontys University of Applied Sciences","country_code":"NL","role":"visiting_lecturer"}]');

select pg_temp.bulk_act(156, 'International Conference on Accounting and Sustainable Finance (ICASF) 2025', 20, 10, 'inbound',
  '2025-11-27', '2025-11-28', 'hybrid', 'Gedung P PCU', 'ID', 112, '{8,12,17}',
  'Konferensi internasional dua hari yang diselenggarakan FBE PCU bersama FEB Universitas Airlangga dengan 64 makalah tentang akuntansi keberlanjutan, tata kelola, dan keuangan hijau. Prosiding terbit dengan ISBN.',
  pg_temp.wib('2025-12-08'), null, null,
  p_co_units => '{21}',
  p_ext => '[{"full_name":"Prof. Dr. Dian Kartikasari, S.E., M.Si., Ak.","institution":"Universitas Airlangga","country_code":"ID","role":"speaker","notes":"Keynote speaker"},{"full_name":"Dr. Bagus Hendra Saputra, S.E., M.M.","institution":"Universitas Airlangga","country_code":"ID","role":"speaker"}]');

select pg_temp.bulk_act(157, 'Inbound Exchange International Business Fontys Fall 2025', 20, 2, 'inbound',
  '2025-09-01', '2026-01-16', 'offline', 'Kampus PCU Siwalankerto', 'ID', 105, '{4,17}',
  'Mahasiswa International Business dari Fontys mengikuti satu semester perkuliahan di FBE PCU, termasuk mata kuliah Asian Business Environment dan Bahasa Indonesia untuk Penutur Asing.',
  pg_temp.wib('2026-01-27'), 'approved', pg_temp.wib('2026-02-05', '14:00'));
select pg_temp.bulk_pset(157, '{}', '{X02250573}', '{}');

select pg_temp.bulk_act(158, 'Pendampingan Pembukuan Digital UMKM Kuliner Siwalankerto bersama Universitas Airlangga', 21, 40, 'outbound',
  '2026-01-05', '2026-01-23', 'offline', 'Balai RW Kelurahan Siwalankerto, Surabaya', 'ID', 112, '{1,8,10}',
  'Dosen dan mahasiswa Manajemen bersama tim FEB Unair mendampingi 25 pelaku UMKM kuliner menyusun pembukuan sederhana dengan aplikasi akuntansi gratis serta memisahkan keuangan usaha dan rumah tangga.',
  pg_temp.wib('2026-02-10'), null, null,
  p_ext => '[{"full_name":"Dr. Nurul Hidayati, S.E., M.Ak.","institution":"Universitas Airlangga","country_code":"ID","role":"other","notes":"Koordinator pengabdian masyarakat FEB Unair"}]');

-- AY 2025/2026 Genap
select pg_temp.bulk_act(159, 'Inbound Exchange Hanyang University Spring 2026 di Fakultas Bisnis & Ekonomi', 20, 2, 'inbound',
  '2026-02-02', '2026-06-12', 'offline', 'Kampus PCU Siwalankerto', 'ID', 102, '{4,17}',
  'Mahasiswa Hanyang University mengikuti semester genap di FBE PCU dengan fokus pada manajemen pemasaran dan kewirausahaan di pasar Asia Tenggara, termasuk proyek konsultasi untuk UMKM Surabaya.',
  pg_temp.wib('2026-06-22'), 'approved', pg_temp.wib('2026-06-30', '14:00'));
select pg_temp.bulk_pset(159, '{}', '{X01260567}', '{}');

select pg_temp.bulk_act(160, 'Kunjungan Akademik Fontys International Business School ke FBE PCU 2026', 20, 27, 'inbound',
  '2026-02-24', '2026-02-25', 'offline', 'Gedung P PCU', 'ID', 105, '{4,17}',
  'Delegasi Fontys membahas benchmarking kurikulum International Business, skema transfer kredit, dan rencana penambahan kuota pertukaran mahasiswa untuk tahun akademik 2026/2027.',
  pg_temp.wib('2026-03-06'), null, null,
  p_ext => '[{"full_name":"Drs. Jeroen Bakker","institution":"Fontys University of Applied Sciences","country_code":"NL","role":"staff_visitor","notes":"International Relations Coordinator"},{"full_name":"Dr. Sanne Willems","institution":"Fontys University of Applied Sciences","country_code":"NL","role":"staff_visitor","notes":"Programme Manager International Business"}]');

select pg_temp.bulk_act(161, 'Short Program Indonesian Business Culture untuk Mahasiswa KMUTT', 20, 23, 'inbound',
  '2026-03-02', '2026-03-13', 'offline', 'Gedung P PCU', 'ID', 108, '{4,8,17}',
  'Program singkat dua minggu bagi mahasiswa KMUTT tentang budaya bisnis Indonesia, praktik bisnis keluarga Tionghoa-Indonesia, dan kunjungan perusahaan di Surabaya dan Gresik.',
  pg_temp.wib('2026-03-20'), 'approved', pg_temp.wib('2026-03-27', '14:00'));
select pg_temp.bulk_pset(161, '{}', '{X01260578}', '{}');

select pg_temp.bulk_act(162, 'Magang Hospitality Management di Taichung melalui Tunghai University', 20, 21, 'outbound',
  '2026-02-02', '2026-04-30', 'offline', 'Tunghai University, Taichung', 'TW', 114, '{8,4}',
  'Magang tiga bulan di hotel mitra Tunghai University di Taichung pada divisi front office, F&B, dan revenue management. Mahasiswa menyusun laporan magang yang diakui sebagai mata kuliah Magang Industri.',
  pg_temp.wib('2026-05-12'), 'approved', pg_temp.wib('2026-05-20', '14:00'));
select pg_temp.bulk_pset(162, '{D31236131,D31246132,D31256152}', '{}', '{}');

select pg_temp.bulk_act(163, 'Publikasi Bersama Kepatuhan Pajak UMKM Indonesia–Korea dengan Hanyang University', 21, 37, 'outbound',
  '2026-02-16', '2026-05-29', 'online', 'Microsoft Teams', null, 102, '{8,16,17}',
  'Penulisan artikel bersama tentang faktor kepatuhan pajak UMKM di Indonesia dan Korea Selatan menggunakan data survei kedua negara. Naskah dikirim ke jurnal internasional bereputasi (Scopus Q2).',
  pg_temp.wib('2026-06-08'), null, null,
  p_ext => '[{"full_name":"Prof. Park Min-jae","institution":"Hanyang University","country_code":"KR","role":"researcher","notes":"Hanyang School of Business"}]');

select pg_temp.bulk_act(164, 'Workshop Lean Startup dan Business Model Validation bersama Fontys', 20, 35, 'inbound',
  '2026-03-18', '2026-03-19', 'hybrid', 'Gedung P PCU', 'ID', 105, '{8,9,4}',
  'Workshop kewirausahaan dua hari bagi mahasiswa inkubator bisnis PCU tentang validasi model bisnis, customer discovery, dan penyusunan pitch deck, difasilitasi pelatih dari Fontys Centre for Entrepreneurship.',
  pg_temp.wib('2026-03-30'), null, null,
  p_ext => '[{"full_name":"Lotte van den Berg, MBA","institution":"Fontys University of Applied Sciences","country_code":"NL","role":"speaker","notes":"Fontys Centre for Entrepreneurship"}]');

select pg_temp.bulk_act(165, 'Pengembangan Kurikulum Bersama Akuntansi Keberlanjutan dengan Tunghai University', 20, 11, 'outbound',
  '2026-04-13', '2026-04-17', 'offline', 'Tunghai University College of Management, Taichung', 'TW', 114, '{4,12,13}',
  'Tim dosen Akuntansi menyusun bersama silabus mata kuliah Sustainability Accounting and Assurance yang akan ditawarkan di kedua universitas, termasuk studi kasus perusahaan Taiwan dan Indonesia.',
  pg_temp.wib('2026-04-28'), null, null,
  p_ext => '[{"full_name":"Prof. Lin Hsiao-Mei","institution":"Tunghai University","country_code":"TW","role":"other","notes":"Ketua Departemen Akuntansi Tunghai University"}]');

select pg_temp.bulk_act(166, 'Studi Ekskursi Pasar Modal dan Fintech Seoul bersama Hanyang University', 20, 24, 'outbound',
  '2026-05-11', '2026-05-16', 'offline', 'Hanyang University Seoul Campus', 'KR', 102, '{8,9,4}',
  'Kunjungan studi mahasiswa Akuntansi ke Korea Exchange, perusahaan fintech di Seoul, dan kelas bersama di Hanyang School of Business tentang regulasi pasar modal dan pelaporan keuangan digital.',
  pg_temp.wib('2026-05-26'), 'approved', pg_temp.wib('2026-06-03', '14:00'));
select pg_temp.bulk_pset(166, '{D32246293,D32236331,D32256344,D32246361,D32256390,D32226417,D32246439}', '{}', '{PG217839}');

select pg_temp.bulk_act(167, 'Kuliah Tamu Forensic Accounting dan Pencegahan Fraud dari Universitas Airlangga', 20, 7, 'inbound',
  '2026-06-03', '2026-06-03', 'offline', 'Auditorium Gedung W PCU', 'ID', 112, '{16,4}',
  'Kuliah tamu tentang teknik akuntansi forensik, red flag kecurangan laporan keuangan, dan studi kasus investigasi fraud di BUMN bagi mahasiswa Akuntansi semester enam.',
  pg_temp.wib('2026-07-28'), null, null,
  p_ext => '[{"full_name":"Dr. Hendra Gunawan Sutrisno, S.E., M.Ak., CFrA","institution":"Universitas Airlangga","country_code":"ID","role":"speaker"}]');

-- AY 2026/2027 Ganjil
select pg_temp.bulk_act(168, 'Short Program Global Supply Chain & Logistics di KMUTT', 20, 23, 'outbound',
  '2026-08-03', '2026-08-14', 'offline', 'KMUTT Bangmod Campus, Bangkok', 'TH', 108, '{9,8,4}',
  'Program singkat dua minggu tentang manajemen rantai pasok global, logistik ASEAN, dan kunjungan ke Laem Chabang Port serta pusat distribusi di Bangkok bagi mahasiswa Manajemen.',
  pg_temp.wib('2026-08-24'), 'approved', pg_temp.wib('2026-09-01', '14:00'));
select pg_temp.bulk_pset(168, '{D31226028,D31246061,D31236090,D31236205,D31236228}', '{}', '{PG295222}');

select pg_temp.bulk_act(169, 'Cultural Exchange Bisnis Keluarga Taiwan bersama Tunghai University', 20, 29, 'outbound',
  '2026-08-24', '2026-09-04', 'offline', 'Tunghai University, Taichung', 'TW', 114, '{4,8,17}',
  'Pertukaran budaya dua minggu untuk mempelajari tata kelola dan suksesi bisnis keluarga Taiwan melalui kelas bersama, kunjungan perusahaan keluarga, dan homestay di Taichung.',
  pg_temp.daysago(12), 'pending', null);
select pg_temp.bulk_pset(169, '{D32246262,D32246272,D32236314,D32226456}', '{}', '{}');

select pg_temp.bulk_act(170, 'Academic Exchange Mahasiswa Tunghai University di FBE PCU 2026', 20, 28, 'inbound',
  '2026-08-17', '2026-09-18', 'offline', 'Gedung P PCU', 'ID', 114, '{4,17}',
  'Mahasiswa Tunghai University mengikuti perkuliahan Akuntansi Perpajakan dan Bisnis Internasional selama lima minggu serta proyek riset kecil tentang investasi Taiwan di Jawa Timur.',
  pg_temp.daysago(6), 'pending', null);
select pg_temp.bulk_pset(170, '{}', '{X02260587}', '{}');

select pg_temp.bulk_act(171, 'Immersion Program Accounting Analytics di Hanyang University', 21, 22, 'outbound',
  '2026-08-10', '2026-08-21', 'offline', 'Hanyang University Seoul Campus', 'KR', 102, '{4,9}',
  'Program imersi dua minggu tentang analitik data akuntansi, audit berbasis data, dan visualisasi keuangan dengan Python dan Power BI di Hanyang School of Business.',
  pg_temp.daysago(15), 'revision_requested', pg_temp.daysago(9),
  p_mnote => 'Transkrip nilai dua mahasiswa belum diunggah dan surat keterangan selesai program dari Hanyang University belum ditandatangani. Mohon lengkapi bundel mobilitas lalu ajukan ulang.');
select pg_temp.bulk_pset(171, '{D31226115,D31236131,D31246132,D31236259,D31226261}', '{}', '{}');

select pg_temp.bulk_act(172, 'Seminar Nasional Perpajakan Digital dan Coretax Administration System', 20, 10, 'inbound',
  '2026-09-09', '2026-09-09', 'hybrid', 'Auditorium Gedung W PCU', 'ID', 112, '{16,8,17}',
  'Seminar nasional tentang implementasi Coretax DJP, e-Faktur generasi baru, dan dampaknya bagi praktik akuntansi perusahaan, menghadirkan akademisi Unair dan praktisi konsultan pajak.',
  pg_temp.wib('2026-09-18'), null, null,
  p_co_units => '{21}',
  p_ext => '[{"full_name":"Dr. Agus Widodo Prasetyo, S.E., M.Ak., BKP","institution":"Universitas Airlangga","country_code":"ID","role":"speaker"}]');

select pg_temp.bulk_act(173, 'Faculty Exchange Dosen Corporate Finance FBE PCU di Fontys Venlo', 20, 31, 'outbound',
  '2026-09-14', '2026-09-25', 'offline', 'Fontys Venlo Campus', 'NL', 105, '{4,17}',
  'Dua dosen Keuangan mengajar modul Corporate Finance in Emerging Markets di Fontys Venlo dan menjajaki penelitian bersama tentang pembiayaan UKM di Indonesia dan Belanda.',
  pg_temp.wib('2026-09-29'), null, null,
  p_ext => '[{"full_name":"Dr. Thomas Janssen","institution":"Fontys University of Applied Sciences","country_code":"NL","role":"other","notes":"Host lecturer Fontys Venlo"}]');

-- Drafts
select pg_temp.bulk_act(174, 'Riset Bersama Integrated Reporting Perusahaan Keluarga dengan Tunghai University', 20, 4, 'outbound',
  '2026-11-02', '2027-01-29', 'hybrid', 'Tunghai University College of Management, Taichung', 'TW', 114, '{12,8,17}',
  'Rencana riset bersama tentang penerapan integrated reporting dan pengungkapan keberlanjutan pada perusahaan keluarga tercatat di Bursa Efek Indonesia dan Taiwan Stock Exchange.',
  null, null, null, p_files => '{ia}');

select pg_temp.bulk_act(175, 'Kuliah Tamu Hotel Revenue Management dari KMUTT', 20, 15, 'inbound',
  '2026-09-30', '2026-09-30', 'online', 'Zoom Meeting', null, 108, '{8,4}',
  'Kuliah tamu daring tentang strategi dynamic pricing, forecasting okupansi, dan distribusi kanal online pada industri perhotelan Thailand bagi mahasiswa Manajemen konsentrasi hospitality.',
  null, null, null,
  p_ext => '[{"full_name":"Asst. Prof. Dr. Siriporn Chaiyaporn","institution":"King Mongkut''s University of Technology Thonburi (KMUTT)","country_code":"TH","role":"speaker"}]');

select pg_temp.bulk_verify(151, 175);
