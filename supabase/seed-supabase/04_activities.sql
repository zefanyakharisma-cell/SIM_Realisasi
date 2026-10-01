-- seed-supabase/04_activities (simks-partnership): a dozen demo activities linked to REAL SIMKS documents, written only
-- into realisasi.* (partner snapshots come from kerjasama.partners via the activity_documents trigger). Dates lie inside
-- each document's validity and inside AY 2025/2026 – 2026/2027. Idempotent: an activity that exists is skipped.
-- Actors are resolved from realisasi.account_roles (03_accounts.sql) through kerjasama.profiles:
--   submitters akun 3 (unit 4, SBM) and akun 4 (unit 5, Prodi Manajemen); partnership akun 11; mobility akun 10.
-- Ids: activities b5000000-0000-4000-8000-0000000000NN, event groups e5000000-…NN, codes RL-2026-00NN.

create or replace function pg_temp.aid(n int) returns uuid language sql immutable as $$
  select ('b5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.gid(n int) returns uuid language sql immutable as $$
  select ('e5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.akun(p_akun int) returns uuid language sql stable as $$
  select id from kerjasama.profiles where akun_id = p_akun $$;
create or replace function pg_temp.pdf() returns bytea language sql immutable as $$
  select decode('255044462d312e340a312030206f626a0a3c3c2f547970652f436174616c6f672f50616765732032203020523e3e0a656e646f626a0a322030206f626a0a3c3c2f547970652f50616765732f4b6964735b33203020525d2f436f756e7420313e3e0a656e646f626a0a332030206f626a0a3c3c2f547970652f506167652f506172656e742032203020522f4d65646961426f785b30203020323030203230305d2f436f6e74656e74732034203020522f5265736f75726365733c3c3e3e3e3e0a656e646f626a0a342030206f626a0a3c3c2f4c656e67746820303e3e73747265616d0a0a656e6473747265616d0a656e646f626a0a787265660a3020350a303030303030303030302036353533352066200a30303030303030303039203030303030206e200a30303030303030303534203030303030206e200a30303030303030313035203030303030206e200a30303030303030313939203030303030206e200a747261696c65720a3c3c2f53697a6520352f526f6f742031203020523e3e0a7374617274787265660a3234350a2525454f460a', 'hex') $$;
create or replace function pg_temp.wib(d date, t time default '09:00') returns timestamptz language sql immutable as $$
  select (d + t) at time zone 'Asia/Jakarta' $$;
create or replace function pg_temp.bd(n int, t time default '08:00') returns timestamptz language sql stable as $$
  select (realisasi._business_days_ago(n) + t) at time zone 'Asia/Jakarta' $$;
create or replace function pg_temp.blob(p_path text, p_by uuid, p_at timestamptz) returns void language sql as $$
  insert into realisasi.file_blobs (path, bucket, data, mime, size_bytes, created_by, created_at)
  values (p_path, split_part(p_path, '/', 1), pg_temp.pdf(), 'application/pdf', length(pg_temp.pdf()), p_by, p_at)
  on conflict (path) do nothing $$;
create or replace function pg_temp.log(p_n int, p_kind text, p_track text, p_action text, p_actor uuid, p_at timestamptz,
                                       p_note text default null, p_diff jsonb default null)
returns void language sql as $$
  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (pg_temp.aid(p_n), p_kind::realisasi.log_kind, p_track::realisasi.team, p_action, p_actor, p_note, p_diff, false, p_at) $$;

-- preconditions: accounts seeded, every referenced SIMKS document present and selectable
do $$
declare d int;
begin
  if pg_temp.akun(3) is null or pg_temp.akun(4) is null or pg_temp.akun(10) is null or pg_temp.akun(11) is null then
    raise exception 'run seed-supabase/03_accounts.sql first (account_roles for akun 3, 4, 10, 11)';
  end if;
  foreach d in array array[11, 15, 17, 19, 25, 27, 28, 29, 33, 34, 36, 42, 44] loop
    if not exists (select 1 from kerjasama.documents where id = d and status not in ('in_process', 'rejected') and start_date is not null) then
      raise exception 'SIMKS document % missing or not selectable; adjust supabase/seed-supabase/04_activities.sql', d;
    end if;
  end loop;
end $$;

create or replace function pg_temp.act(
  p_n int, p_name text, p_unit int, p_type int, p_start date, p_end date, p_mode text, p_venue text, p_city text,
  p_country text, p_docs int[], p_sdgs int[], p_submitted timestamptz, p_verified timestamptz,
  p_pstatus text, p_mstatus text, p_psince timestamptz, p_msince timestamptz,
  p_files text[] default '{ia,ir}', p_pnote text default null, p_mnote text default null, p_ext jsonb default '[]')
returns void language plpgsql as $$
declare v_id uuid := pg_temp.aid(p_n); v_g uuid := pg_temp.gid(p_n); v_code text := 'RL-2026-' || lpad(p_n::text, 4, '0');
        v_creator uuid := pg_temp.akun(case p_unit when 4 then 3 when 5 then 4 end);
        v_part uuid := pg_temp.akun(11); v_mob uuid := pg_temp.akun(10);
        v_created timestamptz; k text; v_path text; e jsonb; v_bad int;
begin
  if exists (select 1 from realisasi.activities where id = v_id) then return; end if;
  if v_creator is null then raise exception 'no submitter account for unit %', p_unit; end if;
  -- R-04 against the live SIMKS data: every agreement valid for the activity dates
  select x into v_bad from unnest(p_docs) x
   where not exists (select 1 from realisasi.documents_valid_between(p_start, p_end) v where v.document_id = x) limit 1;
  if v_bad is not null then raise exception 'activity %: SIMKS document % not valid for % – %', p_n, v_bad, p_start, p_end; end if;

  v_created := coalesce(p_submitted, pg_temp.wib(p_end)) - interval '3 days';
  insert into realisasi.event_groups (id, created_by, created_at) values (v_g, v_creator, v_created) on conflict do nothing;
  insert into realisasi.activities (id, code, name, type_id, start_date, end_date, mode, venue, city, country_code, sks_recognized,
              funding_source, description, submitter_unit_id, created_by, submitted_at, verified_at, partnership_status,
              mobility_status, partnership_since, mobility_since, event_group_id, created_at)
  values (v_id, v_code, p_name, p_type, p_start, p_end, p_mode::realisasi.activity_mode, p_venue, p_city, p_country,
          case when p_type in (1, 7) then 3 end, case when p_type in (1, 2, 7) then 'mixed' else 'pcu' end::realisasi.funding_source,
          'Kegiatan "' || p_name || '" dalam rangka implementasi kerja sama dengan mitra.', p_unit, v_creator, p_submitted,
          p_verified, p_pstatus::realisasi.track_status, p_mstatus::realisasi.track_status,
          coalesce(p_psince, v_created), coalesce(p_msince, p_psince, v_created), v_g, v_created);
  insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, p_unit, true);
  insert into realisasi.activity_documents (activity_id, original_document_id, out_of_scope_warning)
  select v_id, d, not exists (select 1 from kerjasama.document_scope_units su where su.document_id = d and su.unit_id = p_unit)
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
  if p_pstatus = 'approved' then perform pg_temp.log(p_n, 'verification', 'partnership', 'approve', v_part, p_psince); end if;
  if p_pstatus = 'revision_requested' then perform pg_temp.log(p_n, 'verification', 'partnership', 'request_revision', v_part, p_psince, p_pnote); end if;
  if p_mstatus = 'approved' then perform pg_temp.log(p_n, 'verification', 'mobility', 'approve', v_mob, p_msince, null, '{"version":1}'); end if;
  if p_mstatus = 'revision_requested' then perform pg_temp.log(p_n, 'verification', 'mobility', 'request_revision', v_mob, p_msince, p_mnote); end if;
end $$;

create or replace function pg_temp.pset(p_n int, p_status text, p_internal text[], p_inbound text[], p_staff text[],
  p_submitted timestamptz, p_reviewed timestamptz default null) returns void language plpgsql as $$
declare v_act uuid := pg_temp.aid(p_n); v_id uuid := md5(pg_temp.aid(p_n)::text || ':v1')::uuid; v_by uuid; n text; v_path text;
begin
  if exists (select 1 from realisasi.participant_set_versions where id = v_id) then return; end if;
  select created_by into v_by from realisasi.activities where id = v_act;
  insert into realisasi.participant_set_versions (id, activity_id, version, status, submitted_by, submitted_at, reviewed_by, reviewed_at)
  values (v_id, v_act, 1, p_status::realisasi.pset_status, v_by, p_submitted,
          case when p_reviewed is not null then pg_temp.akun(10) end, p_reviewed);
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name)
  select v_id, 'internal', s.nrp, s.full_name, s.faculty_name, s.prodi_name
    from unnest(p_internal) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  foreach n in array p_inbound loop
    v_path := 'realisasi-transcripts/' || v_act || '/v1/' || n || '-' || left(md5(v_act::text || n), 8) || '.pdf';
    perform pg_temp.blob(v_path, v_by, p_submitted - interval '1 day');
    insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
                home_institution, home_student_number, home_country_code, transcript_path)
    select v_id, 'inbound', s.nrp, s.full_name, s.faculty_name, s.prodi_name, s.home_institution,
           'HS-' || right(s.nrp, 4), s.home_country_code, v_path
      from mock_baak.students s where s.nrp = n;
  end loop;
  insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
  select v_id, e.employee_id, e.full_name, e.unit_name
    from unnest(p_staff) with ordinality x(id, o) join mock_hr.employees e on e.employee_id = x.id order by o;
end $$;

-- ---- AY 2025/2026 (verified) -------------------------------------------------------------------------------------
select pg_temp.act(1, 'Student Exchange Semester Ganjil di Kyoto Sangyo University', 4, 1, '2025-09-01', '2025-12-19', 'offline',
  'Kyoto Sangyo University', 'Kyoto', 'JP', '{11}', '{4,17}', pg_temp.wib('2025-12-22'), pg_temp.wib('2026-01-08', '14:00'),
  'approved', 'approved', pg_temp.wib('2026-01-05'), pg_temp.wib('2026-01-08', '14:00'));
select pg_temp.pset(1, 'approved', '{D31238836,D31239872,D32233592}', '{}', '{}', pg_temp.wib('2025-12-22'), pg_temp.wib('2026-01-08', '14:00'));

select pg_temp.act(2, 'Pengabdian Masyarakat UMKM Digital bersama UGM', 5, 8, '2025-11-10', '2025-11-14', 'offline',
  'Desa Wisata Nglanggeran', 'Gunungkidul', 'ID', '{28}', '{1,8}', pg_temp.wib('2025-11-20'), pg_temp.wib('2025-11-26', '10:00'),
  'approved', 'not_required', pg_temp.wib('2025-11-26', '10:00'), pg_temp.wib('2025-11-20'));

select pg_temp.act(3, 'Joint Seminar Bisnis Berkelanjutan ASEAN bersama Chulalongkorn', 4, 6, '2026-01-20', '2026-01-21', 'hybrid',
  'Auditorium PCU', 'Surabaya', 'ID', '{29}', '{8,17}', pg_temp.wib('2026-01-26'), pg_temp.wib('2026-02-02', '10:00'),
  'approved', 'not_required', pg_temp.wib('2026-02-02', '10:00'), pg_temp.wib('2026-01-26'),
  p_ext => '[{"full_name":"Asst. Prof. Kanokwan Srisuk","institution":"Chulalongkorn University","country_code":"TH","role":"speaker"}]');

select pg_temp.act(4, 'Kuliah Tamu Manajemen Inovasi dari National Taiwan University', 4, 4, '2026-03-09', '2026-03-13', 'offline',
  'Gedung T PCU', 'Surabaya', 'ID', '{15}', '{4,9}', pg_temp.wib('2026-03-18'), pg_temp.wib('2026-03-24', '10:00'),
  'approved', 'not_required', pg_temp.wib('2026-03-24', '10:00'), pg_temp.wib('2026-03-18'),
  p_ext => '[{"full_name":"Prof. Chen Yu-Ting","institution":"National Taiwan University","country_code":"TW","role":"visiting_lecturer"}]');

select pg_temp.act(5, 'Riset Bersama Perilaku Konsumen Digital dengan University of Amsterdam', 5, 5, '2026-04-06', '2026-06-30', 'online',
  'Zoom Meeting', null, null, '{17}', '{8,9}', pg_temp.wib('2026-07-06'), pg_temp.wib('2026-07-10', '10:00'),
  'approved', 'not_required', pg_temp.wib('2026-07-10', '10:00'), pg_temp.wib('2026-07-06'));

select pg_temp.act(6, 'Summer Program Business in Asia di Chulalongkorn University', 4, 7, '2026-07-06', '2026-07-24', 'offline',
  'Chulalongkorn University', 'Bangkok', 'TH', '{25}', '{4,17}', pg_temp.wib('2026-07-29'), pg_temp.wib('2026-08-05', '14:00'),
  'approved', 'approved', pg_temp.wib('2026-08-03'), pg_temp.wib('2026-08-05', '14:00'));
select pg_temp.pset(6, 'approved', '{D31242651,D31245931,D32237864,D31246584}', '{}', '{PG217839}', pg_temp.wib('2026-07-29'),
  pg_temp.wib('2026-08-05', '14:00'));

-- ---- AY 2026/2027 Ganjil --------------------------------------------------------------------------------------------
select pg_temp.act(7, 'Inbound Exchange Manajemen National University of Singapore 2026', 5, 2, '2026-08-10', '2026-09-11', 'offline',
  'Kampus PCU Siwalankerto', 'Surabaya', 'ID', '{19}', '{4}', pg_temp.wib('2026-09-14'), pg_temp.wib('2026-09-18', '14:00'),
  'approved', 'approved', pg_temp.wib('2026-09-16'), pg_temp.wib('2026-09-18', '14:00'));
select pg_temp.pset(7, 'approved', '{}', '{X01260012,X01260044}', '{}', pg_temp.wib('2026-09-14'), pg_temp.wib('2026-09-18', '14:00'));

select pg_temp.act(8, 'Riset Bersama Ekonomi Sirkular dengan LMU Munich', 5, 5, '2026-09-07', '2026-09-11', 'hybrid',
  'Lab Manajemen PCU', 'Surabaya', 'ID', '{42}', '{9,12}', pg_temp.wib('2026-09-15'), pg_temp.wib('2026-09-21', '10:00'),
  'approved', 'not_required', pg_temp.wib('2026-09-21', '10:00'), pg_temp.wib('2026-09-15'));

-- renewal chain 29 -> 34 (Chulalongkorn MoA): revision requested on the renewal
select pg_temp.act(9, 'Joint Seminar Rantai Pasok Asia Tenggara (lanjutan)', 4, 6, '2026-09-23', '2026-09-24', 'offline',
  'Gedung T PCU', 'Surabaya', 'ID', '{34}', '{9}', pg_temp.bd(5), null,
  'revision_requested', 'not_required', pg_temp.bd(3, '10:00'), pg_temp.bd(5),
  p_pnote => 'IA belum ditandatangani kedua pihak; mohon unggah IA final.');

-- renewal chain 28 -> 33 (UGM MoU): pending Partnership verification
select pg_temp.act(10, 'Seminar Nasional Kewirausahaan bersama UGM', 5, 6, '2026-09-24', '2026-09-25', 'offline',
  'Auditorium PCU', 'Surabaya', 'ID', '{33}', '{4,8}', pg_temp.bd(2), null,
  'pending', 'not_required', pg_temp.bd(2), pg_temp.bd(2));

-- Partnership approved, Mobility pending
select pg_temp.act(11, 'Student Exchange Singkat di National University of Singapore', 4, 1, '2026-09-01', '2026-09-19', 'offline',
  'National University of Singapore', 'Singapura', 'SG', '{36}', '{4}', pg_temp.bd(6), null,
  'approved', 'pending', pg_temp.bd(4, '10:00'), pg_temp.bd(6));
select pg_temp.pset(11, 'pending', '{D31252983,D32250736,D31243593}', '{}', '{}', pg_temp.bd(6));

-- draft (only IA uploaded)
select pg_temp.act(12, 'Kuliah Tamu Pemasaran Global dari Ateneo de Manila University', 4, 4, '2026-09-28', '2026-09-29', 'online',
  'Zoom Meeting', null, null, '{44}', '{4}', null, null, 'pending', 'not_required', null, null, p_files => '{ia}');

select setval('realisasi.activity_code_seq', greatest(100, (select last_value from realisasi.activity_code_seq)));
