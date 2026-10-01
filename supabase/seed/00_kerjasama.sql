-- 00_kerjasama: SIM Kerjasama stub data (units, countries, partners, documents, profiles). Idempotent.

insert into public.units (id, name, parent_id, kind) values
  (1,  'Rektorat', null, 'up'),
  (2,  'International Office', null, 'up'),
  (10, 'Fakultas Teknologi Industri', null, 'faculty'),
  (20, 'Fakultas Bisnis & Ekonomi', null, 'faculty'),
  (30, 'Fakultas Seni & Desain', null, 'faculty'),
  (11, 'Prodi Informatika', 10, 'prodi'),
  (12, 'Prodi Teknik Elektro', 10, 'prodi'),
  (21, 'Prodi Manajemen', 20, 'prodi'),
  (31, 'Prodi Desain Komunikasi Visual', 30, 'prodi')
on conflict (id) do update set name = excluded.name, parent_id = excluded.parent_id, kind = excluded.kind;

insert into public.countries (code, name) values
  ('ID','Indonesia'), ('JP','Jepang'), ('KR','Korea Selatan'), ('TW','Taiwan'), ('DE','Jerman'), ('NL','Belanda'),
  ('AU','Australia'), ('MY','Malaysia'), ('TH','Thailand'), ('PH','Filipina'), ('SG','Singapura'), ('US','Amerika Serikat'),
  ('CN','Tiongkok'), ('FR','Prancis'), ('GB','Britania Raya')
on conflict (code) do update set name = excluded.name;

insert into public.partners (id, name, country_code) values
  (1,  'Kyoto Institute of Technology', 'JP'),
  (2,  'Hanyang University', 'KR'),
  (3,  'National Taiwan University of Science and Technology', 'TW'),
  (4,  'Hochschule Bremen', 'DE'),
  (5,  'Fontys University of Applied Sciences', 'NL'),
  (6,  'The University of Queensland', 'AU'),
  (7,  'Universiti Teknologi Malaysia', 'MY'),
  (8,  'King Mongkut''s University of Technology Thonburi', 'TH'),
  (9,  'De La Salle University', 'PH'),
  (10, 'Universitas Gadjah Mada', 'ID'),
  (11, 'Institut Teknologi Bandung', 'ID'),
  (12, 'Universitas Airlangga', 'ID'),
  (13, 'Nanyang Polytechnic', 'SG'),
  (14, 'Osaka University', 'JP'),
  (15, 'Tunghai University', 'TW'),
  (16, 'PT Telkom Indonesia', 'ID'),
  (17, 'Chulalongkorn University', 'TH'),
  (18, 'Universität Stuttgart', 'DE'),
  (19, 'Universitas Kristen Duta Wacana', 'ID'),
  (20, 'Saxion University of Applied Sciences', 'NL')
on conflict (id) do update set name = excluded.name, country_code = excluded.country_code;

-- documents: parents/predecessors first
insert into public.documents (id, doc_number, title, kind, status, start_date, end_date, auto_renewed, predecessor_id, parent_id, archived_reason, terminated_at) values
  (101, '011/MoU/PCU-KIT/III/2022', 'Kerja Sama Pendidikan dan Riset Teknik',              'MoU', 'active',   '2022-03-01', '2027-02-28', false, null, null, null, null),
  (102, '004/MoU/PCU-HYU/I/2023',   'Pertukaran Mahasiswa dan Staf Bisnis',               'MoU', 'active',   '2023-01-10', '2028-01-09', false, null, null, null, null),
  (103, '019/MoU/PCU-NTUST/II/2024','Kolaborasi Akademik Teknologi dan Desain',          'MoU', 'active',   '2024-02-01', '2029-01-31', false, null, null, null, null),
  (104, '027/MoA/PCU-HSB/IX/2024',  'Riset Bersama Energi Terbarukan',                   'MoA', 'active',   '2024-09-01', '2027-08-31', false, null, null, null, null),
  (105, '002/MoU/PCU-FONTYS/I/2025','Kerja Sama Pendidikan Bisnis Internasional',        'MoU', 'active',   '2025-01-15', '2030-01-14', false, null, null, null, null),
  (106, '014/MoU/PCU-UQ/V/2024',    'Kerja Sama Seni, Desain, dan Media',                'MoU', 'active',   '2024-05-01', '2029-04-30', false, null, null, null, null),
  (107, '008/MoU/PCU-UTM/III/2025', 'Kolaborasi Riset Teknik Industri',                  'MoU', 'active',   '2025-03-01', '2030-02-28', false, null, null, null, null),
  (108, '021/MoA/PCU-KMUTT/VII/2025','Program Mobilitas Bisnis dan Desain',              'MoA', 'active',   '2025-07-01', '2028-06-30', false, null, null, null, null),
  (109, '017/MoU/PCU-DLSU/VIII/2024','Pertukaran Mahasiswa Seni dan Humaniora',          'MoU', 'active',   '2024-08-01', '2029-07-31', false, null, null, null, null),
  (110, '009/MoU/PCU-ITB/V/2023',   'Kerja Sama Pendidikan dan Penelitian Nasional',      'MoU', 'active',   '2023-05-01', '2028-04-30', false, null, null, null, null),
  (111, '005/MoA/PCU-UGM/II/2025',  'Pengabdian Masyarakat Bersama',                     'MoA', 'active',   '2025-02-01', '2028-01-31', false, null, null, null, null),
  (112, '003/MoU/PCU-UNAIR/I/2024', 'Kerja Sama Tridharma Perguruan Tinggi',             'MoU', 'active',   '2024-01-15', '2029-01-14', false, null, null, null, null),
  (113, '016/MoU/PCU-NYP/VI/2025',  'Program Musim Panas Teknologi Manufaktur',          'MoU', 'active',   '2025-06-01', '2030-05-31', false, null, null, null, null),
  (114, '024/MoU/PCU-THU/IX/2025',  'Pertukaran Mahasiswa Manajemen',                    'MoU', 'active',   '2025-09-01', '2030-08-31', false, null, null, null, null),
  (116, '006/MoU/PCU-TELKOM/III/2024','Kerja Sama Industri dan Pendidikan',              'MoU', 'active',   '2024-03-01', '2029-02-28', false, null, null, null, null),
  (118, '001/MoU/PCU-SAXION/I/2018','Kerja Sama Pendidikan (berakhir)',                  'MoU', 'archived', '2018-01-01', '2023-12-31', false, null, null, 'expired', null),
  (119, '012/MoU/PCU-SAXION/I/2021','Kerja Sama Riset Terapan (diakhiri)',               'MoU', 'archived', '2021-01-01', '2026-12-31', false, null, null, 'terminated', '2025-06-30 10:00+07'),
  (901, '031/MoU/PCU-CU/VI/2026',   'Kerja Sama Teknik dan Inovasi (baru)',              'MoU', 'active',   '2026-06-15', '2031-06-14', false, null, null, null, null),
  (902, '044/MoA/PCU-USTUTT/XII/2026','Program Riset Bersama Otomotif',                  'MoA', 'active',   '2026-12-02', '2029-12-01', false, null, null, null, null),
  (903, '002/MoU/PCU-UKDW/I/2020',  'Kerja Sama Pendidikan Seni (perpanjangan otomatis)','MoU', 'active',   '2020-01-15', '2022-01-14', true,  null, null, null, null),
  (904, '018/MoU/PCU-OU/IX/2023',   'Kerja Sama Riset Material Maju',                    'MoU', 'archived', '2023-09-01', '2026-03-31', false, null, null, 'renewed', null),
  (906, '052/MoU/PCU-SAXION/IX/2026','Kerja Sama Pendidikan (dalam proses)',             'MoU', 'in_process','2026-09-01', '2031-08-31', false, null, null, null, null),
  (907, '049/MoU/PCU-SAXION/VIII/2026','Kerja Sama Pendidikan (ditolak)',                'MoU', 'rejected', '2026-08-01', '2031-07-31', false, null, null, null, null)
on conflict (id) do update set doc_number = excluded.doc_number, title = excluded.title, kind = excluded.kind, status = excluded.status,
  start_date = excluded.start_date, end_date = excluded.end_date, auto_renewed = excluded.auto_renewed,
  predecessor_id = excluded.predecessor_id, parent_id = excluded.parent_id, archived_reason = excluded.archived_reason,
  terminated_at = excluded.terminated_at;

insert into public.documents (id, doc_number, title, kind, status, start_date, end_date, auto_renewed, predecessor_id, parent_id, archived_reason, terminated_at) values
  (115, '010/MoA/PCU-KIT/IV/2025',  'Program Gelar Ganda Teknik Elektro (di bawah MoU 101)', 'MoA', 'active', '2025-04-01', '2027-03-31', false, null, 101, null, null),
  (117, '025/MoA/PCU-TELKOM/X/2025','Seminar dan Magang Industri (di bawah MoU 116)',      'MoA', 'active', '2025-10-01', '2027-09-30', false, null, 116, null, null),
  (905, '015/MoU/PCU-OU/IV/2026',   'Kerja Sama Riset Material Maju (perpanjangan)',       'MoU', 'active', '2026-04-01', '2031-03-31', false, 904, null, null, null)
on conflict (id) do update set doc_number = excluded.doc_number, title = excluded.title, kind = excluded.kind, status = excluded.status,
  start_date = excluded.start_date, end_date = excluded.end_date, auto_renewed = excluded.auto_renewed,
  predecessor_id = excluded.predecessor_id, parent_id = excluded.parent_id, archived_reason = excluded.archived_reason,
  terminated_at = excluded.terminated_at;

insert into public.document_partners (document_id, partner_id, is_lead) values
  (101, 1, true), (102, 2, true), (103, 3, true), (104, 4, true), (105, 5, true), (106, 6, true), (107, 7, true),
  (108, 8, true), (109, 9, true), (110, 11, true), (111, 10, true), (112, 12, true), (113, 13, true), (114, 15, true),
  (115, 1, true), (116, 16, true), (117, 16, true), (118, 20, true), (119, 20, true),
  (901, 17, true), (902, 18, true), (903, 19, true), (904, 14, true), (905, 14, true), (906, 20, true), (907, 20, true)
on conflict (document_id, partner_id) do update set is_lead = excluded.is_lead;

insert into public.document_scope_units (document_id, unit_id) values
  (101, 10), (101, 11), (101, 12), (102, 20), (102, 21), (103, 11), (103, 30), (104, 12), (105, 20),
  (106, 30), (106, 31), (107, 10), (108, 20), (108, 30), (109, 30), (110, 10), (110, 30), (111, 21),
  (112, 20), (112, 21), (113, 10), (113, 11), (114, 20), (115, 10), (115, 12), (116, 21), (117, 21),
  (118, 20), (119, 10), (901, 10), (902, 20), (903, 30), (904, 10), (905, 10), (906, 10), (907, 10)
on conflict do nothing;

insert into public.profiles (id, email, display_name, app_role, unit_id) values
  ('00000000-0000-4000-8000-000000000001', 'kepala.io@demo.petra.ac.id',           'Kepala IO',                       'io_admin',  2),
  ('00000000-0000-4000-8000-000000000002', 'io.partnership@demo.petra.ac.id',      'IO Partnership',                  'io_staff',  2),
  ('00000000-0000-4000-8000-000000000003', 'io.mobility@demo.petra.ac.id',         'IO Mobility',                     'io_staff',  2),
  ('00000000-0000-4000-8000-000000000004', 'ua-fti@demo.petra.ac.id',              'UA Fakultas Teknologi Industri',  'submitter', 10),
  ('00000000-0000-4000-8000-000000000005', 'ua-fbe@demo.petra.ac.id',              'UA Fakultas Bisnis & Ekonomi',    'submitter', 20),
  ('00000000-0000-4000-8000-000000000006', 'kaprodi-informatika@demo.petra.ac.id', 'Kaprodi Informatika',             'submitter', 11),
  ('00000000-0000-4000-8000-000000000007', 'ua-fsd@demo.petra.ac.id',              'UA Fakultas Seni & Desain',       'submitter', 30),
  ('00000000-0000-4000-8000-000000000008', 'rektorat@demo.petra.ac.id',            'Rektorat',                        'viewer',    1)
on conflict (id) do update set email = excluded.email, display_name = excluded.display_name, app_role = excluded.app_role,
  unit_id = excluded.unit_id;
