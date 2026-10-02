-- 01_config: settings, calendar, Jenis Kegiatan rules, SDGs. Idempotent and deployment-agnostic: also applied to
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


-- Jenis Kegiatan = SIMKS agenda (kerjasama.agendas). Default mobility categories (Revisi V.1); IO Admin edits them in
-- Pengaturan. Agendas without a row are non-mobility kegiatan that count for KPI 1.19.S1.
insert into realisasi.agenda_rules (agenda_id, mobility_category) values
  (16, 'jd_dd'), (17, 'jd_dd'), (18, 'jd_dd'), (85, 'jd_dd'),
  (2, 'student_exchange'), (20, 'student_exchange'), (28, 'student_exchange'), (33, 'student_exchange'),
  (22, 'short_summer'), (23, 'short_summer'), (29, 'short_summer'),
  (21, 'other_mobility'), (24, 'other_mobility'), (38, 'other_mobility')
on conflict (agenda_id) do nothing;

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
