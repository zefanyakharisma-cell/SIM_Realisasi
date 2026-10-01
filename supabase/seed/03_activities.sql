-- 03_activities: scenarios S-01…S-30 (+S-15b = 31, S-20b = 32). Idempotent: every helper skips existing rows.
-- Historical scenarios use fixed dates (< 2026-10-01); SLA/revision clocks are relative to realisasi.today() at seed time.

create or replace function pg_temp.aid(n int) returns uuid language sql immutable as $$
  select ('a0000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.gid(n int) returns uuid language sql immutable as $$
  select ('e0000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.pdf() returns bytea language sql immutable as $$
  select decode('255044462d312e340a312030206f626a0a3c3c2f547970652f436174616c6f672f50616765732032203020523e3e0a656e646f626a0a322030206f626a0a3c3c2f547970652f50616765732f4b6964735b33203020525d2f436f756e7420313e3e0a656e646f626a0a332030206f626a0a3c3c2f547970652f506167652f506172656e742032203020522f4d65646961426f785b30203020323030203230305d2f436f6e74656e74732034203020522f5265736f75726365733c3c3e3e3e3e0a656e646f626a0a342030206f626a0a3c3c2f4c656e67746820303e3e73747265616d0a0a656e6473747265616d0a656e646f626a0a787265660a3020350a303030303030303030302036353533352066200a30303030303030303039203030303030206e200a30303030303030303534203030303030206e200a30303030303030313035203030303030206e200a30303030303030313939203030303030206e200a747261696c65720a3c3c2f53697a6520352f526f6f742031203020523e3e0a7374617274787265660a3234350a2525454f460a', 'hex') $$;
create or replace function pg_temp.wib(d date, t time default '09:00') returns timestamptz language sql immutable as $$
  select (d + t) at time zone 'Asia/Jakarta' $$;
-- start (08:00 WIB) of the date n business days before today()
create or replace function pg_temp.bd(n int, t time default '08:00') returns timestamptz language sql stable as $$
  select (realisasi._business_days_ago(n) + t) at time zone 'Asia/Jakarta' $$;
create or replace function pg_temp.daysago(n int, t time default '09:00') returns timestamptz language sql stable as $$
  select ((realisasi.today() - n) + t) at time zone 'Asia/Jakarta' $$;

create or replace function pg_temp.blob(p_path text, p_by uuid, p_at timestamptz) returns void language sql as $$
  insert into realisasi.file_blobs (path, bucket, data, mime, size_bytes, created_by, created_at)
  values (p_path, split_part(p_path, '/', 1), pg_temp.pdf(), 'application/pdf', length(pg_temp.pdf()), p_by, p_at)
  on conflict (path) do nothing $$;

create or replace function pg_temp.log(p_n int, p_kind text, p_track text, p_action text, p_actor uuid, p_at timestamptz,
                                       p_note text default null, p_diff jsonb default null, p_frozen boolean default false)
returns void language sql as $$
  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (pg_temp.aid(p_n), p_kind::realisasi.log_kind, p_track::realisasi.team, p_action, p_actor, p_note, p_diff, p_frozen, p_at) $$;

create or replace function pg_temp.seed_act(
  p_n int, p_name text, p_unit int, p_type int, p_start date, p_end date, p_mode text, p_venue text, p_city text,
  p_country text, p_docs int[], p_sdgs int[], p_submitted timestamptz, p_verified timestamptz,
  p_pstatus text, p_mstatus text, p_psince timestamptz, p_msince timestamptz,
  p_group int default null, p_files text[] default '{ia,ir}', p_pnote text default null, p_mnote text default null,
  p_reason text default null, p_ext jsonb default '[]')
returns void language plpgsql as $$
declare v_id uuid := pg_temp.aid(p_n); v_g uuid := pg_temp.gid(coalesce(p_group, p_n)); v_code text := 'RL-2026-' || lpad(p_n::text, 4, '0');
        v_creator uuid; v_created timestamptz; k text; v_path text; e jsonb;
        c_part uuid := '00000000-0000-4000-8000-000000000002'; c_mob uuid := '00000000-0000-4000-8000-000000000003';
begin
  if exists (select 1 from realisasi.activities where id = v_id) then return; end if;
  v_creator := coalesce((select id from public.profiles where app_role = 'submitter' and unit_id = p_unit order by id limit 1),
                        '00000000-0000-4000-8000-000000000001');
  v_created := coalesce(p_submitted, pg_temp.wib(p_end)) - interval '3 days';
  insert into realisasi.event_groups (id, created_by, created_at) values (v_g, v_creator, v_created) on conflict do nothing;
  insert into realisasi.activities (id, code, name, type_id, start_date, end_date, mode, venue, city, country_code, sks_recognized,
              funding_source, description, submitter_unit_id, created_by, submitted_at, verified_at, partnership_status,
              mobility_status, partnership_since, mobility_since, rejection_reason, event_group_id, created_at)
  values (v_id, v_code, p_name, p_type, p_start, p_end, p_mode::realisasi.activity_mode, p_venue, p_city, p_country,
          case when p_type in (1, 7) then 3 end, case when p_type in (1, 2, 7) then 'mixed' else 'pcu' end::realisasi.funding_source,
          'Kegiatan "' || p_name || '" dalam rangka implementasi kerja sama dengan mitra.', p_unit, v_creator, p_submitted,
          p_verified, p_pstatus::realisasi.track_status, p_mstatus::realisasi.track_status,
          coalesce(p_psince, v_created), coalesce(p_msince, p_psince, v_created), p_reason, v_g, v_created);
  insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, p_unit, true);
  insert into realisasi.activity_documents (activity_id, original_document_id, out_of_scope_warning)
  select v_id, d, not exists (select 1 from public.document_scope_units su where su.document_id = d and su.unit_id = p_unit)
    from unnest(p_docs) d;
  insert into realisasi.activity_sdgs (activity_id, sdg_id) select v_id, s from unnest(p_sdgs) s;
  for e in select * from jsonb_array_elements(p_ext) loop
    insert into realisasi.activity_external_persons (activity_id, full_name, institution, country_code, role, notes)
    values (v_id, e ->> 'full_name', e ->> 'institution', e ->> 'country_code', (e ->> 'role')::realisasi.person_role, e ->> 'notes');
  end loop;
  foreach k in array p_files loop
    v_path := 'realisasi-files/' || v_id || '/' || k || '/' || md5(v_id::text || k)::uuid || '.pdf';
    perform pg_temp.blob(v_path, v_creator, v_created + interval '1 day');
    insert into realisasi.activity_files (activity_id, kind, version, storage_path, filename, size_bytes, mime, is_current, uploaded_by, uploaded_at)
    values (v_id, k::realisasi.file_kind, 1, v_path, upper(k) || '_' || v_code || '.pdf', length(pg_temp.pdf()), 'application/pdf',
            true, v_creator, v_created + interval '1 day');
  end loop;

  perform pg_temp.log(p_n, 'system', null, 'create', v_creator, v_created);
  if p_submitted is null then return; end if;
  perform pg_temp.log(p_n, 'system', null, 'submit', v_creator, p_submitted);
  if p_pstatus = 'approved' then perform pg_temp.log(p_n, 'verification', 'partnership', 'approve', c_part, p_psince); end if;
  if p_pstatus = 'revision_requested' then perform pg_temp.log(p_n, 'verification', 'partnership', 'request_revision', c_part, p_psince, p_pnote); end if;
  if p_pstatus = 'rejected' then
    perform pg_temp.log(p_n, 'verification', 'partnership', 'reject', c_part, p_psince, p_pnote, jsonb_build_object('reason', p_reason));
  end if;
  if p_mstatus = 'approved' then perform pg_temp.log(p_n, 'verification', 'mobility', 'approve', c_mob, p_msince, null, '{"version":1}'); end if;
  if p_mstatus = 'revision_requested' then perform pg_temp.log(p_n, 'verification', 'mobility', 'request_revision', c_mob, p_msince, p_mnote); end if;
end $$;

create or replace function pg_temp.seed_pset(p_n int, p_ver int, p_status text, p_internal text[], p_inbound text[], p_staff text[],
  p_submitted timestamptz, p_reviewed timestamptz default null, p_note text default null, p_row_notes jsonb default '{}')
returns void language plpgsql as $$
declare v_act uuid := pg_temp.aid(p_n); v_id uuid := md5(pg_temp.aid(p_n)::text || ':v' || p_ver)::uuid; v_by uuid; n text; v_path text;
begin
  if exists (select 1 from realisasi.participant_set_versions where id = v_id) then return; end if;
  select created_by into v_by from realisasi.activities where id = v_act;
  insert into realisasi.participant_set_versions (id, activity_id, version, status, submitted_by, submitted_at, reviewed_by, reviewed_at, review_note)
  values (v_id, v_act, p_ver, p_status::realisasi.pset_status, v_by, p_submitted,
          case when p_reviewed is not null then '00000000-0000-4000-8000-000000000003'::uuid end, p_reviewed, p_note);
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name, row_note)
  select v_id, 'internal', s.nrp, s.full_name, s.faculty_name, s.prodi_name, p_row_notes ->> s.nrp
    from unnest(p_internal) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  foreach n in array p_inbound loop
    v_path := 'realisasi-transcripts/' || v_act || '/v' || p_ver || '/' || n || '-' || left(md5(v_act::text || n), 8) || '.pdf';
    perform pg_temp.blob(v_path, v_by, p_submitted - interval '1 day');
    insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
                home_institution, home_student_number, home_country_code, transcript_path, row_note)
    select v_id, 'inbound', s.nrp, s.full_name, s.faculty_name, s.prodi_name, s.home_institution,
           'HS-' || right(s.nrp, 4), s.home_country_code, v_path, p_row_notes ->> s.nrp
      from mock_baak.students s where s.nrp = n;
  end loop;
  insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name, row_note)
  select v_id, e.employee_id, e.full_name, e.unit_name, p_row_notes ->> e.employee_id
    from unnest(p_staff) with ordinality x(id, o) join mock_hr.employees e on e.employee_id = x.id order by o;
end $$;

-- ---------------------------------------------------------------------------------------------
-- AY 2025/2026 Ganjil
select pg_temp.seed_act(1, 'Student Exchange Semester Ganjil di Hanyang University', 20, 1, '2025-09-01', '2025-12-19', 'offline',
  'Hanyang University Seoul Campus', 'Seoul', 'KR', '{102}', '{4,17}', pg_temp.wib('2025-12-22'), pg_temp.wib('2026-01-08', '14:00'),
  'approved', 'approved', pg_temp.wib('2026-01-05'), pg_temp.wib('2026-01-08', '14:00'));
select pg_temp.seed_pset(1, 1, 'approved', '{D31238836,D31239872,D32233592,D31242651}', '{}', '{PG217839}',
  pg_temp.wib('2025-12-22'), pg_temp.wib('2026-01-08', '14:00'));

select pg_temp.seed_act(2, 'Inbound Exchange Kyoto Institute of Technology 2025', 10, 2, '2025-08-25', '2025-12-12', 'offline',
  'Kampus PCU Siwalankerto', 'Surabaya', 'ID', '{101}', '{4}', pg_temp.wib('2025-12-15'), pg_temp.wib('2026-01-05', '15:00'),
  'approved', 'approved', pg_temp.wib('2025-12-18'), pg_temp.wib('2026-01-05', '15:00'));
select pg_temp.seed_pset(2, 1, 'approved', '{}', '{X01250003,X01250017,X01250024}', '{}', pg_temp.wib('2025-12-15'), pg_temp.wib('2026-01-05', '15:00'));

select pg_temp.seed_act(5, 'Seminar Nasional Desain dan Budaya bersama ITB', 30, 6, '2025-11-03', '2025-11-04', 'offline',
  'Auditorium PCU', 'Surabaya', 'ID', '{110}', '{4,11}', pg_temp.wib('2025-11-10'), pg_temp.wib('2025-11-14', '10:00'),
  'approved', 'not_required', pg_temp.wib('2025-11-14', '10:00'), pg_temp.wib('2025-11-10'));
-- S-05: post-freeze edit by IO Partnership (activity inside the frozen Ganjil 2025/2026 window)
select pg_temp.log(5, 'update', 'partnership', 'edit', '00000000-0000-4000-8000-000000000002', pg_temp.wib('2026-05-10', '10:30'),
  'Koreksi lokasi sesuai laporan akhir.', '{"venue": ["Auditorium PCU", "Auditorium Gedung W PCU"]}', true)
 where not exists (select 1 from realisasi.activity_log where activity_id = pg_temp.aid(5) and action = 'edit');
update realisasi.activities set venue = 'Auditorium Gedung W PCU' where id = pg_temp.aid(5) and venue = 'Auditorium PCU';

select pg_temp.seed_act(20, 'Riset Bersama Material Komposit dengan Osaka University', 10, 5, '2025-10-06', '2025-10-10', 'offline',
  'Osaka University Suita Campus', 'Osaka', 'JP', '{904}', '{9}', pg_temp.wib('2025-10-20'), pg_temp.wib('2025-10-24', '11:00'),
  'approved', 'not_required', pg_temp.wib('2025-10-24', '11:00'), pg_temp.wib('2025-10-20'));

-- S-19: Ganjil 2025/2026 activity, submitted late and verified after the Ganjil freeze
select pg_temp.seed_act(19, 'Kuliah Tamu Desain Interaksi dari The University of Queensland', 30, 4, '2025-11-10', '2025-11-14', 'hybrid',
  'Gedung P PCU', 'Surabaya', 'ID', '{106}', '{4}', pg_temp.wib('2026-03-20'), pg_temp.wib('2026-04-15', '10:00'),
  'approved', 'not_required', pg_temp.wib('2026-04-15', '10:00'), pg_temp.wib('2026-03-20'),
  p_ext => '[{"full_name":"Dr. Emily Carter","institution":"The University of Queensland","country_code":"AU","role":"visiting_lecturer"}]');

-- AY 2025/2026 Genap
select pg_temp.seed_act(3, 'Winter Program Smart Computing di NTUST', 11, 7, '2026-02-09', '2026-02-27', 'offline',
  'NTUST Main Campus', 'Taipei', 'TW', '{103}', '{4,9}', pg_temp.wib('2026-03-05'), pg_temp.wib('2026-03-12', '14:00'),
  'approved', 'approved', pg_temp.wib('2026-03-09'), pg_temp.wib('2026-03-12', '14:00'));
select pg_temp.seed_pset(3, 1, 'approved', '{B11252003,B11256252,B11257273,B11240422,B11244167}', '{}', '{PG190875}',
  pg_temp.wib('2026-03-05'), pg_temp.wib('2026-03-12', '14:00'));

select pg_temp.seed_act(4, 'Inbound Exchange Fontys Business School 2026', 20, 2, '2026-02-02', '2026-06-26', 'offline',
  'Kampus PCU Siwalankerto', 'Surabaya', 'ID', '{105}', '{4,8}', pg_temp.wib('2026-07-01'), pg_temp.wib('2026-07-08', '14:00'),
  'approved', 'approved', pg_temp.wib('2026-07-03'), pg_temp.wib('2026-07-08', '14:00'));
select pg_temp.seed_pset(4, 1, 'approved', '{}', '{X02250056,X02250063}', '{}', pg_temp.wib('2026-07-01'), pg_temp.wib('2026-07-08', '14:00'));

select pg_temp.seed_act(6, 'Riset Bersama Sistem Energi Terbarukan dengan Hochschule Bremen', 12, 5, '2026-03-02', '2026-07-31', 'hybrid',
  'Lab Konversi Energi PCU', 'Surabaya', 'ID', '{104}', '{7,13}', pg_temp.wib('2026-08-05'), pg_temp.wib('2026-08-12', '10:00'),
  'approved', 'not_required', pg_temp.wib('2026-08-12', '10:00'), pg_temp.wib('2026-08-05'));

select pg_temp.seed_act(7, 'Visiting Lecturer Media Kreatif dari The University of Queensland', 30, 4, '2026-04-13', '2026-04-17', 'offline',
  'Gedung P PCU', 'Surabaya', 'ID', '{106}', '{4}', pg_temp.wib('2026-04-24'), pg_temp.wib('2026-04-30', '10:00'),
  'approved', 'not_required', pg_temp.wib('2026-04-30', '10:00'), pg_temp.wib('2026-04-24'),
  p_ext => '[{"full_name":"Prof. Liam Walsh","institution":"The University of Queensland","country_code":"AU","role":"visiting_lecturer"}]');

select pg_temp.seed_act(8, 'Pengabdian Masyarakat Penguatan UMKM bersama UGM', 21, 8, '2026-06-08', '2026-06-12', 'offline',
  'Desa Wisata Kandangan', 'Kediri', 'ID', '{111}', '{1,8}', pg_temp.wib('2026-06-20'), pg_temp.wib('2026-06-26', '10:00'),
  'approved', 'not_required', pg_temp.wib('2026-06-26', '10:00'), pg_temp.wib('2026-06-20'));

-- S-15a / S-15b: D31240187 in two different outbound events (AT-02)
select pg_temp.seed_act(15, 'Student Exchange Semester Genap di Hanyang University', 20, 1, '2026-02-10', '2026-03-20', 'offline',
  'Hanyang University Seoul Campus', 'Seoul', 'KR', '{102}', '{4}', pg_temp.wib('2026-03-27'), pg_temp.wib('2026-04-06', '14:00'),
  'approved', 'approved', pg_temp.wib('2026-03-31'), pg_temp.wib('2026-04-06', '14:00'));
select pg_temp.seed_pset(15, 1, 'approved', '{D31240187,D31245931,D32237864}', '{}', '{}', pg_temp.wib('2026-03-27'), pg_temp.wib('2026-04-06', '14:00'));

select pg_temp.seed_act(31, 'Short Course Manajemen Internasional di Tunghai University', 20, 1, '2026-05-04', '2026-06-12', 'offline',
  'Tunghai University', 'Taichung', 'TW', '{114}', '{4,17}', pg_temp.wib('2026-06-18'), pg_temp.wib('2026-06-29', '14:00'),
  'approved', 'approved', pg_temp.wib('2026-06-22'), pg_temp.wib('2026-06-29', '14:00'));
select pg_temp.seed_pset(31, 1, 'approved', '{D31240187,D31246584}', '{}', '{}', pg_temp.wib('2026-06-18'), pg_temp.wib('2026-06-29', '14:00'));

-- S-20b: activity on the renewal (905) of S-20's agreement (904)
select pg_temp.seed_act(32, 'Riset Bersama Material Komposit Tahap II dengan Osaka University', 10, 5, '2026-05-11', '2026-05-15', 'online',
  'Zoom Meeting', null, null, '{905}', '{9}', pg_temp.wib('2026-05-22'), pg_temp.wib('2026-05-29', '10:00'),
  'approved', 'not_required', pg_temp.wib('2026-05-29', '10:00'), pg_temp.wib('2026-05-22'));

-- S-21: two agreements, partners in two countries
select pg_temp.seed_act(21, 'Konferensi Internasional Desain Asia Pasifik', 30, 6, '2026-03-23', '2026-03-24', 'offline',
  'Gedung W PCU', 'Surabaya', 'ID', '{103,108}', '{4,17}', pg_temp.wib('2026-04-02'), pg_temp.wib('2026-04-09', '10:00'),
  'approved', 'not_required', pg_temp.wib('2026-04-09', '10:00'), pg_temp.wib('2026-04-02'),
  p_ext => '[{"full_name":"Dr. Wei-Lun Chang","institution":"National Taiwan University of Science and Technology","country_code":"TW","role":"speaker"},{"full_name":"Asst. Prof. Nattapong Chaiyasit","institution":"King Mongkut''s University of Technology Thonburi","country_code":"TH","role":"speaker"}]');

-- S-24: late submission
select pg_temp.seed_act(24, 'Seminar Teknologi Manufaktur bersama UTM', 10, 6, '2026-06-22', '2026-07-01', 'hybrid',
  'Gedung T PCU', 'Surabaya', 'ID', '{107}', '{9}', pg_temp.wib('2026-08-20'), pg_temp.wib('2026-08-28', '10:00'),
  'approved', 'not_required', pg_temp.wib('2026-08-28', '10:00'), pg_temp.wib('2026-08-20'));

-- AY 2026/2027 Ganjil (verified)
select pg_temp.seed_act(9, 'Riset Bersama Optimasi Rantai Pasok dengan UTM', 10, 5, '2026-08-10', '2026-09-25', 'hybrid',
  'Lab Sistem Industri PCU', 'Surabaya', 'ID', '{107}', '{9,12}', pg_temp.wib('2026-09-28'), pg_temp.wib('2026-09-30', '10:00'),
  'approved', 'not_required', pg_temp.wib('2026-09-30', '10:00'), pg_temp.wib('2026-09-28'));

select pg_temp.seed_act(10, 'Student Exchange Bisnis Digital di KMUTT', 20, 1, '2026-08-03', '2026-09-18', 'offline',
  'KMUTT Bang Mod Campus', 'Bangkok', 'TH', '{108}', '{4,8}', pg_temp.wib('2026-09-21'), pg_temp.wib('2026-09-25', '14:00'),
  'approved', 'approved', pg_temp.wib('2026-09-23'), pg_temp.wib('2026-09-25', '14:00'));
select pg_temp.seed_pset(10, 1, 'approved', '{D31252983,D32250736,D31243593}', '{}', '{}', pg_temp.wib('2026-09-21'), pg_temp.wib('2026-09-25', '14:00'));

select pg_temp.seed_act(11, 'Inbound Exchange Desain Kreatif Asia Tenggara 2026', 30, 2, '2026-08-10', '2026-09-11', 'offline',
  'Kampus PCU Siwalankerto', 'Surabaya', 'ID', '{109}', '{4,10}', pg_temp.wib('2026-09-14'), pg_temp.wib('2026-09-18', '14:00'),
  'approved', 'approved', pg_temp.wib('2026-09-16'), pg_temp.wib('2026-09-18', '14:00'));
select pg_temp.seed_pset(11, 1, 'approved', '{}', '{X01260012,X01260044,X01260051,X01260068}', '{}', pg_temp.wib('2026-09-14'), pg_temp.wib('2026-09-18', '14:00'));

select pg_temp.seed_act(12, 'Seminar Industri Telekomunikasi bersama Telkom', 21, 6, '2026-09-14', '2026-09-15', 'offline',
  'Auditorium PCU', 'Surabaya', 'ID', '{117}', '{9}', pg_temp.wib('2026-09-17'), pg_temp.wib('2026-09-22', '10:00'),
  'approved', 'not_required', pg_temp.wib('2026-09-22', '10:00'), pg_temp.wib('2026-09-17'));

-- S-13 / S-14: same summer program claimed by FTI and Prodi Informatika, linked into event group …13 (AT-01)
select pg_temp.seed_act(13, 'Summer Program Smart Manufacturing di Nanyang Polytechnic', 10, 7, '2026-08-03', '2026-08-21', 'offline',
  'Nanyang Polytechnic', 'Singapura', 'SG', '{113}', '{4,9}', pg_temp.wib('2026-08-28'), pg_temp.wib('2026-09-10', '14:00'),
  'approved', 'approved', pg_temp.wib('2026-09-04'), pg_temp.wib('2026-09-10', '14:00'));
select pg_temp.seed_pset(13, 1, 'approved',
  '{B11227366,B11234310,B11235580,B11235901,B11237182,B11238623,B11240422,B11244167,B12222426,B12223137,B12229323,B12249536}',
  '{}', '{PG707752}', pg_temp.wib('2026-08-28'), pg_temp.wib('2026-09-10', '14:00'));
select pg_temp.seed_act(14, 'Summer Program Smart Manufacturing Nanyang Polytechnic 2026', 11, 7, '2026-08-03', '2026-08-21', 'offline',
  'Nanyang Polytechnic', 'Singapura', 'SG', '{113}', '{4,9}', pg_temp.wib('2026-08-29'), pg_temp.wib('2026-09-12', '14:00'),
  'approved', 'approved', pg_temp.wib('2026-09-07'), pg_temp.wib('2026-09-12', '14:00'), p_group => 13);
select pg_temp.seed_pset(14, 1, 'approved',
  '{B11227366,B11234310,B11235580,B11235901,B11237182,B11238623,B11240422,B11244167,B12222426,B12223137,B12229323,B12249536}',
  '{}', '{}', pg_temp.wib('2026-08-29'), pg_temp.wib('2026-09-12', '14:00'));
insert into realisasi.duplicate_candidates (activity_a, activity_b, score, status, resolved_by, resolved_at)
select least(pg_temp.aid(13), pg_temp.aid(14)), greatest(pg_temp.aid(13), pg_temp.aid(14)),
       round(similarity(lower(a.name), lower(b.name))::numeric, 2), 'linked', '00000000-0000-4000-8000-000000000002',
       pg_temp.wib('2026-09-07', '10:00')
  from realisasi.activities a, realisasi.activities b where a.id = pg_temp.aid(13) and b.id = pg_temp.aid(14)
on conflict (activity_a, activity_b) do nothing;
select pg_temp.log(n, 'verification', 'partnership', 'link_duplicate', '00000000-0000-4000-8000-000000000002', pg_temp.wib('2026-09-07', '10:00'),
                   'Program yang sama diajukan oleh FTI dan Prodi Informatika.',
                   jsonb_build_object('event_group_id', pg_temp.gid(13), 'moved', jsonb_build_array(pg_temp.aid(14))))
  from unnest(array[13, 14]) n
 where not exists (select 1 from realisasi.activity_log where activity_id = pg_temp.aid(n) and action = 'link_duplicate');

-- S-16: Partnership approved, Mobility revision requested 15 days ago (AT-03)
select pg_temp.seed_act(16, 'Student Exchange Teknik di Kyoto Institute of Technology', 10, 1, '2026-08-24', '2026-09-04', 'offline',
  'Kyoto Institute of Technology', 'Kyoto', 'JP', '{101}', '{4}', pg_temp.daysago(17), null,
  'approved', 'revision_requested', pg_temp.daysago(16, '10:00'), pg_temp.daysago(15, '09:00'),
  p_mnote => 'Satu NRP tidak sesuai surat tugas; mohon perbarui data peserta.');
select pg_temp.seed_pset(16, 1, 'revision_requested', '{B12251882,B12252182,B12254341}', '{}', '{}',
  pg_temp.daysago(17), pg_temp.daysago(15, '09:00'), 'Satu NRP tidak sesuai surat tugas; mohon perbarui data peserta.',
  '{"B12254341": "NRP tidak tercantum pada surat tugas."}');

-- S-17: Partnership revision on the wrong IA file, 8 days ago (AT-04)
select pg_temp.seed_act(17, 'Joint Seminar Pemasaran Digital Asia', 20, 6, '2026-09-07', '2026-09-08', 'offline',
  'Gedung T PCU', 'Surabaya', 'ID', '{102}', '{8}', pg_temp.daysago(10), null,
  'revision_requested', 'not_required', pg_temp.daysago(8, '10:00'), pg_temp.daysago(10),
  p_pnote => 'IA yang diunggah salah');

-- S-18: rejected as duplicate
select pg_temp.seed_act(18, 'Summer Program Smart Manufacturing - Nanyang Poly', 11, 7, '2026-08-03', '2026-08-20', 'offline',
  'Nanyang Polytechnic', 'Singapura', 'SG', '{113}', '{4}', pg_temp.wib('2026-08-30'), null,
  'rejected', 'pending', pg_temp.wib('2026-09-03', '10:00'), pg_temp.wib('2026-08-30'),
  p_pnote => 'Duplikat dari RL-2026-0014 yang sudah diajukan.', p_reason => 'duplicate');
select pg_temp.seed_pset(18, 1, 'pending', '{B11227366,B11234310}', '{}', '{}', pg_temp.wib('2026-08-30'));

-- S-22: unit outside the agreement scope (out_of_scope_warning)
select pg_temp.seed_act(22, 'Pengabdian Masyarakat Literasi Keuangan Desa', 20, 8, '2026-08-17', '2026-08-21', 'offline',
  'Desa Sumberejo', 'Pasuruan', 'ID', '{111}', '{1,4}', pg_temp.wib('2026-08-26'), pg_temp.wib('2026-09-02', '10:00'),
  'approved', 'not_required', pg_temp.wib('2026-09-02', '10:00'), pg_temp.wib('2026-08-26'));

-- S-23: draft past its reporting deadline (2026-09-13), only IA uploaded
select pg_temp.seed_act(23, 'Kuliah Tamu Ilustrasi Digital', 30, 4, '2026-08-12', '2026-08-14', 'online',
  'Zoom Meeting', null, null, '{106}', '{4}', null, null, 'pending', 'not_required', null, null, p_files => '{ia}');

-- S-25…S-30: in verification with SLA clocks relative to today()
select pg_temp.seed_act(25, 'Seminar Nasional Manajemen Rantai Pasok', 21, 6, '2026-09-21', '2026-09-22', 'offline',
  'Auditorium PCU', 'Surabaya', 'ID', '{112}', '{9}', pg_temp.bd(1), null, 'pending', 'not_required', pg_temp.bd(1), pg_temp.bd(1));
select pg_temp.seed_act(26, 'Guest Lecture Desain Grafis Kontemporer', 31, 4, '2026-09-14', '2026-09-18', 'online',
  'Zoom Meeting', null, null, '{106}', '{4}', pg_temp.bd(4), null, 'pending', 'not_required', pg_temp.bd(4), pg_temp.bd(4));
select pg_temp.seed_act(27, 'Riset Bersama Smart Grid dengan Hochschule Bremen', 12, 5, '2026-08-03', '2026-08-28', 'hybrid',
  'Lab Tenaga Listrik PCU', 'Surabaya', 'ID', '{104}', '{7}', pg_temp.bd(7), null, 'pending', 'not_required', pg_temp.bd(7), pg_temp.bd(7));
select pg_temp.seed_act(28, 'Staff Mobility ke Fontys University of Applied Sciences', 20, 3, '2026-09-07', '2026-09-11', 'offline',
  'Fontys Eindhoven', 'Eindhoven', 'NL', '{105}', '{4}', pg_temp.bd(4), null, 'approved', 'pending', pg_temp.bd(3, '10:00'), pg_temp.bd(4));
select pg_temp.seed_pset(28, 1, 'pending', '{}', '{}', '{PG217839,PG974721}', pg_temp.bd(4));
select pg_temp.seed_act(29, 'Inbound Exchange Seni Rupa Asia 2026', 30, 2, '2026-08-03', '2026-08-28', 'offline',
  'Kampus PCU Siwalankerto', 'Surabaya', 'ID', '{109}', '{4}', pg_temp.bd(8), null, 'approved', 'pending', pg_temp.bd(7, '10:00'), pg_temp.bd(8));
select pg_temp.seed_pset(29, 1, 'pending', '{}', '{X02260008,X02260015}', '{}', pg_temp.bd(8));
select pg_temp.seed_act(30, 'Staff Mobility Fontys University of Applied Sciences 2026', 21, 3, '2026-09-14', '2026-09-16', 'offline',
  'Fontys Eindhoven', 'Eindhoven', 'NL', '{105}', '{4}', pg_temp.bd(2), null, 'pending', 'pending', pg_temp.bd(2), pg_temp.bd(2));
select pg_temp.seed_pset(30, 1, 'pending', '{}', '{}', '{PG214411}', pg_temp.bd(2));
-- open duplicate candidate S-28 / S-30 (same chain 105, overlapping dates, similar names)
insert into realisasi.duplicate_candidates (activity_a, activity_b, score, status)
select least(a.id, b.id), greatest(a.id, b.id), round(similarity(lower(a.name), lower(b.name))::numeric, 2), 'open'
  from realisasi.activities a, realisasi.activities b where a.id = pg_temp.aid(28) and b.id = pg_temp.aid(30)
on conflict (activity_a, activity_b) do nothing;

select setval('realisasi.activity_code_seq', greatest(100, (select last_value from realisasi.activity_code_seq)));
