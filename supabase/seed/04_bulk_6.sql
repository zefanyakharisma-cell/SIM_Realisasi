-- 04_bulk_6: Prodi DKV (unit 31) with The University of Queensland: illustration, animation, branding, UX/UI, photography, film, typography, game art. RL-2026-0226..0250. Students: the 04_bulk_6 slice of 04_bulk_0_registry.sql.
\ir bulk/_helpers.inc

-- AY 2025/2026 Ganjil
select pg_temp.bulk_act(226, 'Student Exchange Semester 2 2025 Visual Communication di The University of Queensland', 31, 2, 'outbound', '2025-08-04', '2025-11-21', 'offline',
  'UQ St Lucia Campus, Brisbane', 'AU', 106, '{4,17}', 'Tiga mahasiswa DKV mengikuti satu semester di School of Communication and Arts UQ, mengambil mata kuliah Visual Communication Design dan Digital Media. Kredit dikonversi ke kurikulum DKV melalui skema transfer kredit.',
  pg_temp.wib('2025-12-03'), 'approved', pg_temp.wib('2025-12-12', '14:00'));
select pg_temp.bulk_pset(226, '{C21247475,C21237503,C21247508}', '{}', '{}');

select pg_temp.bulk_act(227, 'Kuliah Tamu Motion Graphics untuk Narasi Data oleh UQ', 31, 15, 'inbound', '2025-09-17', '2025-09-17', 'hybrid',
  'Auditorium Gedung P PCU', 'ID', 106, '{4,9}', 'Kuliah tamu tentang perancangan motion graphics untuk menyampaikan data kompleks secara naratif, dilengkapi studi kasus infografis animasi media berita Australia. Diikuti mahasiswa mata kuliah Desain Animasi secara luring dan daring.',
  pg_temp.wib('2025-09-24'), null, null,
  p_ext => '[{"full_name":"Dr. Rachel Bennett","institution":"The University of Queensland","country_code":"AU","role":"speaker"}]');

select pg_temp.bulk_act(228, 'Inbound Short Program Batik dan Visual Heritage Surabaya untuk Mahasiswa UQ', 31, 23, 'inbound', '2025-09-08', '2025-09-26', 'offline',
  'Studio DKV Gedung P PCU', 'ID', 106, '{4,11}', 'Program singkat tiga minggu bagi mahasiswa UQ untuk mempelajari motif batik pesisir dan arsip visual kota lama Surabaya. Luaran berupa seri ilustrasi dan pola permukaan yang dipamerkan di akhir program.',
  pg_temp.wib('2025-10-06'), 'approved', pg_temp.wib('2025-10-14', '14:00'));
select pg_temp.bulk_pset(228, '{}', '{X02250643}', '{PG452412}');

select pg_temp.bulk_act(229, 'Riset Bersama Tipografi Aksara Jawa untuk Antarmuka Digital dengan UQ', 31, 4, 'outbound', '2025-08-18', '2025-12-12', 'hybrid',
  'Lab Tipografi DKV Gedung P PCU', 'ID', 106, '{4,9}', 'Penelitian bersama untuk merancang varian font aksara Jawa yang terbaca baik pada layar ponsel. Tim menguji keterbacaan pada antarmuka aplikasi dan menyiapkan draf artikel jurnal.',
  pg_temp.wib('2026-01-20'), null, null,
  p_ext => '[{"full_name":"Assoc. Prof. Daniel Kerr","institution":"The University of Queensland","country_code":"AU","role":"researcher"}]');

select pg_temp.bulk_act(230, 'Workshop Game Art dan Character Design bersama UQ Games Studio', 31, 35, 'inbound', '2025-10-20', '2025-10-22', 'offline',
  'Lab Komputer Grafis Gedung P PCU', 'ID', 106, '{4,8}', 'Workshop tiga hari tentang pipeline game art mulai dari concept sketch, character sheet, hingga aset 2D siap pakai di game engine. Peserta menghasilkan satu karakter orisinal yang direview langsung oleh mentor UQ.',
  pg_temp.wib('2025-10-30'), null, null,
  p_ext => '[{"full_name":"Mr. Thomas Nguyen","institution":"The University of Queensland","country_code":"AU","role":"speaker","notes":"Lecturer, Games and Interactive Media"}]');

select pg_temp.bulk_act(231, 'Inbound Cultural Exchange Fotografi Dokumenter dari De La Salle University', 31, 29, 'inbound', '2025-11-03', '2025-11-14', 'offline',
  'Kampus PCU Siwalankerto', 'ID', 109, '{4,11}', 'Mahasiswa De La Salle University mengikuti program pertukaran budaya dengan fokus fotografi dokumenter kehidupan pasar tradisional Surabaya bersama mahasiswa DKV. Hasil foto dikurasi menjadi e-zine bersama.',
  pg_temp.wib('2025-11-20'), 'approved', pg_temp.wib('2025-11-28', '14:00'));
select pg_temp.bulk_pset(231, '{}', '{X02250661}', '{PG780858}');

select pg_temp.bulk_act(232, 'Online Course UX Research Fundamentals bersama UQ', 31, 79, 'inbound', '2025-10-06', '2025-11-28', 'online',
  'Zoom Meeting', null, 106, '{4,9}', 'Kursus daring delapan minggu tentang metode riset pengguna: wawancara, usability testing, dan journey mapping. Materi disampaikan dosen UQ dan dipakai sebagai pengayaan mata kuliah Desain UI/UX.',
  pg_temp.wib('2025-12-05'), null, null,
  p_ext => '[{"full_name":"Dr. Priya Raman","institution":"The University of Queensland","country_code":"AU","role":"visiting_lecturer"}]');

select pg_temp.bulk_act(233, 'Short Program Illustration and Picture Book di The University of Queensland', 31, 23, 'outbound', '2026-01-05', '2026-01-23', 'offline',
  'UQ St Lucia Campus, Brisbane', 'AU', 106, '{4,17}', 'Empat mahasiswa DKV mengikuti program musim panas UQ tentang ilustrasi buku cerita anak, dari pengembangan karakter hingga storyboard dan dummy book. Didampingi satu dosen DKV.',
  pg_temp.wib('2026-02-02'), 'approved', pg_temp.wib('2026-02-10', '14:00'));
select pg_temp.bulk_pset(233, '{C21247537,C21247541,C21237544,C21247546}', '{}', '{PG760736}');

-- AY 2025/2026 Genap
select pg_temp.bulk_act(234, 'Student Exchange Semester 1 2026 Digital Media di The University of Queensland', 31, 2, 'outbound', '2026-02-23', '2026-06-19', 'offline',
  'UQ St Lucia Campus, Brisbane', 'AU', 106, '{4,17}', 'Pertukaran satu semester bagi tiga mahasiswa DKV di program Digital Media UQ, dengan mata kuliah animasi, interaction design, dan media studies. Nilai dikonversi melalui transfer kredit.',
  pg_temp.wib('2026-06-29'), 'approved', pg_temp.wib('2026-07-08', '14:00'));
select pg_temp.bulk_pset(234, '{C21227573,C21227583,C21247592}', '{}', '{}');

select pg_temp.bulk_act(235, 'Inbound Student Exchange UQ di Prodi DKV Semester Genap 2026', 31, 2, 'inbound', '2026-02-09', '2026-06-12', 'offline',
  'Kampus PCU Siwalankerto', 'ID', 106, '{4,17}', 'Dua mahasiswa UQ mengikuti satu semester di Prodi DKV, mengambil mata kuliah Desain Komunikasi Visual Nusantara, Fotografi, dan Bahasa Indonesia untuk Penutur Asing.',
  pg_temp.wib('2026-06-22'), 'approved', pg_temp.wib('2026-07-01', '14:00'));
select pg_temp.bulk_pset(235, '{}', '{X02260652,X02260655}', '{PG452412}');

select pg_temp.bulk_act(236, 'Guest Lecture Brand Identity untuk Destinasi Wisata oleh UQ', 31, 7, 'inbound', '2026-03-11', '2026-03-11', 'offline',
  'Auditorium Gedung W PCU', 'ID', 106, '{8,11}', 'Kuliah umum tentang perancangan identitas merek destinasi wisata, membahas kasus rebranding kota-kota di Queensland dan peluang penerapannya untuk kawasan Kota Lama Surabaya.',
  pg_temp.wib('2026-03-18'), null, null,
  p_ext => '[{"full_name":"Prof. Sarah Mitchell","institution":"The University of Queensland","country_code":"AU","role":"speaker"}]');

select pg_temp.bulk_act(237, 'Seminar Internasional Visualisasi Informasi dan Desain Interaksi bersama NTUST', 30, 10, 'inbound', '2026-04-15', '2026-04-16', 'hybrid',
  'Auditorium Gedung W PCU', 'ID', 103, '{4,9,17}', 'Seminar dua hari yang mempertemukan peneliti FSD dan NTUST untuk membahas visualisasi informasi, dashboard publik, dan desain interaksi. Mahasiswa DKV mempresentasikan poster karya riset.',
  pg_temp.wib('2026-04-24'), null, null,
  p_ext => '[{"full_name":"Prof. Dr. Chen Wei-Lun","institution":"National Taiwan University of Science and Technology (NTUST)","country_code":"TW","role":"speaker"}]',
  p_co_units => '{31}');

select pg_temp.bulk_act(238, 'Pengembangan Kurikulum Animasi 2D dan 3D bersama UQ', 31, 11, 'inbound', '2026-03-02', '2026-05-29', 'hybrid',
  'Ruang Rapat Prodi DKV Gedung P PCU', 'ID', 106, '{4}', 'Penyusunan ulang capaian pembelajaran dan rencana studi peminatan animasi dengan membandingkan struktur mata kuliah animasi UQ. Luaran berupa dokumen RPS baru untuk empat mata kuliah.',
  pg_temp.wib('2026-06-05'), null, null,
  p_ext => '[{"full_name":"Dr. Hannah Brooks","institution":"The University of Queensland","country_code":"AU","role":"other","notes":"Program coordinator, Animation"}]');

select pg_temp.bulk_act(239, 'Pengabdian Masyarakat Rebranding UMKM Kampung Kue Rungkut bersama UQ', 31, 40, 'inbound', '2026-04-20', '2026-05-15', 'offline',
  'Kampung Kue Rungkut Lor, Surabaya', 'ID', 106, '{1,8,11}', 'Dosen DKV dan staf UQ mendampingi pelaku UMKM kue di Rungkut Lor merancang ulang logo, kemasan, dan konten media sosial. Sebanyak dua belas usaha menerima paket identitas visual baru.',
  pg_temp.wib('2026-05-25'), null, null,
  p_ext => '[{"full_name":"Ms. Laura Fitzgerald","institution":"The University of Queensland","country_code":"AU","role":"staff_visitor"}]');

select pg_temp.bulk_act(240, 'Studi Ekskursi Film Dokumenter ke Institut Teknologi Bandung', 31, 24, 'outbound', '2026-05-11', '2026-05-15', 'offline',
  'Kampus ITB Ganesha, Bandung', 'ID', 110, '{4,11}', 'Mahasiswa peminatan film mengunjungi studio dan laboratorium Fakultas Seni Rupa dan Desain ITB, mengikuti kelas produksi dokumenter, serta merekam film pendek tentang ruang publik Bandung.',
  pg_temp.wib('2026-05-22'), 'approved', pg_temp.wib('2026-06-02', '14:00'));
select pg_temp.bulk_pset(240, '{C21237617,C21237618,C21237645,C21247646,C21257658,C21247680}', '{}', '{PG780858}');

select pg_temp.bulk_act(241, 'Publikasi Bersama Kajian Visual Kampanye Iklim di Media Sosial dengan UQ', 31, 5, 'outbound', '2026-02-02', '2026-07-17', 'online',
  'Microsoft Teams', null, 106, '{13,4}', 'Kolaborasi penulisan artikel yang menganalisis strategi visual kampanye perubahan iklim di Instagram Indonesia dan Australia. Naskah dikirim ke jurnal desain bereputasi.',
  pg_temp.wib('2026-08-24'), null, null,
  p_ext => '[{"full_name":"Assoc. Prof. Megan O''Connor","institution":"The University of Queensland","country_code":"AU","role":"researcher"}]');

select pg_temp.bulk_act(242, 'Magang Desain UX/UI di UQ Digital Learning Lab', 31, 21, 'outbound', '2026-06-29', '2026-07-31', 'offline',
  'UQ St Lucia Campus, Brisbane', 'AU', 106, '{8,9}', 'Tiga mahasiswa DKV magang di unit pengembangan pembelajaran digital UQ, merancang prototipe antarmuka modul e-learning dan melakukan usability test bersama tim produk.',
  pg_temp.wib('2026-08-07'), 'approved', pg_temp.wib('2026-08-17', '14:00'));
select pg_temp.bulk_pset(242, '{C21247697,C21227700,C21247850}', '{}', '{}');

-- AY 2026/2027 Ganjil
select pg_temp.bulk_act(243, 'Short Program Desain Kemasan Berkelanjutan di KMUTT', 30, 23, 'outbound', '2026-08-03', '2026-08-14', 'offline',
  'KMUTT Bang Mod Campus, Bangkok', 'TH', 108, '{9,12}', 'Program singkat dua minggu di KMUTT tentang desain kemasan ramah lingkungan, material alternatif, dan komunikasi visual label produk. Diikuti mahasiswa DKV dengan pendamping dari FSD.',
  pg_temp.wib('2026-08-20'), 'approved', pg_temp.wib('2026-08-31', '14:00'),
  p_co_units => '{31}');
select pg_temp.bulk_pset(243, '{C21237701,C21227735,C21237749}', '{}', '{PG761401}');

select pg_temp.bulk_act(244, 'Kuliah Tamu Sinematografi dan Color Grading dari UQ Film Studies', 31, 15, 'inbound', '2026-09-02', '2026-09-02', 'offline',
  'Auditorium Gedung P PCU', 'ID', 106, '{4,8}', 'Kuliah tamu tentang bahasa visual sinematografi dan alur color grading untuk film pendek, disertai demo langsung penyuntingan warna pada footage karya mahasiswa DKV.',
  pg_temp.wib('2026-09-09'), null, null,
  p_ext => '[{"full_name":"Dr. Benjamin Clarke","institution":"The University of Queensland","country_code":"AU","role":"visiting_lecturer"}]');

select pg_temp.bulk_act(245, 'Inbound Short Program Ilustrasi Cerita Rakyat Nusantara untuk Mahasiswa De La Salle', 30, 23, 'inbound', '2026-08-10', '2026-09-04', 'offline',
  'Studio Ilustrasi Gedung P PCU', 'ID', 109, '{4,11,17}', 'Mahasiswa De La Salle University mempelajari cerita rakyat Jawa Timur dan menerjemahkannya menjadi ilustrasi naratif bersama mahasiswa DKV. Karya akhir dihimpun dalam buku digital dwibahasa.',
  pg_temp.daysago(12), 'pending', null,
  p_co_units => '{31}');
select pg_temp.bulk_pset(245, '{}', '{X02250661,X02260663}', '{PG452412}');

select pg_temp.bulk_act(246, 'Short Program Animasi dan Visual Effects di The University of Queensland', 31, 23, 'outbound', '2026-08-24', '2026-09-18', 'offline',
  'UQ St Lucia Campus, Brisbane', 'AU', 106, '{4,9}', 'Tiga mahasiswa DKV mengikuti program singkat empat minggu tentang compositing, motion tracking, dan efek visual untuk animasi pendek di studio media UQ.',
  pg_temp.daysago(7), 'pending', null);
select pg_temp.bulk_pset(246, '{C21257779,C21257809,C21247837}', '{}', '{PG760736}');

select pg_temp.bulk_act(247, 'Inbound Academic Exchange Desain Game dari The University of Queensland', 31, 28, 'inbound', '2026-08-03', '2026-09-11', 'offline',
  'Lab Game Art Gedung P PCU', 'ID', 106, '{4,9}', 'Tiga mahasiswa UQ bergabung dengan studio game art DKV selama enam minggu untuk mengembangkan prototipe game edukasi bertema budaya Surabaya bersama mahasiswa PCU.',
  pg_temp.daysago(15), 'revision_requested', pg_temp.daysago(6),
  p_mnote => 'Mohon unggah Letter of Acceptance untuk Jack Thompson dan perbaiki nomor mahasiswa asal Amelia White sesuai transkrip UQ.');
select pg_temp.bulk_pset(247, '{}', '{X02250643,X02260652,X02260655}', '{PG452412}');

select pg_temp.bulk_act(248, 'Pameran Bersama Poster Tipografi Eksperimental PCU dan UQ', 31, 35, 'inbound', '2026-09-14', '2026-09-19', 'hybrid',
  'Galeri Gedung P PCU', 'ID', 106, '{4,11,17}', 'Pameran enam hari yang menampilkan 60 poster tipografi eksperimental karya mahasiswa DKV dan UQ, dilengkapi tur virtual dan diskusi kuratorial daring bersama dosen UQ.',
  pg_temp.wib('2026-09-25'), null, null,
  p_ext => '[{"full_name":"Assoc. Prof. Daniel Kerr","institution":"The University of Queensland","country_code":"AU","role":"speaker","notes":"Kurator tamu"}]');

-- Drafts
select pg_temp.bulk_act(249, 'Riset Bersama Visual Storytelling Edukasi Mitigasi Bencana dengan UQ', 31, 4, 'outbound', '2026-11-02', '2027-01-29', 'hybrid',
  'Lab Riset DKV Gedung P PCU', 'ID', 106, '{11,13}', 'Rencana riset bersama untuk merancang komik dan animasi pendek edukasi mitigasi banjir bagi siswa sekolah dasar di Surabaya, diuji efektivitasnya bersama tim UQ.',
  null, null, null, p_files => '{ia}');

select pg_temp.bulk_act(250, 'Staff Exchange Dosen DKV ke UQ School of Communication and Arts', 31, 3, 'outbound', '2026-11-16', '2026-11-27', 'offline',
  'UQ St Lucia Campus, Brisbane', 'AU', 106, '{4,17}', 'Dua dosen DKV direncanakan mengajar bersama di kelas Visual Communication UQ dan mempelajari tata kelola studio kreatif kampus sebagai bahan pengembangan laboratorium DKV.',
  null, null, null,
  p_ext => '[{"full_name":"Prof. Sarah Mitchell","institution":"The University of Queensland","country_code":"AU","role":"other","notes":"Tuan rumah program"}]');

select pg_temp.bulk_verify(226, 250);
