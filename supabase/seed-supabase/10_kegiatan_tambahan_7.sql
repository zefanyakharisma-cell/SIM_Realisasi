-- seed-supabase/10_kegiatan_tambahan_7 (simks-partnership): additional bulk kegiatan 371-395, adapted from the local
-- demo seed supabase/seed/04_bulk_7.sql to the real SIM Kerjasama units (Program Studi submitters) and agreements.
-- Generated from a reviewed JSON list; every row passes the guards below (agreement valid for the dates, submission
-- after the end date, Mobility decision after the submission, participant set for every submitted mobility kegiatan,
-- no student in two overlapping kegiatan, unique names). Needs 03_accounts.sql and 09_registries_tambahan.sql.
-- Self-contained and idempotent (existing rows are skipped), so it can be run on its own: Supabase SQL Editor or one
-- statement batch. Writes only realisasi.*; SIM Kerjasama tables are only read.

-- The kegiatan reference SIM Kerjasama agreements 25, 30, 31, 38, 62, 100, 105, 107, 108, 112, 117, 133, 137, 156, 158, 166, 188, 190, 191, 200, 205, 206. Where any is missing (e.g. the local
-- --rehearse fixture, which only mirrors agreements 11-52) the whole file is skipped with a notice instead of failing.
drop table if exists pg_temp.tambahan_skip;
create temp table tambahan_skip as
select exists (select 1 from unnest('{25,30,31,38,62,100,105,107,108,112,117,133,137,156,158,166,188,190,191,200,205,206}'::int[]) d where not exists (select 1 from kerjasama.documents k where k.id = d)) as skip;
do $$ begin if (select skip from pg_temp.tambahan_skip) then
  raise notice '10_kegiatan_tambahan_7: SIM Kerjasama agreements missing, kegiatan 371-395 skipped'; end if; end $$;


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

select pg_temp.bulk_act(371, 'Program Imersi Lintas Disiplin Design Thinking & Business Innovation di Hong Kong Baptist University', 5, 22, 'outbound', '2025-08-11', '2025-08-22', 'offline', 'HKBU Kowloon Tong Campus, Hong Kong', 'HK', 62, '{4,8,9}', 'Program imersi gabungan SBM dan Fakultas Humaniora dan Industri Kreatif di Hong Kong Baptist University: mahasiswa Manajemen, Akuntansi, dan DKV bekerja dalam tim lintas disiplin merancang prototipe bisnis kreatif dengan metode design thinking, ditutup dengan pitching di depan mentor HKBU.', pg_temp.wib('2025-08-29', '09:00'), 'approved', pg_temp.wib('2025-09-05', '14:00'), p_co_units => '{4,32}');
select pg_temp.bulk_pset(371, '{D31239877,D31239764,D32249932,C21229456,C21239107}', '{}', '{PG818524}');
select pg_temp.bulk_act(372, 'Pameran Bersama Desain Produk Berkelanjutan FTI–FHIK bersama ITB', 67, 35, 'inbound', '2025-09-15', '2025-09-19', 'offline', 'Galeri Gedung P PCU', 'ID', 137, '{9,12}', 'Pameran karya bersama mahasiswa Teknik Industri, Teknik Elektro, dan program desain PCU dengan Fakultas Seni Rupa dan Desain ITB yang menampilkan 40 prototipe produk ramah lingkungan, dilengkapi sesi kurasi dan diskusi panel tentang material daur ulang.', pg_temp.wib('2025-09-25', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Andar Bagus Sriwarno, M.Ds.", "institution": "Institut Teknologi Bandung", "country_code": "ID", "role": "speaker"}, {"full_name": "Prof. Dr. Imam Santosa, M.Sn.", "institution": "Institut Teknologi Bandung", "country_code": "ID", "role": "speaker"}]', p_co_units => '{28,32,65}');
select pg_temp.bulk_act(373, 'International Conference on Applied Computing, Embedded Systems and Smart Manufacturing (ICACES) 2025 bersama Temasek Polytechnic', 67, 10, 'inbound', '2025-10-08', '2025-10-09', 'hybrid', 'Auditorium Gedung W PCU', 'ID', 188, '{4,9,17}', 'Konferensi internasional yang diselenggarakan Prodi Teknik Industri bersama FTI, Prodi Informatika, Teknik Elektro, dan Kantor Kerja Sama dan Urusan Internasional dengan Temasek Polytechnic; menghadirkan 62 makalah tentang sistem tertanam, IoT, dan manufaktur cerdas serta keynote dari School of Engineering TP.', pg_temp.wib('2025-10-20', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Lim Wei Sheng", "institution": "Temasek Polytechnic", "country_code": "SG", "role": "speaker"}, {"full_name": "Ms. Tan Hui Min", "institution": "Temasek Polytechnic", "country_code": "SG", "role": "speaker"}]', p_co_units => '{28,68,65,2}');
select pg_temp.bulk_act(374, 'Student Exchange Semester Ganjil Informatika dan DKV di NTUST Taipei', 68, 2, 'outbound', '2025-09-01', '2026-01-16', 'offline', 'NTUST Gongguan Campus, Taipei', 'TW', 200, '{4,9}', 'Pertukaran satu semester bagi mahasiswa Informatika dan DKV di National Taiwan University of Science and Technology; peserta mengambil mata kuliah Human-Computer Interaction dan Interactive Media Design yang diakui melalui transfer kredit.', pg_temp.wib('2026-01-26', '09:00'), 'approved', pg_temp.wib('2026-02-04', '14:00'), p_co_units => '{28,32,63}');
select pg_temp.bulk_pset(374, '{B11229965,B11239432,C21249850}', '{}', '{}');
select pg_temp.bulk_act(375, 'Inbound Academic Exchange Kanazawa Institute of Technology di Laboratorium Sistem Kontrol', 65, 28, 'inbound', '2025-10-01', '2025-12-19', 'offline', 'Laboratorium Sistem Kontrol Gedung P PCU', 'ID', 105, '{4,9}', 'Mahasiswa Kanazawa Institute of Technology mengikuti pertukaran akademik di Prodi Teknik Elektro dengan pembimbingan bersama dosen Teknik Elektro dan Informatika, mengerjakan proyek sistem kontrol robot pemindah barang berbasis visi komputer.', pg_temp.wib('2025-12-29', '09:00'), 'approved', pg_temp.wib('2026-01-08', '14:00'), p_co_units => '{28,68}');
select pg_temp.bulk_pset(375, '{}', '{X05269034}', '{PG413450}');
select pg_temp.bulk_act(376, 'Kuliah Bersama Brand Strategy & Visual Identity dengan University of Amsterdam', 5, 34, 'inbound', '2025-11-04', '2025-11-25', 'online', 'Zoom Meeting', null, 166, '{4,8}', 'Empat sesi kuliah bersama daring antara SBM, Prodi Manajemen, dan Prodi DKV dengan Amsterdam Business School, University of Amsterdam, tentang strategi merek dan identitas visual; mahasiswa lintas prodi menyusun brand audit untuk UMKM Surabaya.', pg_temp.wib('2025-12-02', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Femke van Horen", "institution": "University of Amsterdam", "country_code": "NL", "role": "visiting_lecturer"}]', p_co_units => '{4,63}');
select pg_temp.bulk_act(377, 'Batik dan Desain Nusantara: Program Budaya Mahasiswa Hochschule Bremen', 63, 29, 'inbound', '2025-11-10', '2025-11-28', 'offline', 'Kampus PCU Siwalankerto', 'ID', 205, '{4,11}', 'Program pertukaran budaya tiga minggu untuk mahasiswa Hochschule Bremen yang dikelola Prodi DKV, Fakultas Humaniora dan Industri Kreatif, serta Kantor Kerja Sama dan Urusan Internasional: lokakarya batik, kunjungan sentra kriya Madura, dan proyek desain motif kontemporer bersama mahasiswa DKV.', pg_temp.wib('2025-12-05', '09:00'), 'approved', pg_temp.wib('2025-12-12', '14:00'), p_co_units => '{32,2}');
select pg_temp.bulk_pset(377, '{}', '{X05269035}', '{PG780858}');
select pg_temp.bulk_act(378, 'Service Learning Digitalisasi UMKM Kampung Lontong bersama Universitas Pelita Harapan', 6, 40, 'outbound', '2025-12-01', '2025-12-12', 'offline', 'Kampung Lontong Banyu Urip, Surabaya', 'ID', 112, '{1,8,17}', 'Pengabdian masyarakat Prodi Akuntansi bersama SBM, Prodi Manajemen, dan Prodi Informatika dengan Universitas Pelita Harapan: pendampingan pencatatan keuangan sederhana, katalog digital, dan pembayaran QRIS bagi 25 pelaku UMKM lontong.', pg_temp.wib('2025-12-18', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Rahmat Setiawan, S.E., M.M.", "institution": "Universitas Pelita Harapan", "country_code": "ID", "role": "other"}]', p_co_units => '{4,5,68}');
select pg_temp.bulk_act(379, 'Winter Short Program Smart Factory & Electrical Engineering di Kanazawa Institute of Technology', 65, 23, 'outbound', '2026-02-02', '2026-02-20', 'offline', 'Kanazawa Institute of Technology, Ogigaoka Campus', 'JP', 105, '{4,7,9}', 'Program singkat tiga minggu bagi mahasiswa Teknik Elektro dan Informatika di Kanazawa Institute of Technology: kuliah otomasi pabrik, praktikum PLC dan sensor, serta kunjungan ke fasilitas manufaktur di wilayah Hokuriku.', pg_temp.wib('2026-03-02', '09:00'), 'approved', pg_temp.wib('2026-03-10', '14:00'), p_co_units => '{28,68}');
select pg_temp.bulk_pset(379, '{B12239310,B12249808,B12259428,B11229081}', '{}', '{PG204517}');
select pg_temp.bulk_act(380, 'Inbound Student Exchange National Taiwan University Genap 2026 di Prodi Manajemen', 5, 2, 'inbound', '2026-02-09', '2026-06-26', 'offline', 'Gedung T PCU', 'ID', 30, '{4,17}', 'Mahasiswa National Taiwan University mengikuti satu semester di Prodi Manajemen dengan mata kuliah pilihan dari SBM (Pemasaran Digital, Kewirausahaan Asia Tenggara) dan didampingi buddy mahasiswa Manajemen.', pg_temp.wib('2026-07-06', '09:00'), 'approved', pg_temp.wib('2026-07-15', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(380, '{}', '{X06269031}', '{PG295222}');
select pg_temp.bulk_act(381, 'Inbound Study Abroad Monash: International Business in Southeast Asia', 5, 20, 'inbound', '2026-02-16', '2026-06-12', 'offline', 'Gedung T PCU', 'ID', 108, '{4,8,17}', 'Program study abroad satu semester untuk mahasiswa Monash University yang dikelola Prodi Manajemen, SBM, dan Kantor Kerja Sama dan Urusan Internasional; mencakup modul bisnis internasional Asia Tenggara, kunjungan industri Surabaya, dan proyek konsultasi bersama mahasiswa lokal.', pg_temp.wib('2026-06-22', '09:00'), 'approved', pg_temp.wib('2026-07-01', '14:00'), p_co_units => '{4,2}');
select pg_temp.bulk_pset(381, '{}', '{X06259033}', '{PG974721}');
select pg_temp.bulk_act(382, 'Petra–KMUTT International Week 2026: Sustainable Business and Creative Economy', 63, 10, 'inbound', '2026-03-09', '2026-03-13', 'hybrid', 'Auditorium Gedung W PCU', 'ID', 156, '{8,12,17}', 'Pekan internasional tingkat universitas yang diselenggarakan Prodi DKV, Fakultas Humaniora dan Industri Kreatif, SBM, Kantor Kerja Sama dan Urusan Internasional, dan Rektorat bersama KMUTT: seminar ekonomi kreatif, lokakarya kemasan berkelanjutan, dan pameran startup mahasiswa kedua kampus.', pg_temp.wib('2026-03-20', '09:00'), null, null, p_ext => '[{"full_name": "Assoc. Prof. Dr. Suthep Wongsawat", "institution": "King Mongkut''s University of Technology Thonburi", "country_code": "TH", "role": "speaker"}, {"full_name": "Dr. Pimchanok Rattanakul", "institution": "King Mongkut''s University of Technology Thonburi", "country_code": "TH", "role": "speaker"}]', p_co_units => '{32,4,2,1}');
select pg_temp.bulk_act(383, 'Riset Bersama Antarmuka Augmented Reality untuk Museum dengan University of Amsterdam', 68, 4, 'inbound', '2026-02-02', '2026-06-30', 'hybrid', 'Laboratorium Multimedia Gedung P PCU', 'ID', 191, '{9,11}', 'Penelitian bersama Prodi Informatika, Fakultas Humaniora dan Industri Kreatif, dan Prodi DKV dengan University of Amsterdam untuk merancang antarmuka AR pemandu koleksi Museum House of Sampoerna; luaran berupa prototipe aplikasi, uji pengguna dengan 60 pengunjung, dan draf artikel jurnal.', pg_temp.wib('2026-08-05', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Julia Noordegraaf", "institution": "University of Amsterdam", "country_code": "NL", "role": "researcher"}]', p_co_units => '{28,32,63}');
select pg_temp.bulk_act(384, 'Magang Industri Kreatif dan Teknologi di Pusat Inovasi Temasek Polytechnic', 68, 21, 'outbound', '2026-06-01', '2026-07-24', 'offline', 'Temasek Polytechnic, Tampines Campus', 'SG', 188, '{4,8}', 'Magang delapan minggu bagi mahasiswa Informatika dan DKV di pusat inovasi Temasek Polytechnic, mengerjakan proyek aplikasi interaktif untuk klien industri di bawah supervisi bersama FTI dan Prodi DKV.', pg_temp.wib('2026-08-03', '09:00'), 'approved', pg_temp.wib('2026-08-12', '14:00'), p_co_units => '{28,63}');
select pg_temp.bulk_pset(384, '{B11259395,B11249182,C21249850}', '{}', '{PG564518}');
select pg_temp.bulk_act(385, 'Pengembangan Kurikulum Bersama Minor Technopreneurship FTI–SBM dengan UTM', 67, 11, 'inbound', '2026-04-06', '2026-04-08', 'online', 'Microsoft Teams', null, 107, '{4,8,9}', 'Lokakarya daring tiga hari antara Prodi Teknik Industri, FTI, SBM, dan Prodi Manajemen dengan Universiti Teknologi Malaysia untuk menyusun capaian pembelajaran dan struktur 20 SKS minor technopreneurship lintas fakultas.', pg_temp.wib('2026-04-15', '09:00'), null, null, p_ext => '[{"full_name": "Assoc. Prof. Dr. Nor Haslinda Ismail", "institution": "Universiti Teknologi Malaysia", "country_code": "MY", "role": "other"}]', p_co_units => '{28,4,5}');
select pg_temp.bulk_act(386, 'Workshop Bersama Desain Interior dan Rekayasa Material Bambu di UGM', 59, 35, 'outbound', '2026-05-11', '2026-05-13', 'offline', 'Kampus UGM Bulaksumur, Yogyakarta', 'ID', 117, '{9,12}', 'Lokakarya tiga hari dosen Desain Interior, DKV, dan FTI bersama Departemen Teknik Mesin dan Industri UGM tentang pemanfaatan limbah tekstil dan bambu sebagai material interior, menghasilkan rencana proyek bersama 2026/2027.', pg_temp.wib('2026-05-20', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Ir. Ratna Kusumawardani, M.T.", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "speaker"}]', p_co_units => '{32,63,28}');
select pg_temp.bulk_act(387, 'Pelatihan Akuntansi Digital dan Analitik Bisnis bersama Universitas Surabaya', 6, 43, 'outbound', '2026-07-13', '2026-07-17', 'offline', 'Fakultas Bisnis dan Ekonomika Ubaya, Kampus Tenggilis Surabaya', 'ID', 158, '{4,8}', 'Pelatihan lima hari bagi dosen dan asisten Prodi Akuntansi, SBM, dan Prodi Manajemen di Fakultas Bisnis dan Ekonomika Universitas Surabaya tentang otomasi akuntansi berbasis cloud dan dashboard analitik bisnis, ditutup dengan sertifikasi internal.', pg_temp.wib('2026-07-27', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Yie Ke Feliana, S.E., M.Comm., Ak.", "institution": "Universitas Surabaya", "country_code": "ID", "role": "speaker"}]', p_co_units => '{4,5}');
select pg_temp.bulk_act(388, 'Yonsei International Summer School 2026 Business and Culture Track', 5, 23, 'outbound', '2026-08-03', '2026-08-21', 'offline', 'Yonsei University Sinchon Campus, Seoul', 'KR', 31, '{4,8,17}', 'Summer school internasional yang dikoordinasikan Kantor Kerja Sama dan Urusan Internasional bersama SBM dan Prodi Manajemen; mahasiswa Manajemen dan Akuntansi mengikuti modul Korean business culture dan corporate visit ke Seoul.', pg_temp.wib('2026-08-28', '09:00'), 'approved', pg_temp.wib('2026-09-07', '14:00'), p_co_units => '{4,6,2}');
select pg_temp.bulk_pset(388, '{D31249852,D31229441,D32239280,D32239903}', '{}', '{PG214411}');
select pg_temp.bulk_act(389, 'Inbound Summer Program Chulalongkorn University: Akuntansi dan Bisnis Digital Indonesia', 5, 23, 'inbound', '2026-08-03', '2026-08-28', 'offline', 'Gedung T PCU', 'ID', 25, '{4,8}', 'Program singkat empat minggu untuk mahasiswa Chulalongkorn University yang diselenggarakan Prodi Manajemen, Prodi Akuntansi, SBM, dan Kantor Kerja Sama dan Urusan Internasional: kuliah akuntansi dan ekosistem bisnis digital Indonesia serta kunjungan ke startup Surabaya.', pg_temp.daysago(12, '09:00'), 'pending', pg_temp.daysago(12, '09:00'), p_co_units => '{4,6,2}');
select pg_temp.bulk_pset(389, '{}', '{X05269032}', '{PG637448}');
select pg_temp.bulk_act(390, 'Short Course Teknologi Energi Terbarukan dan IoT di Universiti Teknologi Malaysia', 65, 22, 'outbound', '2026-08-24', '2026-09-04', 'offline', 'Universiti Teknologi Malaysia, Johor Bahru', 'MY', 107, '{4,7,13}', 'Program imersi dua minggu bagi mahasiswa Teknik Elektro dan Informatika di UTM tentang sistem panel surya, manajemen energi berbasis IoT, dan kunjungan ke pembangkit tenaga surya di Johor.', pg_temp.daysago(8, '09:00'), 'pending', pg_temp.daysago(8, '09:00'), p_co_units => '{28,68}');
select pg_temp.bulk_pset(390, '{B12239310,B12239803,B11229081}', '{}', '{PG703063}');
select pg_temp.bulk_act(391, 'Pertukaran Budaya Desain dan Bisnis Kreatif di Ateneo de Manila University', 63, 29, 'outbound', '2026-08-10', '2026-08-21', 'offline', 'Ateneo de Manila University, Loyola Heights, Quezon City', 'PH', 133, '{4,8,11}', 'Pertukaran budaya dua minggu mahasiswa DKV, Manajemen, dan Akuntansi di Ateneo de Manila University dengan lokakarya ekonomi kreatif Filipina, kunjungan komunitas seniman Intramuros, dan presentasi proyek kolaboratif.', pg_temp.daysago(15, '09:00'), 'revision_requested', pg_temp.daysago(9, '14:00'), p_mnote => 'Sertifikat partisipasi dari Ateneo de Manila University untuk D31249140 dan D32249413 belum ada di bundel mobilitas, dan dosen pendamping belum dicantumkan; mohon lengkapi lalu ajukan ulang.', p_co_units => '{32,4}');
select pg_temp.bulk_pset(391, '{C21229874,C21239176,D31249140,D32249413}', '{}', '{}');
select pg_temp.bulk_act(392, 'Kuliah Tamu Internet of Things untuk Smart Building dari Chulalongkorn University', 65, 15, 'inbound', '2026-09-08', '2026-09-08', 'hybrid', 'Auditorium Gedung P PCU', 'ID', 38, '{7,9,11}', 'Kuliah tamu gabungan Prodi Teknik Elektro, FTI, dan Prodi Informatika tentang integrasi IoT dan sistem manajemen energi gedung, dihadiri 180 mahasiswa luring dan daring.', pg_temp.wib('2026-09-14', '09:00'), null, null, p_ext => '[{"full_name": "Asst. Prof. Dr. Kittipong Srisuk", "institution": "Chulalongkorn University", "country_code": "TH", "role": "speaker"}]', p_co_units => '{28,68}');
select pg_temp.bulk_act(393, 'Kunjungan Akademik Pimpinan Universitas ke Kanazawa Institute of Technology untuk Penjajakan Joint Lab', 69, 27, 'outbound', '2026-09-14', '2026-09-17', 'offline', 'Kanazawa Institute of Technology, Yatsukaho Campus', 'JP', 190, '{9,17}', 'Kunjungan delegasi Prodi Teknik Mesin dan FTI bersama Rektorat serta Kantor Kerja Sama dan Urusan Internasional ke Kanazawa Institute of Technology untuk meninjau fasilitas riset material komposit dan robotika serta menyepakati rencana joint laboratory.', pg_temp.wib('2026-09-24', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Takahiro Nakamura", "institution": "Kanazawa Institute of Technology", "country_code": "JP", "role": "other"}]', p_co_units => '{28,1,2}');
select pg_temp.bulk_act(394, 'Joint Exhibition Petra–UTS Visual Storytelling 2026', 63, 35, 'inbound', '2026-11-16', '2026-11-20', 'offline', 'Galeri Gedung P PCU', 'ID', 206, '{4,11}', 'Rencana pameran bersama karya visual storytelling mahasiswa DKV PCU dan University of Technology Sydney, didukung Kantor Kerja Sama dan Urusan Internasional, dengan sesi artist talk dan lokakarya komik digital.', null, null, null, p_files => '{ia}', p_co_units => '{32,2}');
select pg_temp.bulk_act(395, 'Fontys Winter School International Marketing 2027', 5, 23, 'outbound', '2027-01-11', '2027-01-22', 'offline', 'Fontys University of Applied Sciences, Eindhoven', 'NL', 100, '{4,8}', 'Rencana winter school dua minggu di Fontys bagi mahasiswa Manajemen dan Akuntansi yang dikoordinasikan SBM dan Kantor Kerja Sama dan Urusan Internasional, berfokus pada pemasaran internasional dan riset pasar Eropa.', null, null, null, p_co_units => '{4,6,2}');
select pg_temp.bulk_pset(395, '{D31239877,D32249932}', '{}', '{}');

select pg_temp.bulk_verify(371, 395);
