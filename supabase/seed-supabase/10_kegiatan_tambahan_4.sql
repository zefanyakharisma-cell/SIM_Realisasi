-- seed-supabase/10_kegiatan_tambahan_4 (simks-partnership): additional bulk kegiatan 296-320, adapted from the local
-- demo seed supabase/seed/04_bulk_4.sql to the real SIM Kerjasama units (Program Studi submitters) and agreements.
-- Generated from a reviewed JSON list; every row passes the guards below (agreement valid for the dates, submission
-- after the end date, Mobility decision after the submission, participant set for every submitted mobility kegiatan,
-- no student in two overlapping kegiatan, unique names). Needs 03_accounts.sql and 09_registries_tambahan.sql.
-- Self-contained and idempotent (existing rows are skipped), so it can be run on its own: Supabase SQL Editor or one
-- statement batch. Writes only realisasi.*; SIM Kerjasama tables are only read.

-- The kegiatan reference SIM Kerjasama agreements 12, 15, 25, 28, 30, 31, 62, 65, 123, 152, 166, 168, 174, 180. Where any is missing (e.g. the local
-- --rehearse fixture, which only mirrors agreements 11-52) the whole file is skipped with a notice instead of failing.
drop table if exists pg_temp.tambahan_skip;
create temp table tambahan_skip as
select exists (select 1 from unnest('{12,15,25,28,30,31,62,65,123,152,166,168,174,180}'::int[]) d where not exists (select 1 from kerjasama.documents k where k.id = d)) as skip;
do $$ begin if (select skip from pg_temp.tambahan_skip) then
  raise notice '10_kegiatan_tambahan_4: SIM Kerjasama agreements missing, kegiatan 296-320 skipped'; end if; end $$;


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

select pg_temp.bulk_act(296, 'Kuliah Tamu Digital Marketing Strategy in the K-Wave Era dari Yonsei School of Business', 5, 15, 'inbound', '2025-10-22', '2025-10-22', 'offline', 'Auditorium Gedung W PCU', 'ID', 31, '{4,8}', 'Kuliah tamu bagi mahasiswa mata kuliah Pemasaran Digital tentang strategi pemasaran merek Korea memanfaatkan Hallyu dan influencer marketing. Diikuti sekitar 180 mahasiswa Manajemen dan ditutup dengan studi kasus kampanye K-beauty di Asia Tenggara.', pg_temp.wib('2025-10-29', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Kim Jae-won, Ph.D.", "institution": "Yonsei University", "country_code": "KR", "role": "speaker"}]', p_co_units => '{4}');
select pg_temp.bulk_act(297, 'Student Exchange HKBU School of Business Semester Fall 2025', 5, 2, 'outbound', '2025-08-25', '2025-12-19', 'offline', 'Hong Kong Baptist University, Kowloon Tong', 'HK', 62, '{4,17}', 'Tiga mahasiswa Manajemen mengikuti satu semester perkuliahan di School of Business Hong Kong Baptist University dengan fokus mata kuliah International Marketing dan Consumer Behavior. Nilai dikonversi ke kurikulum Prodi Manajemen sebagai mata kuliah pilihan internasional.', pg_temp.wib('2026-01-07', '09:00'), 'approved', pg_temp.wib('2026-01-15', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(297, '{D31239083,D31239791,D31239881}', '{}', '{}');
select pg_temp.bulk_act(298, 'Inbound Exchange University of Amsterdam di Prodi Manajemen PCU Semester Ganjil 2025', 5, 2, 'inbound', '2025-08-18', '2025-12-12', 'offline', 'Gedung P PCU', 'ID', 166, '{4,17}', 'Mahasiswa Amsterdam Business School, University of Amsterdam, mengikuti perkuliahan semester ganjil di Prodi Manajemen PCU, termasuk mata kuliah Indonesian Business Environment dan Entrepreneurship. Kegiatan dilengkapi program buddy dan kunjungan industri ke kawasan SIER Surabaya.', pg_temp.wib('2025-12-18', '09:00'), 'approved', pg_temp.wib('2025-12-29', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(298, '{}', '{X05259020}', '{}');
select pg_temp.bulk_act(299, 'Riset Bersama Ketahanan Rantai Pasok UMKM Pangan Olahan dengan FEB UGM', 5, 4, 'outbound', '2025-10-20', '2025-12-31', 'hybrid', 'Fakultas Ekonomika dan Bisnis UGM', 'ID', 28, '{2,9,12}', 'Penelitian bersama mengenai ketahanan rantai pasok UMKM pangan olahan di Jawa Timur dan DIY melalui survei 120 pelaku usaha. Luaran berupa model pemetaan risiko pemasok dan draf artikel untuk jurnal terakreditasi SINTA 2.', pg_temp.wib('2026-02-10', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Rangga Almahendra", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "researcher"}]', p_co_units => '{4}');
select pg_temp.bulk_act(300, 'Pengabdian Masyarakat Digitalisasi Pemasaran Kampung Batik Jetis bersama Unair', 5, 40, 'outbound', '2025-10-11', '2025-11-22', 'offline', 'Kampung Batik Jetis Sidoarjo', 'ID', 180, '{1,8,17}', 'Pendampingan 25 perajin batik Jetis dalam pembuatan katalog digital, pengelolaan akun marketplace, dan pencatatan penjualan sederhana. Dilaksanakan bersama dosen FEB Universitas Airlangga dalam enam kali pertemuan lapangan.', pg_temp.wib('2025-11-28', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Gancar Candra Premananto", "institution": "Universitas Airlangga", "country_code": "ID", "role": "other"}]', p_co_units => '{4}');
select pg_temp.bulk_act(301, 'Pelatihan Digital Business Analytics bersama Telkom Indonesia', 5, 69, 'inbound', '2025-10-15', '2025-10-16', 'offline', 'Lab Komputer Manajemen Gedung P PCU', 'ID', 152, '{4,9}', 'Pelatihan dua hari bagi mahasiswa dan dosen Manajemen tentang analitik data pelanggan, dashboard penjualan, dan pemanfaatan big data telekomunikasi untuk segmentasi pasar. Instruktur berasal dari unit Digital Business Telkom Indonesia.', pg_temp.wib('2025-10-20', '09:00'), null, null, p_ext => '[{"full_name": "Andika Pratama, M.M.", "institution": "PT Telkom Indonesia (Persero) Tbk", "country_code": "ID", "role": "staff_visitor"}, {"full_name": "Rizky Amalia, S.T., M.B.A.", "institution": "PT Telkom Indonesia (Persero) Tbk", "country_code": "ID", "role": "speaker"}]', p_co_units => '{4}');
select pg_temp.bulk_act(302, 'Magang Marketing & Customer Experience di Astra International Surabaya 2025', 5, 21, 'outbound', '2025-09-01', '2025-12-31', 'offline', 'PT Astra International Tbk, Kantor Wilayah Surabaya', 'ID', 123, '{8,9}', 'Tiga mahasiswa Manajemen tingkat akhir menjalani magang empat bulan di divisi Marketing dan Customer Experience Astra International wilayah Surabaya. Mahasiswa terlibat dalam analisis kepuasan pelanggan purnajual dan penyusunan materi kampanye produk korporat.', pg_temp.wib('2026-01-09', '09:00'), 'approved', pg_temp.wib('2026-01-20', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(302, '{D31229852,D31229748,D31229309}', '{}', '{}');
select pg_temp.bulk_act(303, 'Kuliah Bersama Human Resource Analytics dengan Yonsei University', 5, 34, 'inbound', '2025-11-05', '2025-12-10', 'online', 'Zoom Meeting', null, 31, '{4,8}', 'Enam sesi kuliah bersama daring untuk mata kuliah Manajemen SDM Strategik yang membahas people analytics, prediksi turnover, dan desain sistem kinerja. Mahasiswa PCU dan Yonsei mengerjakan tugas kelompok lintas negara.', pg_temp.wib('2025-12-15', '09:00'), null, null, p_ext => '[{"full_name": "Assoc. Prof. Lee Min-ji, Ph.D.", "institution": "Yonsei University", "country_code": "KR", "role": "visiting_lecturer"}]', p_co_units => '{4}');
select pg_temp.bulk_act(304, 'Student Exchange Yonsei School of Business Spring Semester 2026', 5, 2, 'outbound', '2026-02-23', '2026-06-19', 'offline', 'Yonsei University Sinchon Campus, Seoul', 'KR', 31, '{4,17}', 'Empat mahasiswa Manajemen mengikuti semester musim semi di Yonsei School of Business dengan mata kuliah Digital Business Strategy, Supply Chain Management, dan Korean Language I. Hasil studi diakui sebagai 20 SKS.', pg_temp.wib('2026-06-29', '09:00'), 'approved', pg_temp.wib('2026-07-08', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(304, '{D31249994,D31249546,D31239043,D31249493}', '{}', '{}');
select pg_temp.bulk_act(305, 'Inbound Exchange National Taiwan University Spring 2026 di Prodi Manajemen', 5, 2, 'inbound', '2026-02-23', '2026-06-12', 'offline', 'Gedung P PCU', 'ID', 30, '{4,17}', 'Mahasiswa National Taiwan University mengikuti semester genap di Prodi Manajemen PCU dengan mata kuliah Marketing Management, Bahasa Indonesia untuk Penutur Asing, dan Family Business. Program dilengkapi pendampingan buddy mahasiswa.', pg_temp.wib('2026-06-19', '09:00'), 'approved', pg_temp.wib('2026-06-26', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(305, '{}', '{X06259017}', '{}');
select pg_temp.bulk_act(306, 'Inbound Exchange HKBU dan Manipal Spring 2026 di Prodi Manajemen', 5, 2, 'inbound', '2026-02-09', '2026-06-12', 'offline', 'Gedung P PCU', 'ID', 62, '{4,17}', 'Mahasiswa Hong Kong Baptist University dan Manipal Academy of Higher Education mengikuti perkuliahan semester genap di Prodi Manajemen, khususnya mata kuliah Operations Management dan Southeast Asian Business, dalam kerangka MoU tiga pihak.', pg_temp.wib('2026-06-22', '09:00'), 'approved', pg_temp.wib('2026-07-02', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(306, '{}', '{X05269018,X05259019}', '{}');
select pg_temp.bulk_act(307, 'Kuliah Tamu Sustainable Supply Chain Management dari FEB UGM', 5, 15, 'inbound', '2026-03-11', '2026-03-11', 'offline', 'Auditorium Gedung W PCU', 'ID', 28, '{9,12,17}', 'Kuliah tamu tentang praktik rantai pasok berkelanjutan, green procurement, dan pengukuran jejak karbon logistik bagi mahasiswa konsentrasi Operasi dan Rantai Pasok. Dihadiri sekitar 150 mahasiswa dan dosen.', pg_temp.wib('2026-03-16', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Eko Suwardi", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "speaker"}]', p_co_units => '{4}');
select pg_temp.bulk_act(308, 'Sertifikasi Digital Marketing Associate bersama Telkom Indonesia', 5, 44, 'inbound', '2026-04-18', '2026-04-19', 'offline', 'Lab Komputer Manajemen Gedung P PCU', 'ID', 152, '{4,8}', 'Program sertifikasi kompetensi pemasaran digital bagi 40 mahasiswa Manajemen yang mencakup SEO, iklan media sosial, dan analitik kampanye. Ujian sertifikasi diselenggarakan oleh asesor Telkom Corporate University.', pg_temp.wib('2026-04-24', '09:00'), null, null, p_ext => '[{"full_name": "Dimas Aditya, S.Kom., M.M.", "institution": "PT Telkom Indonesia (Persero) Tbk", "country_code": "ID", "role": "staff_visitor"}]', p_co_units => '{4}');
select pg_temp.bulk_act(309, 'Studi Ekskursi Manajemen Operasi ke Astra International Jakarta', 5, 24, 'outbound', '2026-05-12', '2026-05-15', 'offline', 'Kantor Pusat PT Astra International Tbk, Sunter Jakarta', 'ID', 12, '{4,9}', 'Kunjungan studi empat hari ke kantor pusat dan fasilitas produksi grup Astra di Jakarta untuk mempelajari manajemen operasi, lean production, dan layanan pelanggan. Mahasiswa menyusun laporan observasi proses bisnis.', pg_temp.wib('2026-05-22', '09:00'), 'approved', pg_temp.wib('2026-05-29', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(309, '{D31259442,D31239676,D31249971,D31249923,D31249797,D31239469}', '{}', '{}');
select pg_temp.bulk_act(310, 'Publikasi Bersama Perilaku Konsumen Produk Halal dengan FEB UGM', 5, 37, 'outbound', '2026-02-02', '2026-05-29', 'online', 'Microsoft Teams', null, 28, '{4,12}', 'Penulisan artikel bersama tentang niat beli konsumen milenial terhadap produk makanan halal kemasan di Surabaya dan Yogyakarta. Naskah disusun bersama dosen FEB UGM dan dikirim ke Journal of Islamic Marketing.', pg_temp.wib('2026-06-08', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Sahabudin Sidiq, M.A.", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "researcher"}]', p_co_units => '{4}');
select pg_temp.bulk_act(311, 'Pengembangan Kurikulum Kewirausahaan Digital MBKM bersama Binus University', 5, 11, 'inbound', '2026-03-02', '2026-04-30', 'hybrid', 'Ruang Rapat Prodi Manajemen Gedung P PCU', 'ID', 65, '{4,8}', 'Rangkaian lokakarya penyusunan paket mata kuliah Kewirausahaan Digital 20 SKS untuk skema MBKM yang dapat diambil lintas kampus bersama Binus Entrepreneurship Center. Luaran berupa RPS, rubrik penilaian proyek, dan skema rekognisi SKS bersama.', pg_temp.wib('2026-05-06', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Rini Setiowati, S.E., M.M.", "institution": "Universitas Bina Nusantara", "country_code": "ID", "role": "visiting_lecturer"}]', p_co_units => '{4}');
select pg_temp.bulk_act(312, 'Yonsei International Summer School 2026 Global Marketing Track', 5, 23, 'outbound', '2026-06-29', '2026-07-24', 'offline', 'Yonsei University Sinchon Campus, Seoul', 'KR', 31, '{4,17}', 'Empat mahasiswa Manajemen mengikuti program musim panas empat minggu di Yonsei University pada jalur Global Marketing, termasuk kunjungan perusahaan ke CJ ENM dan Amorepacific. Diakui sebagai 6 SKS mata kuliah pilihan.', pg_temp.wib('2026-08-04', '09:00'), 'approved', pg_temp.wib('2026-08-12', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(312, '{D31239820,D31249725,D31249029,D31239881}', '{}', '{}');
select pg_temp.bulk_act(313, 'Seminar Manajemen SDM di Era Kecerdasan Buatan bersama Universiti Brunei Darussalam', 5, 10, 'inbound', '2026-05-20', '2026-05-20', 'offline', 'Auditorium Gedung W PCU', 'ID', 174, '{4,8}', 'Seminar yang membahas dampak kecerdasan buatan terhadap rekrutmen, pengembangan talenta, dan desain pekerjaan. Menghadirkan pembicara dari UBD School of Business and Economics dan praktisi HR Surabaya, diikuti 220 peserta dari kampus dan industri.', pg_temp.wib('2026-05-25', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Nur Amalina Haji Mohamad", "institution": "Universiti Brunei Darussalam", "country_code": "BN", "role": "speaker"}]', p_co_units => '{4}');
select pg_temp.bulk_act(314, 'Guest Lecture Circular Business Models dari Amsterdam Business School', 5, 15, 'inbound', '2026-09-02', '2026-09-02', 'hybrid', 'Auditorium Gedung W PCU', 'ID', 166, '{9,12}', 'Kuliah tamu mengenai model bisnis sirkular dan contoh penerapannya pada UMKM di Belanda bagi mahasiswa mata kuliah Inovasi Model Bisnis. Sesi hybrid diikuti mahasiswa di auditorium dan peserta daring dari Amsterdam.', pg_temp.wib('2026-09-07', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Maarten de Vries", "institution": "University of Amsterdam", "country_code": "NL", "role": "speaker"}]', p_co_units => '{4}');
select pg_temp.bulk_act(315, 'Magang Digital Business Telkom Indonesia Batch Agustus 2026', 5, 21, 'outbound', '2026-08-03', '2026-09-25', 'offline', 'Gedung Telkom Ketintang Surabaya', 'ID', 152, '{8,9}', 'Dua mahasiswa Manajemen magang delapan minggu di unit Digital Business Telkom Regional V untuk mendukung riset pasar layanan Pijar dan analisis funnel penjualan digital UMKM.', pg_temp.daysago(6, '09:00'), 'pending', pg_temp.daysago(6, '09:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(315, '{D31239083,D31239791}', '{}', '{}');
select pg_temp.bulk_act(316, 'Studi Ekskursi Rantai Pasok Sentra UMKM Kerajinan Yogyakarta bersama UGM', 5, 24, 'outbound', '2026-09-14', '2026-09-17', 'offline', 'Fakultas Ekonomika dan Bisnis UGM', 'ID', 28, '{8,12}', 'Kunjungan studi ke sentra kerajinan perak Kotagede dan gerabah Kasongan bersama dosen FEB UGM untuk memetakan rantai pasok dan saluran distribusi UMKM. Mahasiswa mempresentasikan rekomendasi perbaikan logistik di FEB UGM.', pg_temp.daysago(12, '09:00'), 'pending', pg_temp.daysago(12, '09:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(316, '{D31259442,D31239676,D31249971,D31259588,D31249923}', '{}', '{}');
select pg_temp.bulk_act(317, 'Indonesian Business Culture Immersion untuk Mahasiswa Chulalongkorn 2026', 5, 22, 'inbound', '2026-08-03', '2026-08-21', 'offline', 'Kampus PCU Siwalankerto', 'ID', 25, '{4,17}', 'Program imersi tiga minggu bagi mahasiswa Chulalongkorn Business School tentang budaya bisnis Indonesia, negosiasi lintas budaya, dan kunjungan ke perusahaan keluarga di Surabaya. Ditutup dengan presentasi rencana masuk pasar Indonesia.', pg_temp.daysago(15, '09:00'), 'revision_requested', pg_temp.daysago(8, '14:00'), p_mnote => 'Transkrip nilai dan sertifikat program mahasiswa inbound belum dilampirkan pada berkas mobilitas; mohon unggah ulang beserta daftar hadir harian.', p_co_units => '{4}');
select pg_temp.bulk_pset(317, '{}', '{X05259016}', '{}');
select pg_temp.bulk_act(318, 'Pendampingan Pemasaran Digital UMKM Kampung Kue Rungkut bersama Telkom Indonesia', 5, 40, 'outbound', '2026-08-08', '2026-09-12', 'offline', 'Kampung Kue Rungkut Lor Surabaya', 'ID', 152, '{1,8,17}', 'Mahasiswa dan dosen Manajemen bersama relawan Telkom mendampingi 30 pelaku UMKM kue dalam foto produk, pemasaran WhatsApp Business, dan pembayaran QRIS. Luaran berupa peningkatan pesanan daring dan katalog bersama kampung.', pg_temp.wib('2026-09-18', '09:00'), null, null, p_ext => '[{"full_name": "Yudha Kurniawan, S.E.", "institution": "PT Telkom Indonesia (Persero) Tbk", "country_code": "ID", "role": "staff_visitor"}]', p_co_units => '{4}');
select pg_temp.bulk_act(319, 'Joint Research Digital Supply Chain Resilience dengan National Taiwan University', 5, 4, 'outbound', '2026-10-15', '2027-01-29', 'hybrid', 'National Taiwan University, Taipei', 'TW', 15, '{9,17}', 'Rencana penelitian bersama tentang adopsi platform digital untuk ketahanan rantai pasok eksportir furnitur Jawa Timur ke Taiwan. Tahap awal berupa penyusunan instrumen dan pengumpulan data wawancara.', null, null, null, p_files => '{ia}', p_ext => '[{"full_name": "Prof. Chen Yu-ting, Ph.D.", "institution": "National Taiwan University", "country_code": "TW", "role": "researcher"}]', p_co_units => '{4}');
select pg_temp.bulk_act(320, 'Studi Ekskursi Bisnis Digital ke Telkom Indonesia Jakarta', 5, 24, 'outbound', '2026-11-17', '2026-11-20', 'offline', 'Telkom Landmark Tower Jakarta', 'ID', 168, '{8,9}', 'Rencana kunjungan studi ke program inkubasi korporat Telkom Indonesia untuk mempelajari pengembangan produk digital dan corporate venture. Peserta dari Prodi Manajemen konsentrasi Bisnis Digital.', null, null, null, p_co_units => '{4}');
select pg_temp.bulk_pset(320, '{D31249994,D31249546,D31249797,D31239469}', '{}', '{}');

select pg_temp.bulk_verify(296, 320);
