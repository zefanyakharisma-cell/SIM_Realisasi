-- seed-supabase/10_kegiatan_tambahan_2 (simks-partnership): additional bulk kegiatan 246-270, adapted from the local
-- demo seed supabase/seed/04_bulk_2.sql to the real SIM Kerjasama units (Program Studi submitters) and agreements.
-- Generated from a reviewed JSON list; every row passes the guards below (agreement valid for the dates, submission
-- after the end date, Mobility decision after the submission, participant set for every submitted mobility kegiatan,
-- no student in two overlapping kegiatan, unique names). Needs 03_accounts.sql and 09_registries_tambahan.sql.
-- Self-contained and idempotent (existing rows are skipped), so it can be run on its own: Supabase SQL Editor or one
-- statement batch. Writes only realisasi.*; SIM Kerjasama tables are only read.

-- The kegiatan reference SIM Kerjasama agreements 25, 30, 31, 72, 77, 95, 105, 107, 126, 134, 143, 151, 181, 193, 195, 200. Where any is missing (e.g. the local
-- --rehearse fixture, which only mirrors agreements 11-52) the whole file is skipped with a notice instead of failing.
drop table if exists pg_temp.tambahan_skip;
create temp table tambahan_skip as
select exists (select 1 from unnest('{25,30,31,72,77,95,105,107,126,134,143,151,181,193,195,200}'::int[]) d where not exists (select 1 from kerjasama.documents k where k.id = d)) as skip;
do $$ begin if (select skip from pg_temp.tambahan_skip) then
  raise notice '10_kegiatan_tambahan_2: SIM Kerjasama agreements missing, kegiatan 246-270 skipped'; end if; end $$;


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

select pg_temp.bulk_act(246, 'Inbound Exchange Teknik Elektro dari Technische Hochschule Deggendorf 2025', 65, 2, 'inbound', '2025-09-01', '2025-12-19', 'offline', 'Kampus PCU Siwalankerto', 'ID', 126, '{4,17}', 'Mahasiswa Technische Hochschule Deggendorf mengikuti satu semester perkuliahan di Prodi Teknik Elektro PCU, termasuk mata kuliah Sistem Tenaga Listrik dan Energi Terbarukan serta proyek laboratorium konversi energi. Kredit ditransfer ke program Elektrotechnik di Deggendorf.', pg_temp.wib('2025-12-23', '09:00'), 'approved', pg_temp.wib('2026-01-06', '14:00'), p_co_units => '{28}');
select pg_temp.bulk_pset(246, '{}', '{X06269006}', '{}');
select pg_temp.bulk_act(247, 'Kuliah Tamu Proteksi Sistem Tenaga dari Universitas Brawijaya', 65, 15, 'inbound', '2025-09-17', '2025-09-17', 'hybrid', 'Gedung P PCU', 'ID', 193, '{4,7}', 'Kuliah tamu dosen Teknik Elektro Universitas Brawijaya mengenai koordinasi relai proteksi dan deteksi gangguan pada jaringan distribusi dengan penetrasi pembangkit tersebar tinggi. Diikuti mahasiswa mata kuliah Proteksi Sistem Tenaga secara luring dan daring.', pg_temp.wib('2025-09-24', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Ir. Hadi Suyono, S.T., M.T.", "institution": "Universitas Brawijaya", "country_code": "ID", "role": "visiting_lecturer"}]', p_co_units => '{28}');
select pg_temp.bulk_act(248, 'Riset Bersama Optimasi PLTS Atap Kampus dengan Universiti Teknologi Malaysia', 65, 4, 'outbound', '2025-10-13', '2025-10-17', 'offline', 'Universiti Teknologi Malaysia, Johor Bahru', 'MY', 77, '{7,13}', 'Dosen Teknik Elektro melakukan pengukuran dan pemodelan kinerja PLTS atap di kampus UTM sebagai pembanding instalasi PCU. Tim menyusun metodologi optimasi sudut kemiringan dan jadwal pembersihan panel untuk iklim tropis lembap.', pg_temp.wib('2025-10-28', '09:00'), null, null, p_ext => '[{"full_name": "Assoc. Prof. Dr. Mohd Hafiz Abdullah", "institution": "Universiti Teknologi Malaysia", "country_code": "MY", "role": "researcher"}]', p_co_units => '{28}');
select pg_temp.bulk_act(249, 'Short Program Robotika Otonom di Kanazawa Institute of Technology', 65, 23, 'outbound', '2025-11-03', '2025-11-14', 'offline', 'Kanazawa Institute of Technology, Ogigaoka Campus', 'JP', 105, '{4,9}', 'Program singkat dua minggu tentang navigasi robot bergerak otonom, sensor LiDAR, dan ROS 2 di Kanazawa Institute of Technology. Mahasiswa Teknik Elektro menyelesaikan proyek kelompok robot pengantar barang dan mempresentasikannya di laboratorium mitra.', pg_temp.wib('2025-11-21', '09:00'), 'approved', pg_temp.wib('2025-12-01', '14:00'), p_co_units => '{28}');
select pg_temp.bulk_pset(249, '{B12239256,B12229628,B12239294}', '{}', '{PG204517}');
select pg_temp.bulk_act(250, 'Seminar Teknologi Baterai Kendaraan Listrik bersama Universitas Indonesia', 65, 10, 'outbound', '2025-11-26', '2025-11-26', 'offline', 'Fakultas Teknik Universitas Indonesia, Depok', 'ID', 134, '{7,9,11}', 'Seminar bersama Fakultas Teknik Universitas Indonesia tentang sistem manajemen baterai (BMS), keamanan sel lithium-ion, dan infrastruktur pengisian kendaraan listrik di Indonesia. Dosen Teknik Elektro PCU menjadi pembicara sesi estimasi state-of-charge.', pg_temp.wib('2025-12-03', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Ir. Feri Yusivar, M.Eng.", "institution": "Universitas Indonesia", "country_code": "ID", "role": "speaker"}]', p_co_units => '{28}');
select pg_temp.bulk_act(251, 'Kunjungan Akademik Laboratorium Sistem Tenaga Universitas Indonesia', 65, 27, 'outbound', '2025-12-08', '2025-12-10', 'offline', 'Departemen Teknik Elektro Universitas Indonesia, Depok', 'ID', 134, '{7,17}', 'Delegasi Teknik Elektro PCU mengunjungi laboratorium sistem tenaga dan elektronika daya Universitas Indonesia untuk menjajaki topik riset lanjutan serta pemanfaatan bersama fasilitas uji. Hasilnya berupa daftar topik riset bersama 2026.', pg_temp.wib('2025-12-18', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Ir. Rudy Setiabudy", "institution": "Universitas Indonesia", "country_code": "ID", "role": "staff_visitor"}]', p_co_units => '{28}');
select pg_temp.bulk_act(252, 'Riset Bersama Prakiraan Beban Listrik Berbasis Machine Learning dengan Universitas Gadjah Mada', 65, 4, 'outbound', '2025-08-18', '2025-10-31', 'online', 'Microsoft Teams', null, 72, '{7,9}', 'Riset daring bersama Departemen Teknik Elektro dan Teknologi Informasi UGM untuk membangun model prakiraan beban listrik jangka pendek pada jaringan distribusi kampus. Data smart meter PCU dibandingkan dengan data gardu kampus Bulaksumur; luaran berupa draf artikel jurnal dan model LSTM terbuka.', pg_temp.wib('2025-11-07', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Ir. Bambang Sugiyantoro, M.T.", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "researcher"}]', p_co_units => '{28}');
select pg_temp.bulk_act(253, 'Credit Transfer Inbound Sistem Tertanam dari Kanazawa Institute of Technology 2025', 65, 33, 'inbound', '2025-10-01', '2026-01-23', 'offline', 'Laboratorium Sistem Tertanam PCU', 'ID', 105, '{4}', 'Mahasiswa Kanazawa Institute of Technology mengambil mata kuliah Sistem Tertanam, Mikrokontroler, dan Internet of Things di Teknik Elektro PCU dengan pengakuan kredit di institusi asal. Proyek akhir berupa node sensor kualitas udara berdaya rendah.', pg_temp.wib('2026-02-25', '09:00'), 'approved', pg_temp.wib('2026-03-05', '14:00'), p_co_units => '{28}');
select pg_temp.bulk_pset(253, '{}', '{X06269009}', '{}');
select pg_temp.bulk_act(254, 'Student Exchange Semester Genap Teknik Elektro di Hochschule Bremen', 65, 2, 'outbound', '2026-03-02', '2026-07-17', 'offline', 'Hochschule Bremen, Campus Neustadtswall', 'DE', 195, '{4,7,17}', 'Tiga mahasiswa Teknik Elektro mengikuti satu semester di program Elektrotechnik Hochschule Bremen dengan fokus energi terbarukan dan elektronika daya. Mata kuliah yang diambil dikonversi ke kurikulum PCU.', pg_temp.wib('2026-07-24', '09:00'), 'approved', pg_temp.wib('2026-08-05', '14:00'), p_co_units => '{28}');
select pg_temp.bulk_pset(254, '{B12239153,B12249412,B12239792}', '{}', '{}');
select pg_temp.bulk_act(255, 'Inbound Exchange Teknik Mesin dari University of Melbourne Semester Genap 2026', 69, 2, 'inbound', '2026-03-02', '2026-06-26', 'offline', 'Kampus PCU Siwalankerto', 'ID', 181, '{4,7,17}', 'Mahasiswa University of Melbourne menjalani semester pertukaran di Teknik Mesin PCU dan bergabung dalam proyek pengering surya hibrida di Laboratorium Konversi Energi. Kegiatan juga mencakup kelas bahasa dan budaya Indonesia.', pg_temp.wib('2026-07-02', '09:00'), 'approved', pg_temp.wib('2026-07-10', '14:00'), p_co_units => '{28}');
select pg_temp.bulk_pset(255, '{}', '{X05269007}', '{}');
select pg_temp.bulk_act(256, 'Kuliah Tamu Keamanan Siber Smart Grid dari Universitas Gadjah Mada', 65, 15, 'inbound', '2026-03-11', '2026-03-11', 'offline', 'Gedung P PCU', 'ID', 72, '{4,9}', 'Kuliah tamu dosen UGM tentang ancaman siber pada sistem SCADA dan advanced metering infrastructure, termasuk standar IEC 62351. Mahasiswa Teknik Elektro melakukan studi kasus serangan pada gardu induk digital.', pg_temp.wib('2026-03-17', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Eng. Sigit Basuki Wibowo", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "visiting_lecturer"}]', p_co_units => '{28}');
select pg_temp.bulk_act(257, 'Riset Bersama Inverter Grid-Forming Mikrogrid dengan NTUST', 65, 4, 'outbound', '2026-04-20', '2026-04-24', 'offline', 'National Taiwan University of Science and Technology, Taipei', 'TW', 200, '{7,9}', 'Riset bersama National Taiwan University of Science and Technology untuk pengembangan kontrol inverter grid-forming berbasis mikrokontroler DSP pada mikrogrid kampus. Pengujian hardware-in-the-loop dilakukan di laboratorium elektronika daya mitra.', pg_temp.wib('2026-05-04', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Chen Wei-Lun", "institution": "National Taiwan University of Science and Technology", "country_code": "TW", "role": "researcher"}]', p_co_units => '{28}');
select pg_temp.bulk_act(258, 'Pelatihan Daring PLC dan SCADA bersama Universitas Brawijaya', 65, 69, 'outbound', '2026-08-17', '2026-08-19', 'online', 'Zoom Meeting', null, 193, '{4,9}', 'Pelatihan daring tiga hari oleh instruktur Universitas Brawijaya tentang pemrograman PLC IEC 61131-3 dan perancangan HMI SCADA untuk dosen dan laboran Teknik Elektro. Peserta menyelesaikan studi kasus kontrol stasiun pompa.', pg_temp.wib('2026-08-25', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Rini Nur Hasanah, S.T., M.Sc.", "institution": "Universitas Brawijaya", "country_code": "ID", "role": "speaker"}]', p_co_units => '{28}');
select pg_temp.bulk_act(259, 'Magang Riset Robot Kolaboratif Berbasis Visi Komputer di Yonsei University', 65, 21, 'outbound', '2026-06-01', '2026-07-24', 'offline', 'Yonsei University, Sinchon Campus, Seoul', 'KR', 143, '{4,8,9}', 'Magang riset delapan minggu di laboratorium robotika Yonsei University untuk pengembangan lengan robot kolaboratif dengan kendali berbasis visi komputer. Mahasiswa Teknik Elektro menyusun laporan teknis dan demo akhir.', pg_temp.wib('2026-07-29', '09:00'), 'approved', pg_temp.wib('2026-08-07', '14:00'), p_co_units => '{28}');
select pg_temp.bulk_pset(259, '{B12249256,B12249376,B12239075}', '{}', '{}');
select pg_temp.bulk_act(260, 'Inbound Short Program Energi Terbarukan Universiti Teknologi Malaysia 2026', 65, 23, 'inbound', '2026-07-06', '2026-07-17', 'offline', 'Laboratorium Konversi Energi PCU', 'ID', 107, '{4,7}', 'Program singkat dua minggu bagi mahasiswa Universiti Teknologi Malaysia tentang sistem PLTS, turbin angin skala kecil, dan audit energi bangunan. Peserta melakukan kunjungan lapangan ke instalasi PLTS atap di Surabaya.', pg_temp.wib('2026-07-22', '09:00'), 'approved', pg_temp.wib('2026-07-31', '14:00'), p_co_units => '{28}');
select pg_temp.bulk_pset(260, '{}', '{X06269010}', '{}');
select pg_temp.bulk_act(261, 'Pengabdian Masyarakat PLTS Off-Grid Desa bersama Universitas Brawijaya', 65, 40, 'outbound', '2026-02-23', '2026-02-27', 'offline', 'Desa Sidomulyo, Kabupaten Pacitan', 'ID', 193, '{1,7}', 'Dosen dan mahasiswa Teknik Elektro PCU bersama tim Universitas Brawijaya memasang PLTS off-grid 3 kWp untuk balai desa dan pompa air, serta melatih warga melakukan perawatan dasar panel dan baterai. Luaran berupa sistem terpasang dan modul perawatan.', pg_temp.wib('2026-03-06', '09:00'), null, null, p_ext => '[{"full_name": "Ir. Teguh Utomo, M.T.", "institution": "Universitas Brawijaya", "country_code": "ID", "role": "other"}]', p_co_units => '{28}');
select pg_temp.bulk_act(262, 'Joint Curriculum Telekomunikasi 5G dengan Kanazawa Institute of Technology', 65, 32, 'inbound', '2026-04-13', '2026-04-15', 'hybrid', 'Gedung P PCU', 'ID', 95, '{4,9}', 'Lokakarya penyusunan mata kuliah bersama Jaringan 5G dan Antena Gelombang Milimeter dengan Kanazawa Institute of Technology. Kedua pihak menyepakati capaian pembelajaran, modul praktikum, dan skema kuliah bersama mulai Ganjil 2026/2027.', pg_temp.wib('2026-04-21', '09:00'), null, null, p_ext => '[{"full_name": "Assoc. Prof. Dr. Takeshi Nakamura", "institution": "Kanazawa Institute of Technology", "country_code": "JP", "role": "visiting_lecturer"}]', p_co_units => '{28}');
select pg_temp.bulk_act(263, 'Inbound Exchange Kendaraan Listrik Yonsei University Semester Genap 2026', 69, 2, 'inbound', '2026-02-09', '2026-07-24', 'offline', 'Kampus PCU Siwalankerto', 'ID', 31, '{4,17}', 'Mahasiswa Yonsei University mengikuti satu semester di Teknik Mesin PCU dengan mata kuliah Kendaraan Listrik dan Sistem Penggerak serta proyek konversi sepeda motor listrik. Pengakuan kredit dilakukan oleh Yonsei University.', pg_temp.wib('2026-08-04', '09:00'), 'approved', pg_temp.wib('2026-08-12', '14:00'), p_co_units => '{28}');
select pg_temp.bulk_pset(263, '{}', '{X05269008}', '{}');
select pg_temp.bulk_act(264, 'Kunjungan Akademik Fakultas Teknik Chulalongkorn University', 65, 27, 'outbound', '2026-08-24', '2026-08-26', 'offline', 'Chulalongkorn University Faculty of Engineering, Bangkok', 'TH', 151, '{4,17}', 'Kunjungan pimpinan Teknik Elektro ke Chulalongkorn University untuk menindaklanjuti MoU: peninjauan laboratorium smart grid dan telekomunikasi serta penyusunan rencana pertukaran mahasiswa dan dosen 2027.', pg_temp.wib('2026-09-02', '09:00'), null, null, p_ext => '[{"full_name": "Assoc. Prof. Dr. Somchai Wongsiri", "institution": "Chulalongkorn University", "country_code": "TH", "role": "staff_visitor"}]', p_co_units => '{28}');
select pg_temp.bulk_act(265, 'Summer Program Robotics and Automation di Chulalongkorn University', 65, 23, 'outbound', '2026-08-03', '2026-08-14', 'offline', 'Chulalongkorn University Faculty of Engineering, Bangkok', 'TH', 25, '{4,9}', 'Program musim panas dua minggu tentang otomasi industri, PLC, dan robot industri. Mahasiswa Teknik Elektro mengerjakan proyek sel manufaktur otomatis bersama mahasiswa Chulalongkorn University.', pg_temp.daysago(6, '09:00'), 'pending', pg_temp.daysago(6, '09:00'), p_co_units => '{28}');
select pg_temp.bulk_pset(265, '{B12239256,B12229628,B12239294,B12239153,B12249412}', '{}', '{PG707752}');
select pg_temp.bulk_act(266, 'Studi Ekskursi Teknologi Telekomunikasi 5G ke National Taiwan University', 65, 24, 'outbound', '2026-09-07', '2026-09-11', 'offline', 'National Taiwan University, Taipei', 'TW', 30, '{4,9}', 'Studi ekskursi lima hari ke laboratorium komunikasi nirkabel National Taiwan University dan operator telekomunikasi di Taipei. Mahasiswa mengamati pengujian antena 5G dan menyusun laporan perbandingan infrastruktur jaringan.', pg_temp.daysago(12, '09:00'), 'pending', pg_temp.daysago(12, '09:00'), p_co_units => '{28}');
select pg_temp.bulk_pset(266, '{B12239792,B12249256,B12249376}', '{}', '{PG413450}');
select pg_temp.bulk_act(267, 'Magang Riset Powertrain Kendaraan Listrik di University of Melbourne', 69, 21, 'outbound', '2026-07-06', '2026-08-28', 'offline', 'University of Melbourne, Parkville Campus', 'AU', 181, '{8,9,11}', 'Magang delapan minggu di laboratorium e-mobility University of Melbourne, mencakup pengujian motor traksi, manajemen termal baterai, dan pengisi daya DC cepat. Mahasiswa Teknik Mesin menyusun laporan magang dan poster hasil pengujian.', pg_temp.daysago(15, '09:00'), 'revision_requested', pg_temp.daysago(8, '14:00'), p_mnote => 'Sertifikat magang dari University of Melbourne dan transkrip konversi SKS belum diunggah untuk kedua mahasiswa. Mohon lengkapi berkas mobilitas sebelum diajukan ulang.', p_co_units => '{28}');
select pg_temp.bulk_pset(267, '{B14239757,B14229309}', '{}', '{}');
select pg_temp.bulk_act(268, 'Seminar Internasional Transisi Energi Terbarukan bersama Universiti Teknologi Malaysia', 65, 10, 'inbound', '2026-09-16', '2026-09-16', 'hybrid', 'Auditorium Gedung W PCU', 'ID', 77, '{7,13,17}', 'Seminar internasional tentang integrasi energi terbarukan ke jaringan listrik Indonesia dan Malaysia, penyimpanan energi, dan kebijakan net-zero. Menghadirkan pembicara UTM dan dosen Teknik Elektro PCU dengan lebih dari 200 peserta.', pg_temp.wib('2026-09-22', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Ahmad Faizal Rahman", "institution": "Universiti Teknologi Malaysia", "country_code": "MY", "role": "speaker"}]', p_co_units => '{28}');
select pg_temp.bulk_act(269, 'Workshop Persiapan Kontes Robot Sepak Bola Beroda bersama Universitas Gadjah Mada', 65, 35, 'inbound', '2026-11-09', '2026-11-11', 'offline', 'Laboratorium Robotika PCU', 'ID', 72, '{4,9}', 'Rencana lokakarya bersama persiapan kontes robot sepak bola beroda, meliputi desain mekanik, kendali motor, dan strategi multi-agen. Tim robotika UGM akan berbagi pengalaman mengikuti Kontes Robot Indonesia.', null, null, null, p_files => '{ia}', p_co_units => '{28}');
select pg_temp.bulk_act(270, 'Credit Transfer Teknik Elektro ke Hochschule Bremen Ganjil 2026/2027', 65, 33, 'outbound', '2026-10-05', '2027-01-29', 'offline', 'Hochschule Bremen, Campus Neustadtswall', 'DE', 195, '{4,7}', 'Rencana program transfer kredit satu semester di Hochschule Bremen untuk mata kuliah Sistem Tenaga Lanjut dan Penyimpanan Energi. Draf menunggu konfirmasi letter of acceptance dari mitra.', null, null, null, p_files => '{}', p_co_units => '{28}');
select pg_temp.bulk_pset(270, '{B12249585,B12239075}', '{}', '{}');

select pg_temp.bulk_verify(246, 270);
