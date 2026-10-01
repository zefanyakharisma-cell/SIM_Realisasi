-- 01_config: settings, calendar, holidays, Jenis Kegiatan, SDGs, team membership. Idempotent.

-- Demo deployment: enable demo_today time travel (M9). Production does not run seeds, so the flag stays absent (= off).
-- To disable on an existing database: update realisasi.deployment_flags set enabled = false where key = 'demo_time_travel';
insert into realisasi.deployment_flags (key, enabled) values ('demo_time_travel', true) on conflict (key) do nothing;

insert into realisasi.settings (key, value) values
  ('grace_period_months', '6'), ('reporting_deadline_days', '30'), ('sla_yellow_days', '3'), ('sla_red_days', '5'),
  ('revision_reminder_days', '7'), ('revision_escalate_days', '14'), ('dup_date_window_days', '3'),
  ('dup_name_similarity', '0.5'), ('known_match_window_days', '7'), ('known_name_similarity', '0.4'),
  ('nudge_resend_days', '14'), ('deadline_reminder_before_days', '7'), ('demo_today', 'null')
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

insert into realisasi.holidays (day, name) values
  ('2025-01-01','Tahun Baru Masehi'), ('2025-01-27','Isra Mikraj Nabi Muhammad SAW'), ('2025-01-29','Tahun Baru Imlek'),
  ('2025-03-29','Hari Suci Nyepi'), ('2025-03-31','Hari Raya Idul Fitri'), ('2025-04-01','Hari Raya Idul Fitri'),
  ('2025-04-18','Wafat Yesus Kristus'), ('2025-04-20','Kebangkitan Yesus Kristus (Paskah)'), ('2025-05-01','Hari Buruh Internasional'),
  ('2025-05-12','Hari Raya Waisak'), ('2025-05-29','Kenaikan Yesus Kristus'), ('2025-06-01','Hari Lahir Pancasila'),
  ('2025-06-06','Hari Raya Idul Adha'), ('2025-06-27','Tahun Baru Islam'), ('2025-08-17','Hari Kemerdekaan RI'),
  ('2025-09-05','Maulid Nabi Muhammad SAW'), ('2025-12-25','Hari Raya Natal'),
  ('2026-01-01','Tahun Baru Masehi'), ('2026-01-16','Isra Mikraj Nabi Muhammad SAW'), ('2026-02-17','Tahun Baru Imlek'),
  ('2026-03-19','Hari Suci Nyepi'), ('2026-03-20','Hari Raya Idul Fitri'), ('2026-03-21','Hari Raya Idul Fitri'),
  ('2026-04-03','Wafat Yesus Kristus'), ('2026-04-05','Kebangkitan Yesus Kristus (Paskah)'), ('2026-05-01','Hari Buruh Internasional'),
  ('2026-05-14','Kenaikan Yesus Kristus'), ('2026-05-27','Hari Raya Idul Adha'), ('2026-05-31','Hari Raya Waisak'),
  ('2026-06-01','Hari Lahir Pancasila'), ('2026-06-16','Tahun Baru Islam'), ('2026-08-17','Hari Kemerdekaan RI'),
  ('2026-08-25','Maulid Nabi Muhammad SAW'), ('2026-12-25','Hari Raya Natal'),
  ('2027-01-01','Tahun Baru Masehi'), ('2027-01-05','Isra Mikraj Nabi Muhammad SAW'), ('2027-02-06','Tahun Baru Imlek'),
  ('2027-03-08','Hari Suci Nyepi'), ('2027-03-10','Hari Raya Idul Fitri'), ('2027-03-11','Hari Raya Idul Fitri'),
  ('2027-03-26','Wafat Yesus Kristus'), ('2027-03-28','Kebangkitan Yesus Kristus (Paskah)'), ('2027-05-01','Hari Buruh Internasional'),
  ('2027-05-06','Kenaikan Yesus Kristus'), ('2027-05-17','Hari Raya Idul Adha'), ('2027-05-20','Hari Raya Waisak'),
  ('2027-06-01','Hari Lahir Pancasila'), ('2027-06-06','Tahun Baru Islam'), ('2027-08-15','Maulid Nabi Muhammad SAW'),
  ('2027-08-17','Hari Kemerdekaan RI'), ('2027-12-25','Hari Raya Natal')
on conflict (day) do update set name = excluded.name;

insert into realisasi.activity_types (id, name, direction, counts_as_mobility, counts_for_s1, requires_mobility_review, is_active, sort_order) values
  (1, 'Student Outbound Mobility',          'outbound', true,  true, true,  true, 1),
  (2, 'Student Inbound Mobility',           'inbound',  true,  true, true,  true, 2),
  (3, 'Staff Outbound Mobility',            'none',     false, true, true,  true, 3),
  (4, 'Visiting Lecturer / Guest Lecture',  'none',     false, true, false, true, 4),
  (5, 'Joint Research',                     'none',     false, true, false, true, 5),
  (6, 'Joint Seminar / Conference',         'none',     false, true, false, true, 6),
  (7, 'Summer / Winter Program (Outbound)', 'outbound', true,  true, true,  true, 7),
  (8, 'Community Service (Joint)',          'none',     false, true, false, true, 8),
  (9, 'Joint Publication',                  'none',     false, true, false, true, 9)
on conflict (id) do nothing;

insert into realisasi.sdgs (id, name) values
  (1,'Tanpa Kemiskinan'), (2,'Tanpa Kelaparan'), (3,'Kehidupan Sehat dan Sejahtera'), (4,'Pendidikan Berkualitas'),
  (5,'Kesetaraan Gender'), (6,'Air Bersih dan Sanitasi Layak'), (7,'Energi Bersih dan Terjangkau'),
  (8,'Pekerjaan Layak dan Pertumbuhan Ekonomi'), (9,'Industri, Inovasi dan Infrastruktur'), (10,'Berkurangnya Kesenjangan'),
  (11,'Kota dan Permukiman yang Berkelanjutan'), (12,'Konsumsi dan Produksi yang Bertanggung Jawab'),
  (13,'Penanganan Perubahan Iklim'), (14,'Ekosistem Lautan'), (15,'Ekosistem Daratan'),
  (16,'Perdamaian, Keadilan dan Kelembagaan yang Tangguh'), (17,'Kemitraan untuk Mencapai Tujuan')
on conflict (id) do update set name = excluded.name;

insert into realisasi.team_members (account_id, team) values
  ('00000000-0000-4000-8000-000000000001', 'partnership'), ('00000000-0000-4000-8000-000000000001', 'mobility'),
  ('00000000-0000-4000-8000-000000000002', 'partnership'), ('00000000-0000-4000-8000-000000000003', 'mobility')
on conflict do nothing;

select setval('realisasi.academic_years_id_seq', greatest((select max(id) from realisasi.academic_years), 1));
select setval('realisasi.semesters_id_seq', greatest((select max(id) from realisasi.semesters), 1));
select setval('realisasi.activity_types_id_seq', greatest((select max(id) from realisasi.activity_types), 1));
