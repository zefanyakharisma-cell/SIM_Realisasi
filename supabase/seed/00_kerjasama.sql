-- 00_kerjasama (LOCAL ONLY): demo fixtures written into the SIMKS-shaped stub tables (supabase/local/00_simks_stub.sql),
-- read by Realisasi through the kerjasama.* adapter views, plus the Realisasi-owned rows that go with them
-- (realisasi.account_roles, realisasi.team_members, realisasi.document_overrides). Same ids/semantics as the former
-- public.* stubs (CONTRACTS §5.3). Proposal ids are deliberately different from document numbers (proposal = no + 1000)
-- so the adapter's proposal-based joins are exercised. Idempotent.

insert into public.jenis_unit (id, jenis) values (1, 'Unit Akademik'), (2, 'Unit Pembantu')
on conflict (id) do update set jenis = excluded.jenis;

-- parents before children
insert into public.unit (id, nama, id_parent_unit, id_jenis_unit) values
  (1,  'Rektorat', null, 2),
  (2,  'International Office', null, 2),
  (10, 'Fakultas Teknologi Industri', null, 1),
  (20, 'Fakultas Bisnis & Ekonomi', null, 1),
  (30, 'Fakultas Seni & Desain', null, 1)
on conflict (id) do update set nama = excluded.nama, id_parent_unit = excluded.id_parent_unit, id_jenis_unit = excluded.id_jenis_unit;
insert into public.unit (id, nama, id_parent_unit, id_jenis_unit) values
  (11, 'Prodi Informatika', 10, 1),
  (12, 'Prodi Teknik Elektro', 10, 1),
  (21, 'Prodi Manajemen', 20, 1),
  (31, 'Prodi Desain Komunikasi Visual', 30, 1)
on conflict (id) do update set nama = excluded.nama, id_parent_unit = excluded.id_parent_unit, id_jenis_unit = excluded.id_jenis_unit;

-- SIMKS stores ISO alpha-3 codes; the adapter exposes alpha-2 (kerjasama.countries.code)
insert into public.negara (id, kode, nama, is_domestic) values
  (1, 'IDN', 'Indonesia', true), (2, 'JPN', 'Jepang', false), (3, 'KOR', 'Korea Selatan', false), (4, 'TWN', 'Taiwan', false),
  (5, 'DEU', 'Jerman', false), (6, 'NLD', 'Belanda', false), (7, 'AUS', 'Australia', false), (8, 'MYS', 'Malaysia', false),
  (9, 'THA', 'Thailand', false), (10, 'PHL', 'Filipina', false), (11, 'SGP', 'Singapura', false),
  (12, 'USA', 'Amerika Serikat', false), (13, 'CHN', 'Tiongkok', false), (14, 'FRA', 'Prancis', false),
  (15, 'GBR', 'Britania Raya', false)
on conflict (id) do update set kode = excluded.kode, nama = excluded.nama, is_domestic = excluded.is_domestic;

insert into public.partner (id, nama, is_international, id_negara) values
  (1,  'Kyoto Institute of Technology', true, 2),
  (2,  'Hanyang University', true, 3),
  (3,  'National Taiwan University of Science and Technology', true, 4),
  (4,  'Hochschule Bremen', true, 5),
  (5,  'Fontys University of Applied Sciences', true, 6),
  (6,  'The University of Queensland', true, 7),
  (7,  'Universiti Teknologi Malaysia', true, 8),
  (8,  'King Mongkut''s University of Technology Thonburi', true, 9),
  (9,  'De La Salle University', true, 10),
  (10, 'Universitas Gadjah Mada', false, 1),
  (11, 'Institut Teknologi Bandung', false, 1),
  (12, 'Universitas Airlangga', false, 1),
  (13, 'Nanyang Polytechnic', true, 11),
  (14, 'Osaka University', true, 2),
  (15, 'Tunghai University', true, 4),
  (16, 'PT Telkom Indonesia', false, 1),
  (17, 'Chulalongkorn University', true, 9),
  (18, 'Universität Stuttgart', true, 5),
  (19, 'Universitas Kristen Duta Wacana', false, 1),
  (20, 'Saxion University of Applied Sciences', true, 6)
on conflict (id) do update set nama = excluded.nama, is_international = excluded.is_international, id_negara = excluded.id_negara;

-- documents = proposal_dokumen (kind, purpose -> title, predecessor PROPOSAL) + dokumen_kerja_sama (number, dates, status)
-- d: (no, no_dokumen, title, kind, SIMKS status, alasan_arsip, start, end, predecessor no)
create temp table _docs (no int, no_dokumen text, title text, kind text, status text, alasan text, mulai date, berakhir date, prev_no int);
insert into _docs values
  (101, '011/MoU/PCU-KIT/III/2022',   'Kerja Sama Pendidikan dan Riset Teknik',               'MoU', 'Aktif', null, '2022-03-01', '2027-02-28', null),
  (102, '004/MoU/PCU-HYU/I/2023',     'Pertukaran Mahasiswa dan Staf Bisnis',                'MoU', 'Aktif', null, '2023-01-10', '2028-01-09', null),
  (103, '019/MoU/PCU-NTUST/II/2024',  'Kolaborasi Akademik Teknologi dan Desain',            'MoU', 'Aktif', null, '2024-02-01', '2029-01-31', null),
  (104, '027/MoA/PCU-HSB/IX/2024',    'Riset Bersama Energi Terbarukan',                     'MoA', 'Aktif', null, '2024-09-01', '2027-08-31', null),
  (105, '002/MoU/PCU-FONTYS/I/2025',  'Kerja Sama Pendidikan Bisnis Internasional',          'MoU', 'Aktif', null, '2025-01-15', '2030-01-14', null),
  (106, '014/MoU/PCU-UQ/V/2024',      'Kerja Sama Seni, Desain, dan Media',                  'MoU', 'Aktif', null, '2024-05-01', '2029-04-30', null),
  (107, '008/MoU/PCU-UTM/III/2025',   'Kolaborasi Riset Teknik Industri',                    'MoU', 'Aktif', null, '2025-03-01', '2030-02-28', null),
  (108, '021/MoA/PCU-KMUTT/VII/2025', 'Program Mobilitas Bisnis dan Desain',                 'MoA', 'Aktif', null, '2025-07-01', '2028-06-30', null),
  (109, '017/MoU/PCU-DLSU/VIII/2024', 'Pertukaran Mahasiswa Seni dan Humaniora',             'MoU', 'Aktif', null, '2024-08-01', '2029-07-31', null),
  (110, '009/MoU/PCU-ITB/V/2023',     'Kerja Sama Pendidikan dan Penelitian Nasional',       'MoU', 'Aktif', null, '2023-05-01', '2028-04-30', null),
  (111, '005/MoA/PCU-UGM/II/2025',    'Pengabdian Masyarakat Bersama',                       'MoA', 'Aktif', null, '2025-02-01', '2028-01-31', null),
  (112, '003/MoU/PCU-UNAIR/I/2024',   'Kerja Sama Tridharma Perguruan Tinggi',               'MoU', 'Aktif', null, '2024-01-15', '2029-01-14', null),
  (113, '016/MoU/PCU-NYP/VI/2025',    'Program Musim Panas Teknologi Manufaktur',            'MoU', 'Aktif', null, '2025-06-01', '2030-05-31', null),
  (114, '024/MoU/PCU-THU/IX/2025',    'Pertukaran Mahasiswa Manajemen',                      'MoU', 'Aktif', null, '2025-09-01', '2030-08-31', null),
  (115, '010/MoA/PCU-KIT/IV/2025',    'Program Gelar Ganda Teknik Elektro (di bawah MoU 101)', 'MoA', 'Akan Berakhir', null, '2025-04-01', '2027-03-31', null),
  (116, '006/MoU/PCU-TELKOM/III/2024','Kerja Sama Industri dan Pendidikan',                  'MoU', 'Aktif', null, '2024-03-01', '2029-02-28', null),
  (117, '025/MoA/PCU-TELKOM/X/2025',  'Seminar dan Magang Industri (di bawah MoU 116)',      'MoA', 'Aktif', null, '2025-10-01', '2027-09-30', null),
  (118, '001/MoU/PCU-SAXION/I/2018',  'Kerja Sama Pendidikan (berakhir)',                    'MoU', 'Diarsipkan', 'expired_without_renewal', '2018-01-01', '2023-12-31', null),
  -- 119: terminated early; SIMKS has no termination timestamp -> realisasi.document_overrides.terminated_at below
  (119, '012/MoU/PCU-SAXION/I/2021',  'Kerja Sama Riset Terapan (diakhiri)',                 'MoU', 'Diarsipkan', 'expired_without_renewal', '2021-01-01', '2026-12-31', null),
  (901, '031/MoU/PCU-CU/VI/2026',     'Kerja Sama Teknik dan Inovasi (baru)',                'MoU', 'Aktif', null, '2026-06-15', '2031-06-14', null),
  (902, '044/MoA/PCU-USTUTT/XII/2026','Program Riset Bersama Otomotif',                      'MoA', 'Aktif', null, '2026-12-02', '2029-12-01', null),
  -- 903: AT-06 auto-renewed; SIMKS has no auto-renew -> realisasi.document_overrides.auto_renewed below
  (903, '002/MoU/PCU-UKDW/I/2020',    'Kerja Sama Pendidikan Seni (perpanjangan otomatis)',  'MoU', 'Aktif', null, '2020-01-15', '2022-01-14', null),
  (904, '018/MoU/PCU-OU/IX/2023',     'Kerja Sama Riset Material Maju',                      'MoU', 'Diarsipkan', 'superseded_by_renewal', '2023-09-01', '2026-03-31', null),
  (905, '015/MoU/PCU-OU/IV/2026',     'Kerja Sama Riset Material Maju (perpanjangan)',       'MoU', 'Aktif', null, '2026-04-01', '2031-03-31', 904),
  -- 906: a dokumen row still in process (any SIMKS status other than Aktif/Akan Berakhir/Diarsipkan -> in_process)
  (906, '052/MoU/PCU-SAXION/IX/2026', 'Kerja Sama Pendidikan (dalam proses)',                'MoU', 'Dalam Proses', null, '2026-09-01', '2031-08-31', null),
  -- 907: rejected proposals in SIMKS are archived with alasan_arsip 'rejected', no number and no dates
  (907, null,                         'Kerja Sama Pendidikan (ditolak)',                     'MoU', 'Diarsipkan', 'rejected', null, null, null);

insert into public.proposal_dokumen (id, jenis_kerjasama, sifat_periode_kerjasama, status_proposal, tujuan_kerjasama, id_dokumen_sebelumnya)
select d.no + 1000, d.kind::public.jenis_kerjasama, 'Kedua Belah Pihak',
       case when d.alasan = 'rejected' then 'Ditolak' when d.status = 'Dalam Proses' then 'Siap TTD' else 'Disetujui' end,
       d.title, case when d.prev_no is not null then d.prev_no + 1000 end
  from _docs d
on conflict (id) do update set jenis_kerjasama = excluded.jenis_kerjasama, status_proposal = excluded.status_proposal,
  tujuan_kerjasama = excluded.tujuan_kerjasama, id_dokumen_sebelumnya = excluded.id_dokumen_sebelumnya;

insert into public.dokumen_kerja_sama (no, id_proposal_dokumen, no_dokumen, tanggal_mulai, tanggal_berakhir, status, alasan_arsip)
select d.no, d.no + 1000, d.no_dokumen, d.mulai, d.berakhir, d.status, d.alasan from _docs d
on conflict (no) do update set id_proposal_dokumen = excluded.id_proposal_dokumen, no_dokumen = excluded.no_dokumen,
  tanggal_mulai = excluded.tanggal_mulai, tanggal_berakhir = excluded.tanggal_berakhir, status = excluded.status,
  alasan_arsip = excluded.alasan_arsip;

-- partners / scope are keyed by PROPOSAL in SIMKS
insert into public.partner_pengusul (id_proposal_dokumen, id_partner, is_lead)
select no + 1000, partner, true from (values
  (101, 1), (102, 2), (103, 3), (104, 4), (105, 5), (106, 6), (107, 7), (108, 8), (109, 9), (110, 11), (111, 10), (112, 12),
  (113, 13), (114, 15), (115, 1), (116, 16), (117, 16), (118, 20), (119, 20),
  (901, 17), (902, 18), (903, 19), (904, 14), (905, 14), (906, 20), (907, 20)) x(no, partner)
on conflict (id_proposal_dokumen, id_partner) do update set is_lead = excluded.is_lead;

insert into public.proposal_dokumen_unit (id_proposal_dokumen, id_unit)
select no + 1000, unit from (values
  (101, 10), (101, 11), (101, 12), (102, 20), (102, 21), (103, 11), (103, 30), (104, 12), (105, 20),
  (106, 30), (106, 31), (107, 10), (108, 20), (108, 30), (109, 30), (110, 10), (110, 30), (111, 21),
  (112, 20), (112, 21), (113, 10), (113, 11), (114, 20), (115, 10), (115, 12), (116, 21), (117, 21),
  (118, 20), (119, 10), (901, 10), (902, 20), (903, 30), (904, 10), (905, 10), (906, 10), (907, 10)) x(no, unit)
on conflict do nothing;

-- Realisasi-only document facts (SIMKS has neither auto-renewal nor a termination timestamp)
insert into realisasi.document_overrides (document_id, auto_renewed, terminated_at, note) values
  (903, true,  null, 'AT-06: perpanjangan otomatis (fixture lokal)'),
  (119, false, '2025-06-30 10:00+07', 'Diakhiri lebih awal (fixture lokal)')
on conflict (document_id) do update set auto_renewed = excluded.auto_renewed, terminated_at = excluded.terminated_at, note = excluded.note;

-- Accounts: SIMKS jabatan + akun; the demo profile uuids are the akun's auth_user_id (Supabase Auth user id)
insert into public.jabatan (id, nama, id_unit) values
  (1, 'Kepala IO', 2), (2, 'IO Partnership', 2), (3, 'IO Mobility', 2),
  (4, 'UA Fakultas Teknologi Industri', 10), (5, 'UA Fakultas Bisnis & Ekonomi', 20), (6, 'Kaprodi Informatika', 11),
  (7, 'UA Fakultas Seni & Desain', 30), (8, 'Rektorat', 1), (9, 'Staf Sekretariat SIM Kerjasama', 2)
on conflict (id) do update set nama = excluded.nama, id_unit = excluded.id_unit;

insert into public.akun (id, auth_user_id, id_jabatan, email, role) values
  (1, '00000000-0000-4000-8000-000000000001', 1, 'kepala.io@demo.petra.ac.id',           'admin'),
  (2, '00000000-0000-4000-8000-000000000002', 2, 'io.partnership@demo.petra.ac.id',      'admin'),
  (3, '00000000-0000-4000-8000-000000000003', 3, 'io.mobility@demo.petra.ac.id',         'admin'),
  (4, '00000000-0000-4000-8000-000000000004', 4, 'ua-fti@demo.petra.ac.id',              'user_staff'),
  (5, '00000000-0000-4000-8000-000000000005', 5, 'ua-fbe@demo.petra.ac.id',              'user_staff'),
  (6, '00000000-0000-4000-8000-000000000006', 6, 'kaprodi-informatika@demo.petra.ac.id', 'user_staff'),
  (7, '00000000-0000-4000-8000-000000000007', 7, 'ua-fsd@demo.petra.ac.id',              'user_staff'),
  (8, '00000000-0000-4000-8000-000000000008', 8, 'rektorat@demo.petra.ac.id',            'approver'),
  -- a SIMKS-only account (no realisasi.account_roles row -> not a Realisasi user, not in kerjasama.profiles)
  (9, null,                                   9, 'sekretariat.simks@demo.petra.ac.id',   'user_staff')
on conflict (id) do update set auth_user_id = excluded.auth_user_id, id_jabatan = excluded.id_jabatan,
  email = excluded.email, role = excluded.role;

-- Every KUI/IO account is io_admin (all features unlocked)
insert into realisasi.account_roles (akun_id, app_role, unit_id) values
  (1, 'io_admin', null), (2, 'io_admin', null), (3, 'io_admin', null), (4, 'submitter', null), (5, 'submitter', null),
  (6, 'submitter', null), (7, 'submitter', null), (8, 'viewer', null)
on conflict (akun_id) do update set app_role = excluded.app_role, unit_id = excluded.unit_id;

-- Revisi V.1: one verification team (Mobility); every IO staff account is in it
insert into realisasi.team_members (account_id, team) values
  ('00000000-0000-4000-8000-000000000001', 'mobility'),
  ('00000000-0000-4000-8000-000000000002', 'mobility'), ('00000000-0000-4000-8000-000000000003', 'mobility')
on conflict do nothing;
