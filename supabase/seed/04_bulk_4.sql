-- 04_bulk_4: Prodi Manajemen — marketing, bisnis digital, rantai pasok, SDM, pemberdayaan UMKM, kolaborasi industri Telkom. RL-2026-0176..0200. Students: the 04_bulk_4 slice of 04_bulk_0_registry.sql.
\ir bulk/_helpers.inc

-- AY 2025/2026 Ganjil
select pg_temp.bulk_act(176, 'Kuliah Tamu Digital Marketing Strategy in the K-Wave Era dari Hanyang University', 21, 15, 'inbound', '2025-09-17', '2025-09-17', 'offline',
  'Auditorium Gedung W PCU', 'ID', 102, '{4,8}', 'Kuliah tamu bagi mahasiswa mata kuliah Pemasaran Digital tentang strategi pemasaran merek Korea memanfaatkan Hallyu dan influencer marketing. Diikuti sekitar 180 mahasiswa Manajemen dan ditutup dengan studi kasus kampanye K-beauty di Asia Tenggara.',
  pg_temp.wib('2025-09-24'), null, null,
  p_ext => '[{"full_name":"Prof. Kim Jae-won, Ph.D.","institution":"Hanyang University","country_code":"KR","role":"speaker","notes":"School of Business, Department of Marketing"}]');

select pg_temp.bulk_act(177, 'Student Exchange Hanyang Business School Fall Semester 2025', 21, 2, 'outbound', '2025-08-25', '2025-12-19', 'offline',
  'Hanyang University Seoul Campus', 'KR', 102, '{4,17}', 'Tiga mahasiswa Manajemen mengikuti satu semester perkuliahan di Hanyang Business School dengan fokus mata kuliah International Marketing dan Consumer Behavior. Nilai dikonversi ke kurikulum Prodi Manajemen sebagai mata kuliah pilihan internasional.',
  pg_temp.wib('2026-01-07'), 'approved', pg_temp.wib('2026-01-15', '14:00'));
select pg_temp.bulk_pset(177, '{D31236477,D31236534,D31246501}', '{}', '{}');

select pg_temp.bulk_act(178, 'Inbound Exchange Hanyang University di Prodi Manajemen PCU Semester Ganjil 2025', 21, 2, 'inbound', '2025-08-18', '2025-12-12', 'offline',
  'Gedung P PCU', 'ID', 102, '{4,17}', 'Dua mahasiswa Hanyang University mengikuti perkuliahan semester ganjil di Prodi Manajemen PCU, termasuk mata kuliah Indonesian Business Environment dan Entrepreneurship. Kegiatan dilengkapi program buddy dan kunjungan industri ke kawasan SIER Surabaya.',
  pg_temp.wib('2025-12-18'), 'approved', pg_temp.wib('2025-12-29', '14:00'));
select pg_temp.bulk_pset(178, '{}', '{X01250593,X01250595}', '{}');

select pg_temp.bulk_act(179, 'Riset Bersama Ketahanan Rantai Pasok UMKM Pangan dengan UGM', 21, 4, 'outbound', '2025-09-01', '2025-12-31', 'hybrid',
  'Fakultas Ekonomika dan Bisnis UGM', 'ID', 111, '{2,9,12}', 'Penelitian bersama mengenai ketahanan rantai pasok UMKM pangan olahan di Jawa Timur dan DIY melalui survei 120 pelaku usaha. Luaran berupa model pemetaan risiko pemasok dan draf artikel untuk jurnal terakreditasi SINTA 2.',
  pg_temp.wib('2026-02-10'), null, null,
  p_ext => '[{"full_name":"Dr. Rangga Almahendra","institution":"Universitas Gadjah Mada","country_code":"ID","role":"researcher","notes":"Departemen Manajemen FEB UGM"}]');

select pg_temp.bulk_act(180, 'Pengabdian Masyarakat Digitalisasi Pemasaran Kampung Batik Jetis bersama Unair', 21, 40, 'outbound', '2025-10-11', '2025-11-22', 'offline',
  'Kampung Batik Jetis Sidoarjo', 'ID', 112, '{1,8,17}', 'Pendampingan 25 perajin batik Jetis dalam pembuatan katalog digital, pengelolaan akun marketplace, dan pencatatan penjualan sederhana. Dilaksanakan bersama dosen FEB Universitas Airlangga dalam enam kali pertemuan lapangan.',
  pg_temp.wib('2025-11-28'), null, null,
  p_ext => '[{"full_name":"Dr. Gancar Candra Premananto","institution":"Universitas Airlangga","country_code":"ID","role":"other","notes":"Koordinator pengabdian FEB Unair"}]');

select pg_temp.bulk_act(181, 'Pelatihan Digital Business Analytics bersama Telkom Indonesia', 21, 69, 'inbound', '2025-10-15', '2025-10-16', 'offline',
  'Lab Komputer Manajemen Gedung P PCU', 'ID', 117, '{4,9}', 'Pelatihan dua hari bagi mahasiswa dan dosen Manajemen tentang analitik data pelanggan, dashboard penjualan, dan pemanfaatan big data telekomunikasi untuk segmentasi pasar. Instruktur berasal dari unit Digital Business Telkom Indonesia.',
  pg_temp.wib('2025-10-20'), null, null,
  p_ext => '[{"full_name":"Andika Pratama, M.M.","institution":"PT Telkom Indonesia","country_code":"ID","role":"staff_visitor","notes":"Digital Business & Technology Division"},{"full_name":"Rizky Amalia, S.T., M.B.A.","institution":"PT Telkom Indonesia","country_code":"ID","role":"speaker"}]');

select pg_temp.bulk_act(182, 'Magang Marketing & Customer Experience di Telkom Regional V Surabaya 2025', 21, 21, 'outbound', '2025-09-01', '2025-12-31', 'offline',
  'Gedung Telkom Ketintang Surabaya', 'ID', 116, '{8,9}', 'Tiga mahasiswa Manajemen tingkat akhir menjalani magang empat bulan di divisi Marketing dan Customer Experience Telkom Regional V. Mahasiswa terlibat dalam analisis kepuasan pelanggan IndiHome dan penyusunan materi kampanye produk enterprise.',
  pg_temp.wib('2026-01-09'), 'approved', pg_temp.wib('2026-01-20', '14:00'));
select pg_temp.bulk_pset(182, '{D31226522,D31226725,D31226810}', '{}', '{PG561867}');

select pg_temp.bulk_act(183, 'Kuliah Bersama Human Resource Analytics dengan Hanyang University', 21, 34, 'inbound', '2025-11-05', '2025-12-10', 'online',
  'Zoom Meeting', null, 102, '{4,8}', 'Enam sesi kuliah bersama daring untuk mata kuliah Manajemen SDM Strategik yang membahas people analytics, prediksi turnover, dan desain sistem kinerja. Mahasiswa PCU dan Hanyang mengerjakan tugas kelompok lintas negara.',
  pg_temp.wib('2025-12-15'), null, null,
  p_ext => '[{"full_name":"Assoc. Prof. Lee Min-ji, Ph.D.","institution":"Hanyang University","country_code":"KR","role":"visiting_lecturer","notes":"Human Resource Management"}]');

-- AY 2025/2026 Genap
select pg_temp.bulk_act(184, 'Student Exchange Hanyang Business School Spring Semester 2026', 21, 2, 'outbound', '2026-02-23', '2026-06-19', 'offline',
  'Hanyang University Seoul Campus', 'KR', 102, '{4,17}', 'Empat mahasiswa Manajemen mengikuti semester musim semi di Hanyang Business School dengan mata kuliah Digital Business Strategy, Supply Chain Management, dan Korean Language I. Hasil studi diakui sebagai 20 SKS.',
  pg_temp.wib('2026-06-29'), 'approved', pg_temp.wib('2026-07-08', '14:00'));
select pg_temp.bulk_pset(184, '{D31246615,D31246630,D31256663,D31246665}', '{}', '{}');

select pg_temp.bulk_act(185, 'Inbound Exchange Hanyang University Spring 2026 di Prodi Manajemen', 21, 2, 'inbound', '2026-02-23', '2026-06-12', 'offline',
  'Gedung P PCU', 'ID', 102, '{4,17}', 'Mahasiswa Hanyang University mengikuti semester genap di Prodi Manajemen PCU dengan mata kuliah Marketing Management, Bahasa Indonesia untuk Penutur Asing, dan Family Business. Program dilengkapi pendampingan buddy mahasiswa.',
  pg_temp.wib('2026-06-19'), 'approved', pg_temp.wib('2026-06-26', '14:00'));
select pg_temp.bulk_pset(185, '{}', '{X02260598}', '{}');

select pg_temp.bulk_act(186, 'Inbound Exchange Tunghai University Spring 2026 di Prodi Manajemen', 21, 2, 'inbound', '2026-02-09', '2026-06-12', 'offline',
  'Gedung P PCU', 'ID', 114, '{4,17}', 'Dua mahasiswa Tunghai University mengikuti perkuliahan semester genap di Prodi Manajemen, khususnya mata kuliah Operations Management dan Southeast Asian Business. Kerja sama tercatat atas nama FBE sehingga diajukan dengan catatan lingkup unit.',
  pg_temp.wib('2026-06-22'), 'approved', pg_temp.wib('2026-07-02', '14:00'));
select pg_temp.bulk_pset(186, '{}', '{X02250601,X02250608}', '{}');

select pg_temp.bulk_act(187, 'Kuliah Tamu Sustainable Supply Chain Management dari FEB UGM', 21, 15, 'inbound', '2026-03-11', '2026-03-11', 'offline',
  'Auditorium Gedung W PCU', 'ID', 111, '{9,12,17}', 'Kuliah tamu tentang praktik rantai pasok berkelanjutan, green procurement, dan pengukuran jejak karbon logistik bagi mahasiswa konsentrasi Operasi dan Rantai Pasok. Dihadiri sekitar 150 mahasiswa dan dosen.',
  pg_temp.wib('2026-03-16'), null, null,
  p_ext => '[{"full_name":"Prof. Dr. Eko Suwardi","institution":"Universitas Gadjah Mada","country_code":"ID","role":"speaker","notes":"FEB UGM"}]');

select pg_temp.bulk_act(188, 'Sertifikasi Digital Marketing Associate bersama Telkom Indonesia', 21, 44, 'inbound', '2026-04-18', '2026-04-19', 'offline',
  'Lab Komputer Manajemen Gedung P PCU', 'ID', 117, '{4,8}', 'Program sertifikasi kompetensi pemasaran digital bagi 40 mahasiswa Manajemen yang mencakup SEO, iklan media sosial, dan analitik kampanye. Ujian sertifikasi diselenggarakan oleh asesor Telkom Corporate University.',
  pg_temp.wib('2026-04-24'), null, null,
  p_ext => '[{"full_name":"Dimas Aditya, S.Kom., M.M.","institution":"PT Telkom Indonesia","country_code":"ID","role":"staff_visitor","notes":"Asesor Telkom Corporate University"}]');

select pg_temp.bulk_act(189, 'Studi Ekskursi Manajemen Operasi ke Telkom Indonesia Bandung', 21, 24, 'outbound', '2026-05-12', '2026-05-15', 'offline',
  'Telkom Indonesia Kantor Pusat Japati Bandung', 'ID', 116, '{4,9}', 'Kunjungan studi empat hari ke kantor pusat dan pusat inovasi Telkom di Bandung untuk mempelajari manajemen operasi jaringan, layanan pelanggan, dan pengelolaan startup binaan. Mahasiswa menyusun laporan observasi proses bisnis.',
  pg_temp.wib('2026-05-22'), 'approved', pg_temp.wib('2026-05-29', '14:00'));
select pg_temp.bulk_pset(189, '{D31256466,D31256758,D31246788,D31246805,D31236566,D31236572}', '{}', '{PG214411}');

select pg_temp.bulk_act(190, 'Publikasi Bersama Perilaku Konsumen Produk Halal dengan Universitas Airlangga', 21, 37, 'outbound', '2026-02-02', '2026-05-29', 'online',
  'Microsoft Teams', null, 112, '{4,12}', 'Penulisan artikel bersama tentang niat beli konsumen milenial terhadap produk makanan halal kemasan di Surabaya. Naskah disusun bersama dosen FEB Unair dan dikirim ke Journal of Islamic Marketing.',
  pg_temp.wib('2026-06-08'), null, null,
  p_ext => '[{"full_name":"Dr. Indrianawati Usman","institution":"Universitas Airlangga","country_code":"ID","role":"researcher","notes":"Departemen Manajemen FEB Unair"}]');

select pg_temp.bulk_act(191, 'Pengembangan Kurikulum Kewirausahaan Digital MBKM bersama UGM', 21, 11, 'inbound', '2026-03-02', '2026-04-30', 'hybrid',
  'Ruang Rapat Prodi Manajemen Gedung P PCU', 'ID', 111, '{4,8}', 'Rangkaian lokakarya penyusunan paket mata kuliah Kewirausahaan Digital 20 SKS untuk skema MBKM yang dapat diambil lintas kampus. Luaran berupa RPS, rubrik penilaian proyek, dan skema rekognisi SKS bersama.',
  pg_temp.wib('2026-05-06'), null, null,
  p_ext => '[{"full_name":"Dr. Nurul Indarti","institution":"Universitas Gadjah Mada","country_code":"ID","role":"visiting_lecturer","notes":"Departemen Manajemen FEB UGM"}]');

select pg_temp.bulk_act(192, 'Hanyang International Summer School 2026 Global Marketing Track', 21, 23, 'outbound', '2026-06-29', '2026-07-24', 'offline',
  'Hanyang University Seoul Campus', 'KR', 102, '{4,17}', 'Empat mahasiswa Manajemen mengikuti program musim panas empat minggu di Hanyang University pada jalur Global Marketing, termasuk kunjungan perusahaan ke CJ ENM dan Amorepacific. Diakui sebagai 6 SKS mata kuliah pilihan.',
  pg_temp.wib('2026-08-04'), 'approved', pg_temp.wib('2026-08-12', '14:00'));
select pg_temp.bulk_pset(192, '{D31236590,D31236684,D31236696,D31236698}', '{}', '{}');

select pg_temp.bulk_act(193, 'Seminar Nasional Manajemen SDM di Era Kecerdasan Buatan bersama Unair', 21, 10, 'inbound', '2026-05-20', '2026-05-20', 'offline',
  'Auditorium Gedung W PCU', 'ID', 112, '{4,8}', 'Seminar nasional yang membahas dampak kecerdasan buatan terhadap rekrutmen, pengembangan talenta, dan desain pekerjaan. Menghadirkan pembicara dari FEB Unair dan praktisi HR, diikuti 220 peserta dari kampus dan industri.',
  pg_temp.wib('2026-05-25'), null, null,
  p_ext => '[{"full_name":"Prof. Dr. Badri Munir Sukoco","institution":"Universitas Airlangga","country_code":"ID","role":"speaker","notes":"Guru Besar Manajemen Strategik FEB Unair"}]');

-- AY 2026/2027 Ganjil
select pg_temp.bulk_act(194, 'Guest Lecture Circular Business Models dari Fontys Business School', 21, 15, 'inbound', '2026-09-02', '2026-09-02', 'hybrid',
  'Auditorium Gedung W PCU', 'ID', 105, '{9,12}', 'Kuliah tamu mengenai model bisnis sirkular dan contoh penerapannya pada UMKM di Belanda bagi mahasiswa mata kuliah Inovasi Model Bisnis. Kerja sama Fontys tercatat untuk FBE sehingga diajukan dengan catatan lingkup unit.',
  pg_temp.wib('2026-09-07'), null, null,
  p_ext => '[{"full_name":"Dr. Maarten de Vries","institution":"Fontys University of Applied Sciences","country_code":"NL","role":"speaker","notes":"Fontys Business School, Eindhoven"}]');

select pg_temp.bulk_act(195, 'Magang Digital Business Telkom Indonesia Batch Agustus 2026', 21, 21, 'outbound', '2026-08-03', '2026-09-25', 'offline',
  'Gedung Telkom Ketintang Surabaya', 'ID', 117, '{8,9}', 'Dua mahasiswa Manajemen magang delapan minggu di unit Digital Business Telkom Regional V untuk mendukung riset pasar layanan Pijar dan analisis funnel penjualan digital UMKM.',
  pg_temp.daysago(6), 'pending', null);
select pg_temp.bulk_pset(195, '{D31236477,D31236534}', '{}', '{}');

select pg_temp.bulk_act(196, 'Studi Ekskursi Rantai Pasok Sentra UMKM Kerajinan Yogyakarta bersama UGM', 21, 24, 'outbound', '2026-09-14', '2026-09-17', 'offline',
  'Fakultas Ekonomika dan Bisnis UGM', 'ID', 111, '{8,12}', 'Kunjungan studi ke sentra kerajinan perak Kotagede dan gerabah Kasongan bersama dosen FEB UGM untuk memetakan rantai pasok dan saluran distribusi UMKM. Mahasiswa mempresentasikan rekomendasi perbaikan logistik di FEB UGM.',
  pg_temp.daysago(12), 'pending', null);
select pg_temp.bulk_pset(196, '{D31256466,D31256758,D31246788,D32226832,D32256875}', '{}', '{PG295222}');

select pg_temp.bulk_act(197, 'Indonesian Business Culture Immersion untuk Mahasiswa Hanyang 2026', 21, 22, 'inbound', '2026-08-03', '2026-08-21', 'offline',
  'Kampus PCU Siwalankerto', 'ID', 102, '{4,17}', 'Program imersi tiga minggu bagi mahasiswa Hanyang University tentang budaya bisnis Indonesia, negosiasi lintas budaya, dan kunjungan ke perusahaan keluarga di Surabaya. Ditutup dengan presentasi rencana masuk pasar Indonesia.',
  pg_temp.daysago(15), 'revision_requested', pg_temp.daysago(8, '14:00'),
  p_mnote => 'Transkrip nilai dan sertifikat program mahasiswa inbound belum dilampirkan pada berkas mobilitas; mohon unggah ulang beserta daftar hadir harian.');
select pg_temp.bulk_pset(197, '{}', '{X02260598,X01250593}', '{}');

select pg_temp.bulk_act(198, 'Pendampingan Pemasaran Digital UMKM Kampung Kue Rungkut bersama Telkom Indonesia', 21, 40, 'outbound', '2026-08-08', '2026-09-12', 'offline',
  'Kampung Kue Rungkut Lor Surabaya', 'ID', 116, '{1,8,17}', 'Mahasiswa dan dosen Manajemen bersama relawan Telkom mendampingi 30 pelaku UMKM kue dalam foto produk, pemasaran WhatsApp Business, dan pembayaran QRIS. Luaran berupa peningkatan pesanan daring dan katalog bersama kampung.',
  pg_temp.wib('2026-09-18'), null, null,
  p_ext => '[{"full_name":"Yudha Kurniawan, S.E.","institution":"PT Telkom Indonesia","country_code":"ID","role":"staff_visitor","notes":"Program CSR Telkom Regional V"}]');

-- Drafts
select pg_temp.bulk_act(199, 'Joint Research Digital Supply Chain Resilience dengan Hanyang University', 21, 4, 'outbound', '2026-10-15', '2027-01-29', 'hybrid',
  'Hanyang University Seoul Campus', 'KR', 102, '{9,17}', 'Rencana penelitian bersama tentang adopsi platform digital untuk ketahanan rantai pasok eksportir furnitur Jawa Timur ke Korea Selatan. Tahap awal berupa penyusunan instrumen dan pengumpulan data wawancara.',
  null, null, null, p_files => '{ia}',
  p_ext => '[{"full_name":"Prof. Park Sung-hoon, Ph.D.","institution":"Hanyang University","country_code":"KR","role":"researcher","notes":"Industrial Engineering & Supply Chain"}]');

select pg_temp.bulk_act(200, 'Studi Ekskursi Bisnis Digital ke Telkom Digital Amoeba Jakarta', 21, 24, 'outbound', '2026-11-17', '2026-11-20', 'offline',
  'Telkom Landmark Tower Jakarta', 'ID', 117, '{8,9}', 'Rencana kunjungan studi ke program inkubasi korporat Digital Amoeba Telkom untuk mempelajari pengembangan produk digital dan corporate venture. Peserta dari Prodi Manajemen dan Akuntansi.',
  null, null, null);
select pg_temp.bulk_pset(200, '{D31246615,D31246630,D32246900,D32236925}', '{}', '{PG214411}');

select pg_temp.bulk_verify(176, 200);
