-- seed-supabase/10_kegiatan_tambahan_8 (simks-partnership): additional bulk kegiatan 396-420, adapted from the local
-- demo seed supabase/seed/04_bulk_8.sql to the real SIM Kerjasama units (Program Studi submitters) and agreements.
-- Generated from a reviewed JSON list; every row passes the guards below (agreement valid for the dates, submission
-- after the end date, Mobility decision after the submission, participant set for every submitted mobility kegiatan,
-- no student in two overlapping kegiatan, unique names). Needs 03_accounts.sql and 09_registries_tambahan.sql.
-- Self-contained and idempotent (existing rows are skipped), so it can be run on its own: Supabase SQL Editor or one
-- statement batch. Writes only realisasi.*; SIM Kerjasama tables are only read.

-- The kegiatan reference SIM Kerjasama agreements 11, 19, 25, 28, 30, 31, 42, 72, 105, 107, 126, 133, 151, 156, 158, 166, 174, 188, 191, 195, 205, 206, 208. Where any is missing (e.g. the local
-- --rehearse fixture, which only mirrors agreements 11-52) the whole file is skipped with a notice instead of failing.
drop table if exists pg_temp.tambahan_skip;
create temp table tambahan_skip as
select exists (select 1 from unnest('{11,19,25,28,30,31,42,72,105,107,126,133,151,156,158,166,174,188,191,195,205,206,208}'::int[]) d where not exists (select 1 from kerjasama.documents k where k.id = d)) as skip;
do $$ begin if (select skip from pg_temp.tambahan_skip) then
  raise notice '10_kegiatan_tambahan_8: SIM Kerjasama agreements missing, kegiatan 396-420 skipped'; end if; end $$;


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
create or replace function pg_temp.daysago(n int, t time default '09:00') returns timestamptz language sql stable as $$
  select ((realisasi.today() - n) + t) at time zone 'Asia/Jakarta' $$;

create or replace function pg_temp.blob(p_path text, p_by uuid, p_at timestamptz) returns void language sql as $$
  insert into realisasi.file_blobs (path, bucket, data, mime, size_bytes, created_by, created_at)
  values (p_path, split_part(p_path, '/', 1), pg_temp.pdf(), 'application/pdf', length(pg_temp.pdf()), p_by, p_at)
  on conflict (path) do nothing $$;

create or replace function pg_temp.log(p_n int, p_kind text, p_track text, p_action text, p_actor uuid, p_at timestamptz,
                                       p_note text default null, p_diff jsonb default null)
returns void language sql as $$
  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (pg_temp.aid(p_n), p_kind::realisasi.log_kind, p_track::realisasi.team, p_action, p_actor, p_note, p_diff, false, p_at) $$;

-- One kegiatan. p_submitted null = draft. Mobility agendas need p_mstatus ('approved' | 'pending' | 'revision_requested')
-- once submitted (+ p_msince for approved / revision_requested); non-mobility agendas take p_mstatus null.
create or replace function pg_temp.bulk_act(
  p_n int, p_name text, p_unit int, p_agenda int, p_dir text, p_start date, p_end date, p_mode text, p_venue text,
  p_country text, p_doc int, p_sdgs int[], p_desc text, p_submitted timestamptz, p_mstatus text, p_msince timestamptz,
  p_files text[] default '{ia,ir}', p_mnote text default null, p_ext jsonb default '[]', p_co_units int[] default '{}')
returns void language plpgsql as $$
declare v_id uuid := pg_temp.aid(p_n); v_g uuid := pg_temp.gid(p_n); v_code text;
        v_creator uuid; v_created timestamptz; k text; v_path text; e jsonb; v_mob boolean; u int;
        c_mob uuid := pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end);
begin
  if (select skip from pg_temp.tambahan_skip) then return; end if;
  if exists (select 1 from realisasi.activities where id = v_id) then return; end if;
  -- guards
  if p_n not between 221 and 420 then raise exception 'bulk %: number outside 221..420', p_n; end if;
  if not exists (select 1 from kerjasama.units where id = p_unit and kind = 'prodi') then raise exception 'bulk %: unit % is not a Program Studi', p_n, p_unit; end if;
  if not exists (select 1 from kerjasama.agendas where id = p_agenda) then raise exception 'bulk %: agenda % missing', p_n, p_agenda; end if;
  if exists (select 1 from realisasi.activities where lower(name) = lower(p_name)) then
    raise exception 'bulk %: duplicate kegiatan name "%"', p_n, p_name; end if;
  if not exists (select 1 from realisasi.documents_valid_between(p_start, p_end) v where v.document_id = p_doc) then
    raise exception 'bulk %: document % not valid for % .. %', p_n, p_doc, p_start, p_end; end if;
  if p_country is not null and not exists (select 1 from kerjasama.countries where code = p_country) then
    raise exception 'bulk %: country % missing', p_n, p_country; end if;
  if p_country is null and p_mode <> 'online' then raise exception 'bulk %: country required unless online', p_n; end if;
  if cardinality(p_sdgs) = 0 or exists (select 1 from unnest(p_sdgs) s where s not between 1 and 17) then
    raise exception 'bulk %: 1..17 SDGs required', p_n; end if;
  if coalesce(length(p_desc), 0) < 40 then raise exception 'bulk %: description too short', p_n; end if;
  v_mob := realisasi.agenda_is_mobility(p_agenda);
  if p_submitted is not null then
    if (p_submitted at time zone 'Asia/Jakarta')::date <= p_end then raise exception 'bulk %: submitted on/before end date', p_n; end if;
    if (p_submitted at time zone 'Asia/Jakarta')::date > realisasi.today() then raise exception 'bulk %: submitted in the future', p_n; end if;
    if v_mob and coalesce(p_mstatus, '') not in ('approved', 'pending', 'revision_requested') then
      raise exception 'bulk %: mobility kegiatan needs p_mstatus approved/pending/revision_requested', p_n; end if;
    if not v_mob and p_mstatus is not null then raise exception 'bulk %: non-mobility kegiatan takes p_mstatus null', p_n; end if;
    if p_mstatus in ('approved', 'revision_requested') and (p_msince is null or p_msince <= p_submitted) then
      raise exception 'bulk %: p_msince must follow p_submitted', p_n; end if;
    if p_mstatus = 'revision_requested' and p_mnote is null then raise exception 'bulk %: revision needs p_mnote', p_n; end if;
    if not p_files @> '{ia,ir}' then raise exception 'bulk %: a submitted kegiatan needs IA and IR', p_n; end if;
  end if;

  -- creator as in 06/07: the Prodi Manajemen submitter (akun 4) for unit 5, otherwise IO Admin (akun 1) for the prodi
  v_creator := pg_temp.akun(case when p_unit = 5 then 4 else 1 end);
  v_created := coalesce(p_submitted, pg_temp.wib(p_end)) - interval '3 days';
  v_code := 'RL-' || to_char(v_created at time zone 'Asia/Jakarta', 'YYYY') || '-' || lpad(p_n::text, 4, '0');
  insert into realisasi.event_groups (id, created_by, created_at) values (v_g, v_creator, v_created) on conflict do nothing;
  insert into realisasi.activities (id, code, name, agenda_id, direction, start_date, end_date, mode, venue, country_code,
              sks_recognized, description, submitter_unit_id, created_by, submitted_at, verified_at,
              mobility_status, mobility_since, event_group_id, created_at)
  values (v_id, v_code, p_name, p_agenda, p_dir::realisasi.direction, p_start, p_end, p_mode::realisasi.activity_mode, p_venue,
          p_country, case when v_mob and p_dir = 'outbound' then case when p_end - p_start >= 60 then 20 when p_end - p_start >= 14 then 6 else 3 end end,
          p_desc, p_unit, v_creator, p_submitted,
          case when p_submitted is not null and (not v_mob or p_mstatus = 'approved')
               then coalesce(case when v_mob then p_msince end, p_submitted) end,
          case when p_submitted is null or not v_mob then 'not_required' else p_mstatus end::realisasi.track_status,
          coalesce(p_msince, p_submitted, v_created), v_g, v_created);
  insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, p_unit, true);
  foreach u in array p_co_units loop
    if u = p_unit or not exists (select 1 from kerjasama.units where id = u) then raise exception 'bulk %: bad co-unit %', p_n, u; end if;
    insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, u, false);
  end loop;
  insert into realisasi.activity_documents (activity_id, original_document_id, out_of_scope_warning)
  values (v_id, p_doc, not exists (select 1 from kerjasama.document_scope_units su where su.document_id = p_doc and su.unit_id = p_unit));
  insert into realisasi.activity_sdgs (activity_id, sdg_id) select distinct v_id, s from unnest(p_sdgs) s;
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

-- Participant set v1 of a mobility kegiatan; status follows the activity's Mobility track (draft for a draft kegiatan).
create or replace function pg_temp.bulk_pset(p_n int, p_internal text[], p_inbound text[] default '{}', p_staff text[] default '{}')
returns void language plpgsql as $$
declare v_act uuid := pg_temp.aid(p_n); v_id uuid := md5(pg_temp.aid(p_n)::text || ':v1')::uuid; a realisasi.activities; v_bad text;
        v_status text;
begin
  if (select skip from pg_temp.tambahan_skip) then return; end if;
  if exists (select 1 from realisasi.participant_set_versions where id = v_id) then return; end if;
  select * into a from realisasi.activities where id = v_act;
  if a.id is null then raise exception 'bulk_pset %: activity missing', p_n; end if;
  if not realisasi.agenda_is_mobility(a.agenda_id) then raise exception 'bulk_pset %: only mobility kegiatan carry participants', p_n; end if;
  if cardinality(p_internal) + cardinality(p_inbound) = 0 then raise exception 'bulk_pset %: no students', p_n; end if;
  if a.direction = 'outbound' and cardinality(p_internal) = 0 then raise exception 'bulk_pset %: outbound needs internal students', p_n; end if;
  if a.direction = 'inbound' and cardinality(p_inbound) = 0 then raise exception 'bulk_pset %: inbound needs inbound students', p_n; end if;
  select string_agg(x, ',') into v_bad from unnest(p_internal) x
   where not exists (select 1 from mock_baak.students s where s.nrp = x and s.category = 'regular' and s.status = 'active');
  if v_bad is not null then raise exception 'bulk_pset %: not active regular students: %', p_n, v_bad; end if;
  select string_agg(x, ',') into v_bad from unnest(p_inbound) x
   where not exists (select 1 from mock_baak.students s where s.nrp = x and s.category = 'inbound_exchange');
  if v_bad is not null then raise exception 'bulk_pset %: not inbound students: %', p_n, v_bad; end if;
  select string_agg(x, ',') into v_bad from unnest(p_staff) x
   where not exists (select 1 from mock_hr.employees e where e.employee_id = x and e.status = 'active');
  if v_bad is not null then raise exception 'bulk_pset %: not active employees: %', p_n, v_bad; end if;
  select string_agg(distinct ps.nrp || ' (' || o.code || ')', ', ') into v_bad
    from realisasi.participant_students ps
    join realisasi.participant_set_versions v on v.id = ps.set_version_id and v.status <> 'superseded'
    join realisasi.activities o on o.id = v.activity_id and o.id <> v_act
   where ps.nrp = any (p_internal || p_inbound) and o.start_date <= a.end_date and a.start_date <= o.end_date;
  if v_bad is not null then raise exception 'bulk_pset %: students already in an overlapping kegiatan: %', p_n, v_bad; end if;

  v_status := case when a.submitted_at is null then 'draft' else a.mobility_status::text end;
  insert into realisasi.participant_set_versions (id, activity_id, version, status, submitted_by, submitted_at, reviewed_by, reviewed_at, review_note)
  values (v_id, v_act, 1, v_status::realisasi.pset_status, a.created_by, a.submitted_at,
          case when v_status in ('approved', 'revision_requested') then pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end) end,
          case when v_status in ('approved', 'revision_requested') then a.mobility_since end,
          case when v_status = 'revision_requested'
               then (select note from realisasi.activity_log where activity_id = v_act and action = 'request_revision' limit 1) end);
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

-- End-of-file check for one bulk file: exactly the expected rows exist and every submitted mobility kegiatan has its
-- participant set.
create or replace function pg_temp.bulk_verify(p_from int, p_to int) returns void language plpgsql as $$
declare v_n int; v_bad text;
begin
  if (select skip from pg_temp.tambahan_skip) then return; end if;
  select count(*) into v_n from realisasi.activities a where a.id = any (select pg_temp.aid(g) from generate_series(p_from, p_to) g);
  if v_n <> p_to - p_from + 1 then raise exception 'bulk_verify %..%: % of % kegiatan present', p_from, p_to, v_n, p_to - p_from + 1; end if;
  select string_agg(a.code, ', ') into v_bad from realisasi.activities a
   where a.id = any (select pg_temp.aid(g) from generate_series(p_from, p_to) g)
     and realisasi.agenda_is_mobility(a.agenda_id) and a.submitted_at is not null
     and not exists (select 1 from realisasi.participant_set_versions v where v.activity_id = a.id);
  if v_bad is not null then raise exception 'bulk_verify: mobility kegiatan without participants: %', v_bad; end if;
  perform setval('realisasi.activity_code_seq', greatest(420, (select last_value from realisasi.activity_code_seq)));
end $$;

select pg_temp.bulk_act(396, 'Riset Bersama Sensor Getaran Struktur Jembatan dengan Universitas Gadjah Mada', 65, 4, 'outbound', '2025-10-20', '2026-01-30', 'offline', 'Laboratorium Struktur, Fakultas Teknik UGM, Yogyakarta', 'ID', 28, '{9,11}', 'Riset bersama pengembangan sensor getaran berbasis MEMS untuk pemantauan kesehatan struktur jembatan. Tim Teknik Elektro melakukan kalibrasi prototipe di laboratorium struktur UGM dan menyusun draf artikel bersama sebelum perjanjian kerja sama tersebut diarsipkan.', pg_temp.wib('2026-02-12', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Ir. Bambang Suhendro, M.Sc.", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "researcher"}]', p_co_units => '{28}');
select pg_temp.bulk_act(397, 'Kuliah Tamu Lean Production 4.0 dari Technische Hochschule Deggendorf', 67, 7, 'inbound', '2025-11-12', '2025-11-12', 'offline', 'Auditorium Gedung P PCU', 'ID', 126, '{8,9}', 'Kuliah tamu tentang penerapan lean production yang terintegrasi dengan sensor IoT di industri manufaktur Bavaria, diikuti mahasiswa Teknik Industri dan Informatika.', pg_temp.wib('2025-11-20', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr.-Ing. Markus Hofbauer", "institution": "Technische Hochschule Deggendorf", "country_code": "DE", "role": "speaker"}]', p_co_units => '{28,68}');
select pg_temp.bulk_act(398, 'Short Program Power Electronics di Hochschule Bremen', 65, 23, 'outbound', '2025-10-13', '2025-10-31', 'offline', 'Hochschule Bremen, Campus Neustadtswall', 'DE', 195, '{4,7}', 'Program singkat tiga minggu tentang desain konverter daya dan inverter untuk sistem energi terbarukan. Mahasiswa Teknik Elektro mengikuti kuliah, praktikum laboratorium, dan kunjungan ke industri turbin angin di Bremerhaven.', pg_temp.wib('2026-01-20', '09:00'), 'approved', pg_temp.wib('2026-01-29', '14:00'));
select pg_temp.bulk_pset(398, '{B12239276,B12239596}', '{}', '{PG204517}');
select pg_temp.bulk_act(399, 'Kuliah Tamu Daring Motion Graphics untuk Kampanye Sosial bersama University of Technology Sydney', 63, 7, 'inbound', '2025-12-03', '2025-12-03', 'online', 'Zoom Meeting', null, 206, '{4,17}', 'Kuliah tamu daring tentang perancangan motion graphics untuk kampanye kesadaran sosial, termasuk studi kasus kampanye kesehatan publik di New South Wales dan sesi tanya jawab portofolio.', pg_temp.wib('2025-12-10', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Emma Fitzgerald", "institution": "University of Technology Sydney", "country_code": "AU", "role": "speaker"}]');
select pg_temp.bulk_act(400, 'Inbound Exchange University of Amsterdam di Prodi Manajemen Semester Ganjil 2025/2026', 5, 2, 'inbound', '2025-09-01', '2026-01-16', 'offline', 'Kampus PCU Siwalankerto', 'ID', 166, '{4,17}', 'Mahasiswa pertukaran dari University of Amsterdam mengikuti satu semester perkuliahan reguler Manajemen, termasuk mata kuliah Bisnis Internasional dan kelas Bahasa Indonesia untuk penutur asing.', pg_temp.wib('2026-01-26', '09:00'), 'approved', pg_temp.wib('2026-02-04', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(400, '{}', '{X06269040}', '{PG818524}');
select pg_temp.bulk_act(401, 'Joint Webinar Manajemen Operasi Rantai Halal Asia Tenggara bersama KMUTT', 5, 10, 'inbound', '2025-11-25', '2025-11-25', 'hybrid', 'Ruang Seminar Gedung T PCU', 'ID', 156, '{8,12}', 'Webinar hibrida yang membahas tantangan sertifikasi dan logistik produk halal di Thailand dan Indonesia, dengan pembicara dari KMUTT dan dosen Manajemen PCU.', pg_temp.wib('2025-12-02', '09:00'), null, null, p_ext => '[{"full_name": "Assoc. Prof. Dr. Somchai Prasertsri", "institution": "King Mongkut''s University of Technology Thonburi", "country_code": "TH", "role": "speaker"}]');
select pg_temp.bulk_act(402, 'Staff Exchange Laboratorium Mekatronika ke Universitas Gadjah Mada', 65, 3, 'outbound', '2026-05-11', '2026-05-22', 'offline', 'Departemen Teknik Elektro dan Teknologi Informasi, Fakultas Teknik UGM, Yogyakarta', 'ID', 72, '{4,9}', 'Dua dosen Teknik Elektro menjalani program pertukaran staf di laboratorium mekatronika UGM untuk mempelajari tata kelola laboratorium riset dan merancang praktikum bersama di bawah perjanjian yang masih berlaku.', pg_temp.wib('2026-06-03', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Ir. Adha Imam Cahyadi, M.Eng.", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "staff_visitor"}]', p_co_units => '{28}');
select pg_temp.bulk_act(403, 'Program Budaya Seni Tradisi Jawa untuk Mahasiswa Yonsei University', 63, 29, 'inbound', '2026-02-09', '2026-03-20', 'offline', 'Studio Desain Gedung P PCU', 'ID', 31, '{4,11}', 'Mahasiswa Yonsei University mengikuti program enam minggu tentang batik, wayang, dan ragam hias Jawa Timur, ditutup dengan pameran karya kolaboratif bersama mahasiswa Desain Komunikasi Visual.', pg_temp.wib('2026-05-04', '09:00'), 'approved', pg_temp.wib('2026-05-12', '14:00'), p_co_units => '{32}');
select pg_temp.bulk_pset(403, '{}', '{X05269037}', '{PG761401}');
select pg_temp.bulk_act(404, 'Online Course Cloud Native Development dari Temasek Polytechnic', 68, 79, 'inbound', '2026-03-02', '2026-04-24', 'online', 'Microsoft Teams', null, 188, '{4,9}', 'Kursus daring delapan minggu tentang container, Kubernetes, dan CI/CD yang diampu dosen Temasek Polytechnic untuk mahasiswa Informatika, dengan proyek akhir deployment aplikasi mikroservis.', pg_temp.wib('2026-05-06', '09:00'), null, null, p_ext => '[{"full_name": "Mr. Lim Wei Jie", "institution": "Temasek Polytechnic", "country_code": "SG", "role": "visiting_lecturer"}]');
select pg_temp.bulk_act(405, 'Pameran Bersama Tipografi Nusantara bersama ITB', 63, 35, 'outbound', '2026-04-20', '2026-04-25', 'offline', 'Galeri Soemardja, Institut Teknologi Bandung', 'ID', 208, '{4,11}', 'Pameran karya tipografi berbasis aksara daerah hasil kolaborasi mahasiswa DKV PCU dan FSRD ITB, disertai diskusi kuratorial tentang digitalisasi aksara Nusantara.', pg_temp.wib('2026-05-02', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Andi Wiranata, M.Sn.", "institution": "Institut Teknologi Bandung", "country_code": "ID", "role": "other"}]');
select pg_temp.bulk_act(406, 'Pengabdian Masyarakat Pembukuan Digital UMKM Kampung Lawas Maspati bersama Universitas Surabaya', 6, 40, 'outbound', '2026-06-15', '2026-06-19', 'offline', 'Kampung Lawas Maspati, Surabaya', 'ID', 158, '{1,8}', 'Dosen dan mahasiswa Akuntansi bersama tim Universitas Surabaya mendampingi pelaku UMKM kampung wisata dalam pencatatan keuangan sederhana menggunakan aplikasi kasir digital.', pg_temp.wib('2026-08-10', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Rahmawati Santoso, S.E., M.Ak.", "institution": "Universitas Surabaya", "country_code": "ID", "role": "other"}]', p_co_units => '{4}');
select pg_temp.bulk_act(407, 'Inbound Credit Transfer Informatika Universiti Teknologi Malaysia 2026', 68, 33, 'inbound', '2026-07-20', '2026-09-11', 'offline', 'Laboratorium Informatika Gedung P PCU', 'ID', 107, '{4,9}', 'Mahasiswa Universiti Teknologi Malaysia mengambil dua mata kuliah Informatika (Pemrograman Mobile dan Data Mining) dengan pengakuan kredit di kampus asal.', pg_temp.daysago(2, '09:00'), 'pending', pg_temp.daysago(2, '09:00'));
select pg_temp.bulk_pset(407, '{}', '{X06269039}', '{PG564518}');
select pg_temp.bulk_act(408, 'Academic Exchange Sistem Kendali Cerdas National University of Singapore 2026', 65, 28, 'inbound', '2026-08-03', '2026-09-25', 'offline', 'Laboratorium Teknik Elektro Gedung W PCU', 'ID', 19, '{4,7}', 'Mahasiswa National University of Singapore melakukan pertukaran akademik di laboratorium Teknik Elektro, mengerjakan proyek kendali cerdas untuk sistem panel surya skala kecil.', pg_temp.daysago(5, '09:00'), 'pending', pg_temp.daysago(5, '09:00'));
select pg_temp.bulk_pset(408, '{}', '{X06269036}', '{PG703063}');
select pg_temp.bulk_act(409, 'Magang Akuntansi dan Logistik Internasional di KMUTT Bangkok', 6, 21, 'outbound', '2026-08-03', '2026-09-11', 'offline', 'KMUTT Bang Mod Campus, Bangkok', 'TH', 156, '{8,17}', 'Mahasiswa Akuntansi magang enam minggu di unit keuangan dan logistik KMUTT serta mitra industrinya, mempelajari pelaporan biaya rantai pasok lintas negara.', pg_temp.daysago(8, '09:00'), 'pending', pg_temp.daysago(8, '09:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(409, '{D32239187,D32249796}', '{}', '{PG818524}');
select pg_temp.bulk_act(410, 'Short Program Animation and Game Art di University of Technology Sydney', 63, 23, 'outbound', '2026-08-17', '2026-09-11', 'offline', 'UTS City Campus, Ultimo, Sydney', 'AU', 206, '{4,9}', 'Program singkat empat minggu tentang animasi 3D dan desain aset gim, ditutup dengan presentasi prototipe gim pendek di depan dosen UTS.', pg_temp.daysago(11, '09:00'), 'pending', pg_temp.daysago(11, '09:00'));
select pg_temp.bulk_pset(410, '{C21229761,C21239657,C21239466}', '{}', '{PG452412}');
select pg_temp.bulk_act(411, 'Studi Ekskursi Industri Otomotif Thailand bersama Chulalongkorn University', 68, 24, 'outbound', '2026-08-24', '2026-08-29', 'offline', 'Faculty of Engineering, Chulalongkorn University', 'TH', 151, '{9,12}', 'Kunjungan studi ke Chulalongkorn University dan kawasan industri otomotif Rayong untuk mempelajari otomasi lini perakitan dan sistem informasi manufaktur.', pg_temp.daysago(12, '09:00'), 'pending', pg_temp.daysago(12, '09:00'), p_co_units => '{28}');
select pg_temp.bulk_pset(411, '{B11239024,B11239809,B11229632}', '{}', '{PG707752}');
select pg_temp.bulk_act(412, 'Credit Transfer Kewirausahaan Sosial di Chulalongkorn University', 5, 33, 'outbound', '2026-08-10', '2026-09-11', 'offline', 'Sasin School of Management, Chulalongkorn University, Bangkok', 'TH', 25, '{4,8}', 'Mahasiswa Manajemen mengikuti mata kuliah Kewirausahaan Sosial di Chulalongkorn University selama lima minggu dengan pengakuan kredit, termasuk proyek lapangan bersama koperasi petani di Nakhon Pathom.', pg_temp.daysago(15, '09:00'), 'revision_requested', pg_temp.daysago(6, '14:00'), p_mnote => 'NRP peserta D31239267 pada daftar peserta tidak sama dengan NRP di surat tugas (tertulis D31239276). Mohon periksa kembali NRP dan unggah ulang surat tugas yang benar.');
select pg_temp.bulk_pset(412, '{D31239924,D31239267}', '{}', '{PG295222}');
select pg_temp.bulk_act(413, 'Program Imersi Budaya Visual Filipina bersama Ateneo de Manila University', 63, 22, 'outbound', '2026-08-17', '2026-09-04', 'offline', 'Ateneo de Manila University, Loyola Heights, Quezon City', 'PH', 133, '{4,11}', 'Program imersi tiga minggu tentang budaya visual Filipina: kunjungan museum, lokakarya ilustrasi jeepney art, dan kolaborasi poster dengan mahasiswa Ateneo.', pg_temp.daysago(18, '09:00'), 'revision_requested', pg_temp.daysago(9, '14:00'), p_mnote => 'Transkrip nilai C21249938 hanya memuat halaman 1 dari 2; halaman rincian mata kuliah dan tanda tangan registrar Ateneo belum ada. Mohon unggah transkrip lengkap.');
select pg_temp.bulk_pset(413, '{C21259377,C21249938}', '{}', '{PG780858}');
select pg_temp.bulk_act(414, 'Academic Exchange Laboratorium Robotika Kanazawa Institute of Technology', 65, 28, 'outbound', '2026-08-31', '2026-09-18', 'offline', 'Ogigaoka Campus, Kanazawa Institute of Technology', 'JP', 105, '{4,9}', 'Mahasiswa Teknik Elektro bergabung dengan laboratorium robotika Kanazawa Institute of Technology selama tiga minggu untuk mengembangkan pengendali lengan robot berbasis visi komputer.', pg_temp.daysago(9, '09:00'), 'revision_requested', pg_temp.daysago(3, '14:00'), p_mnote => 'Tanggal kegiatan (31 Agustus - 18 September 2026) tidak sesuai dengan surat tugas No. 412/FTI/VIII/2026 yang mencantumkan 1 - 19 September 2026. Mohon sesuaikan tanggal kegiatan atau unggah surat tugas revisi.');
select pg_temp.bulk_pset(414, '{B12239147,B12239970}', '{}', '{PG413450}');
select pg_temp.bulk_act(415, 'Pelatihan Daring Analitik Data Pelanggan bersama Universiti Brunei Darussalam', 5, 69, 'inbound', '2026-08-18', '2026-08-20', 'online', 'Microsoft Teams', null, 174, '{4,8}', 'Pelatihan daring tiga hari tentang segmentasi pelanggan dan analitik churn menggunakan data ritel anonim, dibawakan dosen UBD School of Business and Economics untuk mahasiswa dan dosen Manajemen.', pg_temp.wib('2026-08-27', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Nurul Aisyah binti Haji Abdullah", "institution": "Universiti Brunei Darussalam", "country_code": "BN", "role": "speaker"}]');
select pg_temp.bulk_act(416, 'Kuliah Tamu Cybersecurity Operations Center dari University of Amsterdam', 68, 15, 'inbound', '2026-08-12', '2026-08-12', 'offline', 'Auditorium Gedung P PCU', 'ID', 191, '{4,9}', 'Kuliah tamu tentang operasional Security Operations Center, simulasi penanganan insiden, dan jalur karier keamanan siber bagi mahasiswa Informatika.', null, null, null, p_ext => '[{"full_name": "Dr. Pieter van der Berg", "institution": "University of Amsterdam", "country_code": "NL", "role": "speaker"}]');
select pg_temp.bulk_act(417, 'Seminar Bersama Ekonomi Digital Taiwan-Indonesia dengan National Taiwan University', 5, 10, 'inbound', '2026-09-22', '2026-09-22', 'hybrid', 'Ruang Seminar Gedung T PCU', 'ID', 30, '{8,17}', 'Seminar hibrida yang membandingkan ekosistem platform digital dan regulasi e-commerce di Taiwan dan Indonesia, dengan pembicara dari National Taiwan University.', null, null, null, p_files => '{ia}', p_ext => '[{"full_name": "Prof. Dr. Chen Wei-ting", "institution": "National Taiwan University", "country_code": "TW", "role": "speaker"}]', p_co_units => '{4}');
select pg_temp.bulk_act(418, 'Penyusunan Kurikulum Bersama Desain Interaktif dengan Hochschule Bremen', 63, 32, 'inbound', '2026-09-14', '2026-09-25', 'offline', 'Ruang Rapat Gedung P PCU', 'ID', 205, '{4,17}', 'Lokakarya penyusunan kurikulum bersama mata kuliah Desain Interaktif dan UX, menyelaraskan capaian pembelajaran DKV PCU dengan program Hochschule Bremen untuk rencana pengakuan kredit.', null, null, null, p_files => '{ia}', p_ext => '[{"full_name": "Prof. Dr. Katrin Schulte", "institution": "Hochschule Bremen", "country_code": "DE", "role": "visiting_lecturer"}]');
select pg_temp.bulk_act(419, 'Winter Program Renewable Energy Systems di Kyoto Sangyo University', 65, 23, 'outbound', '2026-11-23', '2026-12-04', 'offline', 'Kamigamo Campus, Kyoto Sangyo University', 'JP', 11, '{7,13}', 'Program musim dingin dua minggu tentang integrasi energi surya dan penyimpanan baterai, termasuk praktikum laboratorium dan kunjungan ke fasilitas smart grid di Kyoto.', null, null, null, p_files => '{}');
select pg_temp.bulk_pset(419, '{B12239276,B12239596}', '{}', '{PG204517}');
select pg_temp.bulk_act(420, 'Kuliah Tamu Model Bisnis Industrie 4.0 dari Ludwig Maximilian University of Munich', 5, 7, 'inbound', '2026-12-08', '2026-12-08', 'offline', 'Auditorium Gedung W PCU', 'ID', 42, '{8,9}', 'Kuliah tamu perdana dalam kerja sama baru dengan Ludwig Maximilian University of Munich tentang model bisnis berbasis Industrie 4.0 dan transformasi digital UKM manufaktur Jerman.', null, null, null, p_files => '{}', p_ext => '[{"full_name": "Prof. Dr. Thomas Weber", "institution": "Ludwig Maximilian University of Munich", "country_code": "DE", "role": "speaker"}]', p_co_units => '{4}');

select pg_temp.bulk_verify(396, 420);
