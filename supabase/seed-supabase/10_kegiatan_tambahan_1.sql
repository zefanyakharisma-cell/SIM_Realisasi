-- seed-supabase/10_kegiatan_tambahan_1 (simks-partnership): additional bulk kegiatan 221-245, adapted from the local
-- demo seed supabase/seed/04_bulk_1.sql to the real SIM Kerjasama units (Program Studi submitters) and agreements.
-- Generated from a reviewed JSON list; every row passes the guards below (agreement valid for the dates, submission
-- after the end date, Mobility decision after the submission, participant set for every submitted mobility kegiatan,
-- no student in two overlapping kegiatan, unique names). Needs 03_accounts.sql and 09_registries_tambahan.sql.
-- Self-contained and idempotent (existing rows are skipped), so it can be run on its own: Supabase SQL Editor or one
-- statement batch. Writes only realisasi.*; SIM Kerjasama tables are only read.

-- The kegiatan reference SIM Kerjasama agreements 11, 19, 25, 30, 34, 83, 105, 107, 126, 181, 184, 188, 191, 193, 200. Where any is missing (e.g. the local
-- --rehearse fixture, which only mirrors agreements 11-52) the whole file is skipped with a notice instead of failing.
drop table if exists pg_temp.tambahan_skip;
create temp table tambahan_skip as
select exists (select 1 from unnest('{11,19,25,30,34,83,105,107,126,181,184,188,191,193,200}'::int[]) d where not exists (select 1 from kerjasama.documents k where k.id = d)) as skip;
do $$ begin if (select skip from pg_temp.tambahan_skip) then
  raise notice '10_kegiatan_tambahan_1: SIM Kerjasama agreements missing, kegiatan 221-245 skipped'; end if; end $$;


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

select pg_temp.bulk_act(221, 'Kuliah Tamu Machine Learning untuk Visi Komputer dari Kanazawa Institute of Technology', 68, 15, 'inbound', '2025-09-15', '2025-09-16', 'offline', 'Auditorium Gedung P PCU', 'ID', 105, '{4,9}', 'Kuliah tamu dua hari tentang deep learning untuk inspeksi visual di industri manufaktur Jepang, disertai sesi praktik klasifikasi citra cacat produk bagi mahasiswa Informatika semester 5.', pg_temp.wib('2025-09-25', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Hiroshi Tanaka", "institution": "Kanazawa Institute of Technology", "country_code": "JP", "role": "visiting_lecturer"}]');
select pg_temp.bulk_act(222, 'Inbound Student Exchange Informatika Xiamen University Semester Ganjil 2025', 68, 2, 'inbound', '2025-09-01', '2025-12-19', 'offline', 'Kampus PCU Siwalankerto', 'ID', 184, '{4,17}', 'Mahasiswa Xiamen University mengikuti satu semester perkuliahan Informatika di PCU (Pemrograman Web, Basis Data Lanjut, Kecerdasan Buatan) dengan pengakuan kredit di universitas asal.', pg_temp.wib('2026-01-08', '09:00'), 'approved', pg_temp.wib('2026-01-15', '14:00'));
select pg_temp.bulk_pset(222, '{}', '{X06259003}', '{PG557816}');
select pg_temp.bulk_act(223, 'Riset Bersama Sensor IoT untuk Pertanian Presisi dengan Universitas Brawijaya', 65, 4, 'outbound', '2025-10-13', '2025-10-17', 'offline', 'Kebun Percobaan Fakultas Pertanian Universitas Brawijaya, Malang', 'ID', 193, '{2,9}', 'Tim dosen Teknik Elektro melakukan kalibrasi bersama jaringan sensor kelembapan tanah berbasis LoRaWAN di kebun percobaan Universitas Brawijaya serta menyusun rencana publikasi hasil uji lapangan.', pg_temp.wib('2025-10-28', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Ir. Bambang Susilo, M.Sc.Agr.", "institution": "Universitas Brawijaya", "country_code": "ID", "role": "researcher"}]', p_co_units => '{28}');
select pg_temp.bulk_act(224, 'Short Program Data Science and Analytics di NTUST Taipei 2025', 68, 23, 'outbound', '2025-10-20', '2025-11-07', 'offline', 'NTUST Taipei Campus, Department of Computer Science and Information Engineering', 'TW', 200, '{4,9}', 'Program singkat tiga minggu berisi kuliah analitik big data, praktikum Python untuk machine learning, dan proyek kelompok analisis data transportasi publik kota Taipei.', pg_temp.wib('2025-11-20', '09:00'), 'approved', pg_temp.wib('2025-11-27', '14:00'));
select pg_temp.bulk_pset(224, '{B11239558,B11239097,B11229093,B11239548}', '{}', '{PG663266}');
select pg_temp.bulk_act(225, 'Workshop Penyelarasan Kurikulum Rekayasa Perangkat Lunak bersama ITB', 68, 11, 'outbound', '2025-11-17', '2025-11-18', 'offline', 'Kampus ITB Ganesha, Bandung', 'ID', 83, '{4}', 'Lokakarya penyelarasan capaian pembelajaran mata kuliah rekayasa perangkat lunak dan DevOps antara Informatika PCU dan STEI ITB, menghasilkan draf peta mata kuliah setara untuk program pertukaran.', pg_temp.wib('2025-11-28', '09:00'), null, null, p_co_units => '{28}');
select pg_temp.bulk_act(226, 'Inbound Short Program Industrial Automation TH Deggendorf 2025', 67, 23, 'inbound', '2025-11-24', '2025-12-12', 'offline', 'Laboratorium Sistem Manufaktur Gedung P PCU', 'ID', 126, '{4,9,17}', 'Mahasiswa Technische Hochschule Deggendorf mengikuti program tiga minggu tentang otomasi lini produksi dengan PLC dan sistem MES, termasuk kunjungan industri ke kawasan SIER Surabaya.', pg_temp.wib('2025-12-22', '09:00'), 'approved', pg_temp.wib('2026-01-05', '14:00'), p_co_units => '{28}');
select pg_temp.bulk_pset(226, '{}', '{X05259004}', '{PG681184}');
select pg_temp.bulk_act(227, 'Kuliah Bersama Cloud Computing dengan University of Amsterdam', 68, 34, 'inbound', '2025-09-08', '2025-12-12', 'online', 'Microsoft Teams', null, 191, '{4,9}', 'Mata kuliah Cloud Computing diajarkan bersama secara daring oleh dosen Informatika PCU dan dosen University of Amsterdam selama satu semester, mencakup arsitektur serverless dan kontainerisasi.', pg_temp.wib('2025-12-18', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Pieter de Vries", "institution": "University of Amsterdam", "country_code": "NL", "role": "visiting_lecturer"}]');
select pg_temp.bulk_act(228, 'Magang Smart Factory di Technische Hochschule Deggendorf', 67, 21, 'outbound', '2026-01-05', '2026-01-30', 'offline', 'Technologie Campus Cham, Technische Hochschule Deggendorf', 'DE', 126, '{8,9}', 'Mahasiswa Teknik Industri magang di laboratorium smart production TH Deggendorf, mengerjakan pemetaan aliran nilai dan integrasi sensor untuk lini perakitan cerdas skala pilot.', pg_temp.wib('2026-02-12', '09:00'), 'approved', pg_temp.wib('2026-02-20', '14:00'));
select pg_temp.bulk_pset(228, '{B13239251,B13239748}', '{}', '{PG634699}');
select pg_temp.bulk_act(229, 'Seminar Internasional AI for Smart Manufacturing bersama Kanazawa Institute of Technology', 67, 35, 'inbound', '2026-02-24', '2026-02-25', 'hybrid', 'Auditorium Gedung W PCU', 'ID', 105, '{8,9}', 'Seminar internasional dua hari membahas penerapan kecerdasan buatan pada pemeliharaan prediktif dan kendali kualitas, dihadiri 180 peserta luring dan daring dari kampus serta industri Jawa Timur.', pg_temp.wib('2026-03-06', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Kenji Yamamoto", "institution": "Kanazawa Institute of Technology", "country_code": "JP", "role": "speaker"}, {"full_name": "Dr. Ayumi Sato", "institution": "Kanazawa Institute of Technology", "country_code": "JP", "role": "speaker"}]', p_co_units => '{28,68,65}');
select pg_temp.bulk_act(230, 'Student Exchange Informatika di National Taiwan University Semester Genap 2026', 68, 2, 'outbound', '2026-02-16', '2026-06-19', 'offline', 'National Taiwan University, Main Campus Taipei', 'TW', 30, '{4,17}', 'Tiga mahasiswa Informatika menempuh satu semester di National Taiwan University dengan mata kuliah Deep Learning, Distributed Systems, dan Mandarin dasar; kredit diakui melalui skema transfer kredit.', pg_temp.wib('2026-07-02', '09:00'), 'approved', pg_temp.wib('2026-07-10', '14:00'));
select pg_temp.bulk_pset(230, '{B11249656,B11229911,B11239054}', '{}', '{}');
select pg_temp.bulk_act(231, 'Inbound Credit Transfer National Taiwan University di Prodi Informatika 2026', 68, 33, 'inbound', '2026-02-09', '2026-06-12', 'offline', 'Kampus PCU Siwalankerto', 'ID', 30, '{4,17}', 'Mahasiswa National Taiwan University mengambil 18 SKS mata kuliah Informatika PCU (Pengembangan Aplikasi Mobile, Interaksi Manusia dan Komputer) yang dikonversi ke kredit di universitas asal.', pg_temp.wib('2026-06-24', '09:00'), 'approved', pg_temp.wib('2026-07-03', '14:00'));
select pg_temp.bulk_pset(231, '{}', '{X06269001}', '{PG593383}');
select pg_temp.bulk_act(232, 'Riset Bersama Digital Twin Lini Produksi dengan TH Deggendorf', 67, 4, 'inbound', '2026-03-09', '2026-05-29', 'hybrid', 'Laboratorium Sistem Produksi Gedung P PCU', 'ID', 126, '{9,12}', 'Pengembangan purwarupa digital twin lini perakitan skala laboratorium untuk simulasi penjadwalan dan pengurangan limbah produksi, dengan pertemuan daring mingguan dan kunjungan peneliti TH Deggendorf.', pg_temp.wib('2026-07-08', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr.-Ing. Markus Hofmann", "institution": "Technische Hochschule Deggendorf", "country_code": "DE", "role": "researcher"}]');
select pg_temp.bulk_act(233, 'Academic Exchange Teknik Industri National University of Singapore 2026', 67, 28, 'inbound', '2026-03-02', '2026-05-22', 'offline', 'Laboratorium Optimasi dan Rekayasa Industri Gedung P PCU', 'ID', 19, '{4,9}', 'Mahasiswa National University of Singapore mengikuti perkuliahan Riset Operasi dan Ergonomi Industri serta terlibat dalam proyek optimasi tata letak gudang mitra industri Teknik Industri PCU.', pg_temp.wib('2026-06-04', '09:00'), 'approved', pg_temp.wib('2026-06-12', '14:00'));
select pg_temp.bulk_pset(233, '{}', '{X06259002}', '{}');
select pg_temp.bulk_act(234, 'Pelatihan dan Sertifikasi IoT Developer bersama Temasek Polytechnic', 67, 44, 'inbound', '2026-04-20', '2026-04-24', 'offline', 'Laboratorium Internet of Things Gedung P PCU', 'ID', 188, '{4,8}', 'Pelatihan lima hari pemrograman mikrokontroler, protokol MQTT, dan dashboard IoT yang ditutup dengan ujian sertifikasi IoT Developer berstandar Temasek Polytechnic untuk 30 mahasiswa Teknik Industri dan Informatika.', pg_temp.wib('2026-05-06', '09:00'), null, null, p_ext => '[{"full_name": "Mr. Tan Jun Hao", "institution": "Temasek Polytechnic", "country_code": "SG", "role": "visiting_lecturer"}]', p_co_units => '{68}');
select pg_temp.bulk_act(235, 'Kunjungan Akademik Teknik Industri ke Kyoto Sangyo University', 67, 27, 'outbound', '2026-04-13', '2026-04-16', 'offline', 'Kyoto Sangyo University, Kamigamo Campus', 'JP', 11, '{9,17}', 'Delegasi pimpinan Teknik Industri dan FTI meninjau laboratorium sistem informasi dan rekayasa produksi Kyoto Sangyo University untuk menindaklanjuti kerja sama serta merancang skema riset bersama periode 2026-2031.', pg_temp.wib('2026-04-27', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Takeshi Nakamura", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "other"}]', p_co_units => '{28}');
select pg_temp.bulk_act(236, 'Pengabdian Masyarakat Smart Village Berbasis IoT bersama ITB', 68, 40, 'outbound', '2026-07-06', '2026-07-10', 'offline', 'Desa Ketapanrame, Trawas, Mojokerto', 'ID', 83, '{1,9,11}', 'Pemasangan sistem pemantauan debit air dan panel informasi desa berbasis IoT bersama tim ITB, disertai pelatihan perawatan perangkat bagi karang taruna desa.', pg_temp.wib('2026-07-20', '09:00'), null, null, p_co_units => '{28}');
select pg_temp.bulk_act(237, 'June Program Robotika dan Otomasi Industri di Temasek Polytechnic', 67, 23, 'outbound', '2026-06-22', '2026-07-10', 'offline', 'Temasek Polytechnic, Tampines Campus', 'SG', 188, '{4,9}', 'Program tiga minggu tentang pemrograman robot kolaboratif, machine vision, dan integrasi PLC di pusat otomasi Temasek Polytechnic, ditutup presentasi proyek otomasi lini perakitan.', pg_temp.wib('2026-07-22', '09:00'), 'approved', pg_temp.wib('2026-07-30', '14:00'));
select pg_temp.bulk_pset(237, '{B13249805,B13249021,B13249069,B13249311}', '{}', '{PG681184}');
select pg_temp.bulk_act(238, 'Inbound Short Program Lean Manufacturing Temasek Polytechnic 2026', 67, 23, 'inbound', '2026-08-03', '2026-08-28', 'offline', 'Laboratorium Teknik Industri Gedung P PCU', 'ID', 188, '{4,9,17}', 'Mahasiswa Temasek Polytechnic mengikuti program empat minggu tentang lean manufacturing dan rantai pasok UMKM Jawa Timur, termasuk studi lapangan di dua pabrik mitra.', pg_temp.wib('2026-09-07', '09:00'), 'approved', pg_temp.wib('2026-09-15', '14:00'));
select pg_temp.bulk_pset(238, '{}', '{X05269005}', '{}');
select pg_temp.bulk_act(239, 'Guest Lecture Industry 4.0 Readiness dari Chulalongkorn University', 67, 7, 'inbound', '2026-08-19', '2026-08-19', 'online', 'Zoom Meeting', null, 25, '{8,9}', 'Kuliah tamu daring mengenai pengukuran kesiapan Industri 4.0 pada industri manufaktur Thailand dan pelajaran yang relevan bagi industri Indonesia, diikuti 150 mahasiswa Teknik Industri.', pg_temp.wib('2026-08-26', '09:00'), null, null, p_ext => '[{"full_name": "Assoc. Prof. Dr. Somchai Rattanakul", "institution": "Chulalongkorn University", "country_code": "TH", "role": "speaker"}]');
select pg_temp.bulk_act(240, 'Studi Ekskursi Smart Manufacturing ke Kanazawa Institute of Technology', 67, 24, 'outbound', '2026-09-14', '2026-09-19', 'offline', 'Kanazawa Institute of Technology, Ogigaoka Campus', 'JP', 105, '{4,9}', 'Studi ekskursi enam hari ke laboratorium mekatronika Kanazawa Institute of Technology dan dua pabrik manufaktur di Hokuriku untuk mengamati penerapan sistem produksi cerdas dan otomasi.', pg_temp.daysago(6, '09:00'), 'pending', pg_temp.daysago(6, '09:00'));
select pg_temp.bulk_pset(240, '{B13259437,B13259187,B13249780,B13239273,B13239019}', '{}', '{PG660389}');
select pg_temp.bulk_act(241, 'Magang AI Engineering di NTUST Artificial Intelligence Center', 68, 21, 'outbound', '2026-07-20', '2026-09-11', 'offline', 'NTUST Taipei Campus, Taiwan Building Technology Center', 'TW', 200, '{8,9}', 'Dua mahasiswa Informatika magang delapan minggu di pusat AI NTUST, mengembangkan pipeline pelabelan data dan model deteksi objek untuk inspeksi konstruksi.', pg_temp.daysago(12, '09:00'), 'pending', pg_temp.daysago(12, '09:00'));
select pg_temp.bulk_pset(241, '{B11239992,B11229772}', '{}', '{}');
select pg_temp.bulk_act(242, 'Short Program Cyber-Physical Systems di Universiti Teknologi Malaysia', 68, 23, 'outbound', '2026-08-10', '2026-08-28', 'offline', 'UTM Johor Bahru Campus', 'MY', 107, '{4,9}', 'Program tiga minggu tentang sistem siber-fisik, edge computing, dan keamanan jaringan industri di UTM, dengan proyek kelompok pemantauan mesin berbasis sensor getaran.', pg_temp.daysago(15, '09:00'), 'revision_requested', pg_temp.daysago(9, '14:00'), p_mnote => 'Mohon unggah transkrip nilai UTM untuk B11249376 yang belum ada di berkas mobility, dan sesuaikan tanggal selesai dengan sertifikat (27 Agustus 2026).');
select pg_temp.bulk_pset(242, '{B11239558,B11249376,B11249731,B11249484}', '{}', '{PG557816}');
select pg_temp.bulk_act(243, 'Publikasi Bersama Material Komposit Daur Ulang untuk Manufaktur Aditif dengan University of Melbourne', 69, 37, 'outbound', '2026-08-03', '2026-09-18', 'online', 'Microsoft Teams', null, 181, '{9,12}', 'Penulisan dan pengiriman artikel bersama ke jurnal internasional bereputasi tentang karakterisasi filamen komposit daur ulang untuk manufaktur aditif, melalui rapat daring dua mingguan.', pg_temp.wib('2026-09-24', '09:00'), null, null, p_ext => '[{"full_name": "Assoc. Prof. Dr. Sarah Mitchell", "institution": "University of Melbourne", "country_code": "AU", "role": "researcher"}]', p_co_units => '{28}');
select pg_temp.bulk_act(244, 'Kuliah Tamu Large Language Models untuk Rekayasa Perangkat Lunak dari Xiamen University', 68, 15, 'inbound', '2026-11-09', '2026-11-10', 'offline', 'Auditorium Gedung P PCU', 'ID', 184, '{4,9}', 'Rencana kuliah tamu tentang pemanfaatan large language model untuk pembangkitan kode dan pengujian otomatis, disertai lokakarya praktik bagi mahasiswa Informatika.', null, null, null, p_files => '{ia}', p_ext => '[{"full_name": "Prof. Dr. Lin Hao", "institution": "Xiamen University", "country_code": "CN", "role": "visiting_lecturer"}]');
select pg_temp.bulk_act(245, 'Penyusunan Joint Curriculum Industrial Engineering bersama Chulalongkorn University', 67, 32, 'inbound', '2026-12-07', '2026-12-09', 'hybrid', 'Ruang Rapat Dekanat FTI Gedung P PCU', 'ID', 34, '{4,17}', 'Rencana lokakarya penyusunan kurikulum bersama program Industrial Engineering untuk skema double degree, mencakup pemetaan mata kuliah dan mekanisme penjaminan mutu.', null, null, null, p_ext => '[{"full_name": "Asst. Prof. Dr. Napat Wongsuwan", "institution": "Chulalongkorn University", "country_code": "TH", "role": "staff_visitor"}]');

select pg_temp.bulk_verify(221, 245);
