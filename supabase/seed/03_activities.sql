-- 03_activities: scenarios S-01…S-34 (+S-15b = 31, S-20b = 32). Idempotent: every helper skips existing rows.
-- Historical scenarios use fixed dates (< 2026-10-01); queue/revision clocks are relative to realisasi.today() at seed time.
-- Revisi V.1: Jenis Kegiatan = SIMKS agenda (agenda_rules decides mobility), Inbound/Outbound per kegiatan, one kerja
-- sama per kegiatan, Mobility is the only verification (non-mobility kegiatan are verified on submit), and student
-- conflicts between units (S-13/S-14 resolved, S-18 open) replace the old duplicate candidates.

create or replace function pg_temp.aid(n int) returns uuid language sql immutable as $$
  select ('a0000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.gid(n int) returns uuid language sql immutable as $$
  select ('e0000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.pdf() returns bytea language sql immutable as $$
  select decode('255044462d312e340a312030206f626a0a3c3c2f547970652f436174616c6f672f50616765732032203020523e3e0a656e646f626a0a322030206f626a0a3c3c2f547970652f50616765732f4b6964735b33203020525d2f436f756e7420313e3e0a656e646f626a0a332030206f626a0a3c3c2f547970652f506167652f506172656e742032203020522f4d65646961426f785b30203020323030203230305d2f436f6e74656e74732034203020522f5265736f75726365733c3c3e3e3e3e0a656e646f626a0a342030206f626a0a3c3c2f4c656e67746820303e3e73747265616d0a0a656e6473747265616d0a656e646f626a0a787265660a3020350a303030303030303030302036353533352066200a30303030303030303039203030303030206e200a30303030303030303534203030303030206e200a30303030303030313035203030303030206e200a30303030303030313939203030303030206e200a747261696c65720a3c3c2f53697a6520352f526f6f742031203020523e3e0a7374617274787265660a3234350a2525454f460a', 'hex') $$;
create or replace function pg_temp.wib(d date, t time default '09:00') returns timestamptz language sql immutable as $$
  select (d + t) at time zone 'Asia/Jakarta' $$;
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
  p_n int, p_name text, p_unit int, p_agenda int, p_dir text, p_start date, p_end date, p_mode text, p_venue text,
  p_country text, p_doc int, p_sdgs int[], p_submitted timestamptz, p_mstatus text, p_msince timestamptz,
  p_files text[] default '{ia,ir}', p_mnote text default null, p_ext jsonb default '[]')
returns void language plpgsql as $$
declare v_id uuid := pg_temp.aid(p_n); v_g uuid := pg_temp.gid(p_n); v_code text := 'RL-2026-' || lpad(p_n::text, 4, '0');
        v_creator uuid; v_created timestamptz; k text; v_path text; e jsonb; v_mob boolean;
        c_mob uuid := '00000000-0000-4000-8000-000000000003';
begin
  if exists (select 1 from realisasi.activities where id = v_id) then return; end if;
  v_mob := realisasi.agenda_is_mobility(p_agenda);
  v_creator := coalesce((select id from kerjasama.profiles where app_role = 'submitter' and unit_id = p_unit order by id limit 1),
                        '00000000-0000-4000-8000-000000000001');
  v_created := coalesce(p_submitted, pg_temp.wib(p_end)) - interval '3 days';
  insert into realisasi.event_groups (id, created_by, created_at) values (v_g, v_creator, v_created) on conflict do nothing;
  insert into realisasi.activities (id, code, name, agenda_id, direction, start_date, end_date, mode, venue, country_code,
              sks_recognized, description, submitter_unit_id, created_by, submitted_at, verified_at,
              mobility_status, mobility_since, event_group_id, created_at)
  values (v_id, v_code, p_name, p_agenda, p_dir::realisasi.direction, p_start, p_end, p_mode::realisasi.activity_mode, p_venue,
          p_country, case when v_mob and p_dir = 'outbound' then 3 end,
          'Kegiatan "' || p_name || '" dalam rangka implementasi kerja sama dengan mitra.', p_unit, v_creator, p_submitted,
          case when p_submitted is not null and (not v_mob or p_mstatus = 'approved')
               then coalesce(case when v_mob then p_msince end, p_submitted) end,
          case when p_submitted is null then 'not_required' when not v_mob then 'not_required' else p_mstatus end::realisasi.track_status,
          coalesce(p_msince, p_submitted, v_created), v_g, v_created);
  insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, p_unit, true);
  insert into realisasi.activity_documents (activity_id, original_document_id, out_of_scope_warning)
  select v_id, p_doc, not exists (select 1 from kerjasama.document_scope_units su where su.document_id = p_doc and su.unit_id = p_unit)
   where p_doc is not null;
  insert into realisasi.activity_sdgs (activity_id, sdg_id) select v_id, s from unnest(p_sdgs) s;
  for e in select * from jsonb_array_elements(p_ext) loop
    insert into realisasi.activity_external_persons (activity_id, full_name, institution, country_code, role, notes)
    values (v_id, e ->> 'full_name', e ->> 'institution', e ->> 'country_code', (e ->> 'role')::realisasi.person_role, e ->> 'notes');
  end loop;
  foreach k in array p_files || case when v_mob and p_submitted is not null then '{mobility_bundle}'::text[] else '{}' end loop
    v_path := case when k = 'mobility_bundle' then 'realisasi-transcripts/' else 'realisasi-files/' end
              || v_id || '/' || k || '/' || md5(v_id::text || k)::uuid || '.pdf';
    perform pg_temp.blob(v_path, v_creator, v_created + interval '1 day');
    insert into realisasi.activity_files (activity_id, kind, version, storage_path, filename, size_bytes, mime, is_current, uploaded_by, uploaded_at)
    values (v_id, k::realisasi.file_kind, 1, v_path,
            case when k = 'mobility_bundle' then 'Transkrip_Poster_Dokumentasi_' else upper(k) || '_' end || v_code || '.pdf',
            length(pg_temp.pdf()), 'application/pdf', true, v_creator, v_created + interval '1 day');
  end loop;

  perform pg_temp.log(p_n, 'system', null, 'create', v_creator, v_created);
  if p_submitted is null then return; end if;
  perform pg_temp.log(p_n, 'system', null, 'submit', v_creator, p_submitted);
  if v_mob and p_mstatus = 'approved' then perform pg_temp.log(p_n, 'verification', 'mobility', 'approve', c_mob, p_msince, null, '{"version":1}'); end if;
  if v_mob and p_mstatus = 'revision_requested' then perform pg_temp.log(p_n, 'verification', 'mobility', 'request_revision', c_mob, p_msince, p_mnote); end if;
end $$;

create or replace function pg_temp.seed_pset(p_n int, p_ver int, p_status text, p_internal text[], p_inbound text[], p_staff text[],
  p_submitted timestamptz, p_reviewed timestamptz default null, p_note text default null)
returns void language plpgsql as $$
declare v_act uuid := pg_temp.aid(p_n); v_id uuid := md5(pg_temp.aid(p_n)::text || ':v' || p_ver)::uuid; v_by uuid;
begin
  if exists (select 1 from realisasi.participant_set_versions where id = v_id) then return; end if;
  select created_by into v_by from realisasi.activities where id = v_act;
  insert into realisasi.participant_set_versions (id, activity_id, version, status, submitted_by, submitted_at, reviewed_by, reviewed_at, review_note)
  values (v_id, v_act, p_ver, p_status::realisasi.pset_status, v_by, p_submitted,
          case when p_reviewed is not null then '00000000-0000-4000-8000-000000000003'::uuid end, p_reviewed, p_note);
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name)
  select v_id, 'internal', s.nrp, s.full_name, s.faculty_name, s.prodi_name
    from unnest(p_internal) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
              home_institution, home_student_number, home_country_code)
  select v_id, 'inbound', s.nrp, s.full_name, s.faculty_name, s.prodi_name, s.home_institution,
         'HS-' || right(s.nrp, 4), s.home_country_code
    from unnest(p_inbound) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
  select v_id, e.employee_id, e.full_name, e.unit_name
    from unnest(p_staff) with ordinality x(id, o) join mock_hr.employees e on e.employee_id = x.id order by o;
end $$;

-- a student conflict between two units' activities (rule 2.1); p_kept null = still open
create or replace function pg_temp.seed_conflict(p_nrp text, p_a int, p_b int, p_kept int, p_at timestamptz, p_note text default null)
returns void language sql as $$
  insert into realisasi.participant_conflicts (nrp, activity_a, activity_b, status, kept_activity_id, note, resolved_by, resolved_at, created_at)
  values (p_nrp, least(pg_temp.aid(p_a), pg_temp.aid(p_b)), greatest(pg_temp.aid(p_a), pg_temp.aid(p_b)),
          case when p_kept is null then 'open' else 'resolved' end::realisasi.conflict_status,
          case when p_kept is not null then pg_temp.aid(p_kept) end, p_note,
          case when p_kept is not null then '00000000-0000-4000-8000-000000000003'::uuid end,
          case when p_kept is not null then p_at + interval '2 days' end, p_at)
  on conflict (nrp, activity_a, activity_b) do nothing $$;

-- ---------------------------------------------------------------------------------------------
-- Agendas used: 2 Student Exchange, 17 Gelar Ganda/Double Degree, 23 Short Program, 24 Studi Ekskursi (mobility);
-- 4 Joint Research, 15 Kuliah Tamu, 31 Staf/Faculty Exchange, 35 Joint Projects (seminar), 40 Pengabdian (non-mobility).

-- AY 2025/2026 Ganjil
select pg_temp.seed_act(1, 'Student Exchange Semester Ganjil di Hanyang University', 20, 2, 'outbound', '2025-09-01', '2025-12-19', 'offline',
  'Hanyang University Seoul Campus', 'KR', 102, '{4,17}', pg_temp.wib('2025-12-22'), 'approved', pg_temp.wib('2026-01-08', '14:00'));
select pg_temp.seed_pset(1, 1, 'approved', '{D31238836,D31239872,D32233592,D31242651}', '{}', '{PG217839}',
  pg_temp.wib('2025-12-22'), pg_temp.wib('2026-01-08', '14:00'));

select pg_temp.seed_act(2, 'Inbound Exchange Kyoto Institute of Technology 2025', 10, 2, 'inbound', '2025-08-25', '2025-12-12', 'offline',
  'Kampus PCU Siwalankerto', 'ID', 101, '{4}', pg_temp.wib('2025-12-15'), 'approved', pg_temp.wib('2026-01-05', '15:00'));
select pg_temp.seed_pset(2, 1, 'approved', '{}', '{X01250003,X01250017,X01250024}', '{}', pg_temp.wib('2025-12-15'), pg_temp.wib('2026-01-05', '15:00'));

select pg_temp.seed_act(5, 'Seminar Nasional Desain dan Budaya bersama ITB', 30, 35, 'inbound', '2025-11-03', '2025-11-04', 'offline',
  'Auditorium PCU', 'ID', 110, '{4,11}', pg_temp.wib('2025-11-10'), null, null);
-- S-05: post-freeze edit by IO Admin (activity inside the frozen Ganjil 2025/2026 window)
select pg_temp.log(5, 'update', null, 'edit', '00000000-0000-4000-8000-000000000001', pg_temp.wib('2026-05-10', '10:30'),
  'Koreksi lokasi sesuai laporan akhir.', '{"venue": ["Auditorium PCU", "Auditorium Gedung W PCU"]}', true)
 where not exists (select 1 from realisasi.activity_log where activity_id = pg_temp.aid(5) and action = 'edit');
update realisasi.activities set venue = 'Auditorium Gedung W PCU' where id = pg_temp.aid(5) and venue = 'Auditorium PCU';

select pg_temp.seed_act(20, 'Riset Bersama Material Komposit dengan Osaka University', 10, 4, 'outbound', '2025-10-06', '2025-10-10', 'offline',
  'Osaka University Suita Campus', 'JP', 904, '{9}', pg_temp.wib('2025-10-20'), null, null);

-- S-19: Ganjil 2025/2026 activity, submitted late (after the Ganjil freeze) and verified on submit
select pg_temp.seed_act(19, 'Kuliah Tamu Desain Interaksi dari The University of Queensland', 30, 15, 'inbound', '2025-11-10', '2025-11-14', 'hybrid',
  'Gedung P PCU', 'ID', 106, '{4}', pg_temp.wib('2026-04-15', '10:00'), null, null,
  p_ext => '[{"full_name":"Dr. Emily Carter","institution":"The University of Queensland","country_code":"AU","role":"visiting_lecturer"}]');

-- AY 2025/2026 Genap
select pg_temp.seed_act(3, 'Winter Program Smart Computing di NTUST', 11, 23, 'outbound', '2026-02-09', '2026-02-27', 'offline',
  'NTUST Main Campus', 'TW', 103, '{4,9}', pg_temp.wib('2026-03-05'), 'approved', pg_temp.wib('2026-03-12', '14:00'));
select pg_temp.seed_pset(3, 1, 'approved', '{B11252003,B11256252,B11257273,B11240422,B11244167}', '{}', '{PG190875}',
  pg_temp.wib('2026-03-05'), pg_temp.wib('2026-03-12', '14:00'));

select pg_temp.seed_act(4, 'Inbound Exchange Fontys Business School 2026', 20, 2, 'inbound', '2026-02-02', '2026-06-26', 'offline',
  'Kampus PCU Siwalankerto', 'ID', 105, '{4,8}', pg_temp.wib('2026-07-01'), 'approved', pg_temp.wib('2026-07-08', '14:00'));
select pg_temp.seed_pset(4, 1, 'approved', '{}', '{X02250056,X02250063}', '{}', pg_temp.wib('2026-07-01'), pg_temp.wib('2026-07-08', '14:00'));

select pg_temp.seed_act(6, 'Riset Bersama Sistem Energi Terbarukan dengan Hochschule Bremen', 12, 4, 'inbound', '2026-03-02', '2026-07-31', 'hybrid',
  'Lab Konversi Energi PCU', 'ID', 104, '{7,13}', pg_temp.wib('2026-08-05'), null, null);

select pg_temp.seed_act(7, 'Visiting Lecturer Media Kreatif dari The University of Queensland', 30, 15, 'inbound', '2026-04-13', '2026-04-17', 'offline',
  'Gedung P PCU', 'ID', 106, '{4}', pg_temp.wib('2026-04-24'), null, null,
  p_ext => '[{"full_name":"Prof. Liam Walsh","institution":"The University of Queensland","country_code":"AU","role":"visiting_lecturer"}]');

select pg_temp.seed_act(8, 'Pengabdian Masyarakat Penguatan UMKM bersama UGM', 21, 40, 'outbound', '2026-06-08', '2026-06-12', 'offline',
  'Desa Wisata Kandangan', 'ID', 111, '{1,8}', pg_temp.wib('2026-06-20'), null, null);

-- S-15a / S-15b: D31240187 in two activities of the same unit (rule 2.2: counted in both; AT-02)
select pg_temp.seed_act(15, 'Student Exchange Semester Genap di Hanyang University', 20, 2, 'outbound', '2026-02-10', '2026-03-20', 'offline',
  'Hanyang University Seoul Campus', 'KR', 102, '{4}', pg_temp.wib('2026-03-27'), 'approved', pg_temp.wib('2026-04-06', '14:00'));
select pg_temp.seed_pset(15, 1, 'approved', '{D31240187,D31245931,D32237864}', '{}', '{}', pg_temp.wib('2026-03-27'), pg_temp.wib('2026-04-06', '14:00'));

select pg_temp.seed_act(31, 'Short Course Manajemen Internasional di Tunghai University', 20, 23, 'outbound', '2026-05-04', '2026-06-12', 'offline',
  'Tunghai University', 'TW', 114, '{4,17}', pg_temp.wib('2026-06-18'), 'approved', pg_temp.wib('2026-06-29', '14:00'));
select pg_temp.seed_pset(31, 1, 'approved', '{D31240187,D31246584}', '{}', '{}', pg_temp.wib('2026-06-18'), pg_temp.wib('2026-06-29', '14:00'));

-- S-34: Double Degree (Outbound Internasional, JD/DD)
select pg_temp.seed_act(34, 'Double Degree Manajemen dengan Fontys University of Applied Sciences', 21, 17, 'outbound', '2026-02-02', '2026-07-03', 'offline',
  'Fontys Eindhoven', 'NL', 105, '{4,17}', pg_temp.wib('2026-07-10'), 'approved', pg_temp.wib('2026-07-17', '14:00'));
select pg_temp.seed_pset(34, 1, 'approved', '{D31243593,D32250736}', '{}', '{}', pg_temp.wib('2026-07-10'), pg_temp.wib('2026-07-17', '14:00'));

-- S-20b: activity on the renewal (905) of S-20's agreement (904)
select pg_temp.seed_act(32, 'Riset Bersama Material Komposit Tahap II dengan Osaka University', 10, 4, 'outbound', '2026-05-11', '2026-05-15', 'online',
  'Zoom Meeting', null, 905, '{9}', pg_temp.wib('2026-05-22'), null, null);

-- S-21: international conference with speakers from two countries
select pg_temp.seed_act(21, 'Konferensi Internasional Desain Asia Pasifik', 30, 35, 'inbound', '2026-03-23', '2026-03-24', 'offline',
  'Gedung W PCU', 'ID', 103, '{4,17}', pg_temp.wib('2026-04-02'), null, null,
  p_ext => '[{"full_name":"Dr. Wei-Lun Chang","institution":"National Taiwan University of Science and Technology","country_code":"TW","role":"speaker"},{"full_name":"Asst. Prof. Nattapong Chaiyasit","institution":"King Mongkut''s University of Technology Thonburi","country_code":"TH","role":"speaker"}]');

-- S-24: late submission
select pg_temp.seed_act(24, 'Seminar Teknologi Manufaktur bersama UTM', 10, 35, 'inbound', '2026-06-22', '2026-07-01', 'hybrid',
  'Gedung T PCU', 'ID', 107, '{9}', pg_temp.wib('2026-08-20'), null, null);

-- AY 2026/2027 Ganjil (verified)
select pg_temp.seed_act(9, 'Riset Bersama Optimasi Rantai Pasok dengan UTM', 10, 4, 'inbound', '2026-08-10', '2026-09-25', 'hybrid',
  'Lab Sistem Industri PCU', 'ID', 107, '{9,12}', pg_temp.wib('2026-09-28'), null, null);

select pg_temp.seed_act(10, 'Student Exchange Bisnis Digital di KMUTT', 20, 2, 'outbound', '2026-08-03', '2026-09-18', 'offline',
  'KMUTT Bang Mod Campus', 'TH', 108, '{4,8}', pg_temp.wib('2026-09-21'), 'approved', pg_temp.wib('2026-09-25', '14:00'));
select pg_temp.seed_pset(10, 1, 'approved', '{D31252983,D31243593}', '{}', '{}', pg_temp.wib('2026-09-21'), pg_temp.wib('2026-09-25', '14:00'));

select pg_temp.seed_act(11, 'Inbound Exchange Desain Kreatif Asia Tenggara 2026', 30, 2, 'inbound', '2026-08-10', '2026-09-11', 'offline',
  'Kampus PCU Siwalankerto', 'ID', 109, '{4,10}', pg_temp.wib('2026-09-14'), 'approved', pg_temp.wib('2026-09-18', '14:00'));
select pg_temp.seed_pset(11, 1, 'approved', '{}', '{X01260012,X01260044,X01260051,X01260068}', '{}', pg_temp.wib('2026-09-14'), pg_temp.wib('2026-09-18', '14:00'));

select pg_temp.seed_act(12, 'Seminar Industri Telekomunikasi bersama Telkom', 21, 35, 'inbound', '2026-09-14', '2026-09-15', 'offline',
  'Auditorium PCU', 'ID', 117, '{9}', pg_temp.wib('2026-09-17'), null, null);

-- S-33: Studi Ekskursi in Indonesia, 5 days (Outbound Dalam Negeri, Kegiatan Internasional < 14 hari column)
select pg_temp.seed_act(33, 'Studi Ekskursi Desain ke Universitas Udayana', 31, 24, 'outbound', '2026-09-01', '2026-09-05', 'offline',
  'Universitas Udayana', 'ID', 110, '{4,11}', pg_temp.wib('2026-09-10'), 'approved', pg_temp.wib('2026-09-15', '14:00'));
select pg_temp.seed_pset(33, 1, 'approved', '{C21233005,C21233140,C21233729}', '{}', '{}', pg_temp.wib('2026-09-10'), pg_temp.wib('2026-09-15', '14:00'));

-- S-13 / S-14: the same summer program claimed by FTI and Program Studi Informatika with the same 12 students. Rule 2.1: the
-- Mobility team looked at both PDFs and kept every student on S-13 (FTI), so they count once, for FTI (AT-01).
select pg_temp.seed_act(13, 'Summer Program Smart Manufacturing di Nanyang Polytechnic', 10, 23, 'outbound', '2026-08-03', '2026-08-21', 'offline',
  'Nanyang Polytechnic', 'SG', 113, '{4,9}', pg_temp.wib('2026-08-28'), 'approved', pg_temp.wib('2026-09-10', '14:00'));
select pg_temp.seed_pset(13, 1, 'approved',
  '{B11227366,B11234310,B11235580,B11235901,B11237182,B11238623,B11240422,B11244167,B12222426,B12223137,B12229323,B12249536}',
  '{}', '{PG707752}', pg_temp.wib('2026-08-28'), pg_temp.wib('2026-09-10', '14:00'));
select pg_temp.seed_act(14, 'Summer Program Smart Manufacturing Nanyang Polytechnic 2026', 11, 23, 'outbound', '2026-08-03', '2026-08-21', 'offline',
  'Nanyang Polytechnic', 'SG', 113, '{4,9}', pg_temp.wib('2026-08-29'), 'approved', pg_temp.wib('2026-09-12', '14:00'));
select pg_temp.seed_pset(14, 1, 'approved',
  '{B11227366,B11234310,B11235580,B11235901,B11237182,B11238623,B11240422,B11244167,B12222426,B12223137,B12229323,B12249536}',
  '{}', '{}', pg_temp.wib('2026-08-29'), pg_temp.wib('2026-09-12', '14:00'));
select pg_temp.seed_conflict(n, 13, 14, 13, pg_temp.wib('2026-08-29', '10:00'), 'Surat tugas dan transkrip diterbitkan FTI.')
  from unnest('{B11227366,B11234310,B11235580,B11235901,B11237182,B11238623,B11240422,B11244167,B12222426,B12223137,B12229323,B12249536}'::text[]) n;
select pg_temp.log(n, 'verification', 'mobility', 'resolve_conflict', '00000000-0000-4000-8000-000000000003', pg_temp.wib('2026-08-31', '10:00'),
                   'Surat tugas dan transkrip diterbitkan FTI.',
                   jsonb_build_object('students', 12, 'kept', 'RL-2026-0013', 'not_counted', 'RL-2026-0014'))
  from unnest(array[13, 14]) n
 where not exists (select 1 from realisasi.activity_log where activity_id = pg_temp.aid(n) and action = 'resolve_conflict');

-- S-16: Mobility revision requested 15 days ago (AT-03)
select pg_temp.seed_act(16, 'Student Exchange Teknik di Kyoto Institute of Technology', 10, 2, 'outbound', '2026-08-24', '2026-09-04', 'offline',
  'Kyoto Institute of Technology', 'JP', 101, '{4}', pg_temp.daysago(17), 'revision_requested', pg_temp.daysago(15, '09:00'),
  p_mnote => 'Satu NRP tidak sesuai surat tugas; mohon perbarui data peserta.');
select pg_temp.seed_pset(16, 1, 'revision_requested', '{B12251882,B12252182,B12254341}', '{}', '{}',
  pg_temp.daysago(17), pg_temp.daysago(15, '09:00'), 'Satu NRP tidak sesuai surat tugas; mohon perbarui data peserta.');

-- S-17: non-mobility seminar, verified on submit 10 days ago
select pg_temp.seed_act(17, 'Joint Seminar Pemasaran Digital Asia', 20, 35, 'inbound', '2026-09-07', '2026-09-08', 'offline',
  'Gedung T PCU', 'ID', 102, '{8}', pg_temp.daysago(10), null, null);

-- S-18: Program Studi Informatika claims two of S-13's students for an overlapping program: open conflicts in the queue
select pg_temp.seed_act(18, 'Summer Program Smart Manufacturing - Nanyang Poly', 11, 23, 'outbound', '2026-08-03', '2026-08-20', 'offline',
  'Nanyang Polytechnic', 'SG', 113, '{4}', pg_temp.daysago(3), 'pending', pg_temp.daysago(3));
select pg_temp.seed_pset(18, 1, 'pending', '{B11227366,B11234310}', '{}', '{}', pg_temp.daysago(3));
select pg_temp.seed_conflict(n, 13, 18, null, pg_temp.daysago(3)) from unnest('{B11227366,B11234310}'::text[]) n;

-- S-22: unit outside the agreement scope (out_of_scope_warning)
select pg_temp.seed_act(22, 'Pengabdian Masyarakat Literasi Keuangan Desa', 20, 40, 'outbound', '2026-08-17', '2026-08-21', 'offline',
  'Desa Sumberejo', 'ID', 111, '{1,4}', pg_temp.wib('2026-08-26'), null, null);

-- S-23: draft past its reporting deadline (2026-09-13), only IA uploaded
select pg_temp.seed_act(23, 'Kuliah Tamu Ilustrasi Digital', 30, 15, 'inbound', '2026-08-12', '2026-08-14', 'online',
  'Zoom Meeting', null, 106, '{4}', null, null, null, p_files => '{ia}');

-- S-25…S-27: non-mobility, verified on submit; S-28/S-30 staff exchange (non-mobility since Revisi V.1)
select pg_temp.seed_act(25, 'Seminar Nasional Manajemen Rantai Pasok', 21, 35, 'inbound', '2026-09-21', '2026-09-22', 'offline',
  'Auditorium PCU', 'ID', 112, '{9}', pg_temp.daysago(1), null, null);
select pg_temp.seed_act(26, 'Guest Lecture Desain Grafis Kontemporer', 31, 15, 'inbound', '2026-09-14', '2026-09-18', 'online',
  'Zoom Meeting', null, 106, '{4}', pg_temp.daysago(5), null, null);
select pg_temp.seed_act(27, 'Riset Bersama Smart Grid dengan Hochschule Bremen', 12, 4, 'inbound', '2026-08-03', '2026-08-28', 'hybrid',
  'Lab Tenaga Listrik PCU', 'ID', 104, '{7}', pg_temp.daysago(9), null, null);
select pg_temp.seed_act(28, 'Staff Mobility ke Fontys University of Applied Sciences', 20, 31, 'outbound', '2026-09-07', '2026-09-11', 'offline',
  'Fontys Eindhoven', 'NL', 105, '{4}', pg_temp.daysago(6), null, null);

-- S-29 / S-30: in the Mobility queue
select pg_temp.seed_act(29, 'Inbound Exchange Seni Rupa Asia 2026', 30, 2, 'inbound', '2026-08-03', '2026-08-28', 'offline',
  'Kampus PCU Siwalankerto', 'ID', 109, '{4}', pg_temp.daysago(10), 'pending', pg_temp.daysago(10));
select pg_temp.seed_pset(29, 1, 'pending', '{}', '{X02260008,X02260015}', '{}', pg_temp.daysago(10));
select pg_temp.seed_act(30, 'Short Program Bisnis Berkelanjutan di Fontys', 21, 23, 'outbound', '2026-09-14', '2026-09-25', 'offline',
  'Fontys Eindhoven', 'NL', 105, '{4}', pg_temp.daysago(2), 'pending', pg_temp.daysago(2));
select pg_temp.seed_pset(30, 1, 'pending', '{D31245931,D31246584}', '{}', '{}', pg_temp.daysago(2));

select setval('realisasi.activity_code_seq', greatest(100, (select last_value from realisasi.activity_code_seq)));
