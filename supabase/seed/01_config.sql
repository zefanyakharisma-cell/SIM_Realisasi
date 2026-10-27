-- 01_config: settings, calendar, Jenis Kegiatan, SDGs. Idempotent and deployment-agnostic: also applied to
-- Supabase by supabase/seed-supabase/01_config.sql. Team membership lives with the accounts (00_kerjasama.sql locally,
-- seed-supabase/03_accounts.sql on Supabase).

-- Demo deployment: enable demo_today time travel (M9). Production does not run seeds, so the flag stays absent (= off).
-- To disable on an existing database: update realisasi.deployment_flags set enabled = false where key = 'demo_time_travel';
insert into realisasi.deployment_flags (key, enabled) values ('demo_time_travel', true) on conflict (key) do nothing;

insert into realisasi.settings (key, value) values
  ('grace_period_months', '6'), ('reporting_deadline_days', '30'), ('revision_reminder_days', '7'),
  ('deadline_reminder_before_days', '7'), ('demo_today', 'null')
on conflict (key) do nothing;

insert into realisasi.academic_years (id, label, start_date, end_date) values
  (1, '2025/2026', '2025-08-01', '2026-07-31'),
  (2, '2026/2027', '2026-08-01', '2027-07-31')
on conflict (id) do update set label = excluded.label, start_date = excluded.start_date, end_date = excluded.end_date;

insert into realisasi.semesters (id, academic_year_id, term, start_date, end_date, cutoff_date) values
  (1, 1, 'ganjil', '2025-08-01', '2026-01-31', '2026-03-02'),
  (2, 1, 'genap',  '2026-02-01', '2026-07-31', '2026-08-30'),
  (3, 2, 'ganjil', '2026-08-01', '2027-01-31', '2027-03-02'),
  (4, 2, 'genap',  '2027-02-01', '2027-07-31', '2027-08-30')
on conflict (id) do update set academic_year_id = excluded.academic_year_id, term = excluded.term,
  start_date = excluded.start_date, end_date = excluded.end_date, cutoff_date = excluded.cutoff_date;


-- Jenis Kegiatan master (IO list "AGENDA - SIM REALISASI"). Keterangan as given by IO (its "(?)" notes included); IO
-- Admin edits the list in Pengaturan -> Jenis Kegiatan. Inserted once: later edits are kept on re-apply.
insert into realisasi.agendas (id, program, name, description, mobility_category, sort_order) values
  (1, 'student_mobility', 'Joint/Double Degree', 'Program bergelar JD/DD minimal 1 tahun', 'jd_dd', 1),
  (2, 'student_mobility', 'Student Exchange', 'Dalam kategori ini masuk Student Exchange, Study Abroad, International Internship, International Research: 1 semester/trimester ATAU jumlah SKS minimal 6', 'student_exchange', 2),
  (3, 'student_mobility', 'Short Program', 'Program berdurasi 14-45 hari atau menghasilkan 2-5 SKS', 'short_summer', 3),
  (4, 'student_mobility', 'International Event', 'Semua kegiatan kurang dari 2 minggu dan non SKS; termasuk aktifitas virtual insidental', 'other_mobility', 4),
  (5, 'faculty_mobility', 'Kolaborasi dan Hibah Global', 'Mencakup joint supervision, mengajar ≥ 1 semester, realisasi IA dengan Mitra Top Tier, serta perolehan hibah pendanaan luar negeri atau sabbatical leave. Top TIer QS 100 atau setara, industri luar negeri (?)', null, 5),
  (6, 'faculty_mobility', 'Forum Akademik Internasional', 'kepanitiaan dan/antau keanggotaan kunci untuk kegiatan seminar, workshop, konferensi internasional atau yang setara', null, 6),
  (7, 'faculty_mobility', 'Kemitraan Institusional', 'Mencakup joint supervision, mengajar ≥ 1 semester, dan realisasi IA operasional dengan Mitra Reguler, non QS 100 atau setara, PTN/PTS papan atas Indonesia, MNC (?)', null, 7),
  (8, 'faculty_mobility', 'Mobilitas Akademik dan Penguatan Kapasitas', 'Durasi > 2 minggu, menggabungkan keikutsertaan program non-degree, sertifikasi atau lomba internasional, dan peran sebagai Dosen Pembimbing Lapangan (DPL), serta kepanitiaan dan/atau keanggotaan kunci regional/nasional', null, 8),
  (9, 'faculty_mobility', 'Eksposur Internasional Jangka Pendek', 'Mencakup program non-degree singkat (< 2 minggu) dan kegiatan menjadi dosen tamu insidental dengan durasi di bawah 1 semester.', null, 9)
on conflict (id) do nothing;
select setval('realisasi.agendas_id_seq', greatest((select max(id) from realisasi.agendas), 1));

insert into realisasi.sdgs (id, name) values
  (1,'Tanpa Kemiskinan'), (2,'Tanpa Kelaparan'), (3,'Kehidupan Sehat dan Sejahtera'), (4,'Pendidikan Berkualitas'),
  (5,'Kesetaraan Gender'), (6,'Air Bersih dan Sanitasi Layak'), (7,'Energi Bersih dan Terjangkau'),
  (8,'Pekerjaan Layak dan Pertumbuhan Ekonomi'), (9,'Industri, Inovasi dan Infrastruktur'), (10,'Berkurangnya Kesenjangan'),
  (11,'Kota dan Permukiman yang Berkelanjutan'), (12,'Konsumsi dan Produksi yang Bertanggung Jawab'),
  (13,'Penanganan Perubahan Iklim'), (14,'Ekosistem Lautan'), (15,'Ekosistem Daratan'),
  (16,'Perdamaian, Keadilan dan Kelembagaan yang Tangguh'), (17,'Kemitraan untuk Mencapai Tujuan')
on conflict (id) do update set name = excluded.name;

select setval('realisasi.academic_years_id_seq', greatest((select max(id) from realisasi.academic_years), 1));
select setval('realisasi.semesters_id_seq', greatest((select max(id) from realisasi.semesters), 1));
