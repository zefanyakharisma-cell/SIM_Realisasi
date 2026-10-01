-- 04_known: Known Activities register (ids 1–8): 5 matched, 2 unmatched international, 1 dismissed.
insert into realisasi.known_activities (id, title, activity_date, unit_id, partner_name, country_code, is_international, source,
            source_reference, notes, status, matched_activity_id, nudged_at, created_by, created_at) values
  (1, 'Summer program FTI ke Nanyang Polytechnic', '2026-08-03', 10, 'Nanyang Polytechnic', 'SG', true, 'surat_tugas',
      'ST/0812/FTI/VIII/2026', null, 'matched', 'a0000000-0000-4000-8000-000000000013', null,
      '00000000-0000-4000-8000-000000000002', '2026-08-05 10:00+07'),
  (2, 'Riset rantai pasok bersama UTM', '2026-08-12', 10, 'Universiti Teknologi Malaysia', 'MY', true, 'faculty_report',
      'Laporan FTI Agustus 2026', null, 'matched', 'a0000000-0000-4000-8000-000000000009', null,
      '00000000-0000-4000-8000-000000000002', '2026-08-20 10:00+07'),
  (3, 'Pertukaran mahasiswa FBE ke KMUTT', '2026-08-03', 20, 'King Mongkut''s University of Technology Thonburi', 'TH', true, 'loa_visa_letter',
      'LoA KMUTT 2026/115', null, 'matched', 'a0000000-0000-4000-8000-000000000010', null,
      '00000000-0000-4000-8000-000000000002', '2026-08-06 10:00+07'),
  (4, 'Mahasiswa inbound program desain kreatif', '2026-08-10', 30, 'De La Salle University', 'PH', true, 'email',
      'Email DLSU 2026-07-28', null, 'matched', 'a0000000-0000-4000-8000-000000000011', null,
      '00000000-0000-4000-8000-000000000002', '2026-08-11 10:00+07'),
  (5, 'Seminar industri telekomunikasi', '2026-09-14', 21, 'PT Telkom Indonesia', 'ID', false, 'news',
      'https://www.petra.ac.id/berita/seminar-telkom-2026', null, 'matched', 'a0000000-0000-4000-8000-000000000012', null,
      '00000000-0000-4000-8000-000000000002', '2026-09-16 10:00+07'),
  (6, 'Kunjungan dosen FBE ke Hanyang University', '2026-09-08', 20, 'Hanyang University', 'KR', true, 'surat_tugas',
      'ST/0931/FBE/IX/2026', 'Belum ada laporan di SIM Realisasi.', 'unmatched', null, null,
      '00000000-0000-4000-8000-000000000002', '2026-09-10 10:00+07'),
  (7, 'Workshop desain bersama Chulalongkorn University', '2026-09-21', 30, 'Chulalongkorn University', 'TH', true, 'news',
      'https://www.petra.ac.id/berita/workshop-cu-2026', null, 'unmatched', null, null,
      '00000000-0000-4000-8000-000000000002', '2026-09-23 10:00+07'),
  (8, 'Webinar alumni (bukan kegiatan kerja sama)', '2026-09-02', null, null, null, true, 'email',
      null, 'Diabaikan: bukan implementasi kerja sama.', 'dismissed', null, null,
      '00000000-0000-4000-8000-000000000001', '2026-09-03 10:00+07')
on conflict (id) do nothing;
select setval('realisasi.known_activities_id_seq', greatest(8, (select max(id) from realisasi.known_activities)));
