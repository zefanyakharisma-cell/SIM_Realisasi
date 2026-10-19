-- seed-supabase/10_kegiatan_tambahan_6 (simks-partnership): additional bulk kegiatan 346-370, adapted from the local
-- demo seed supabase/seed/04_bulk_6.sql to the real SIM Kerjasama units (Program Studi submitters) and agreements.
-- Generated from a reviewed JSON list; every row passes the guards below (agreement valid for the dates, submission
-- after the end date, Mobility decision after the submission, participant set for every submitted mobility kegiatan,
-- no student in two overlapping kegiatan, unique names). Needs 03_accounts.sql and 09_registries_tambahan.sql.
-- Self-contained and idempotent (existing rows are skipped), so it can be run on its own: Supabase SQL Editor or one
-- statement batch. Writes only realisasi.*; SIM Kerjasama tables are only read.

-- The kegiatan reference SIM Kerjasama agreements 156, 167, 177, 200, 204, 205, 206, 207, 208. Where any is missing (e.g. the local
-- --rehearse fixture, which only mirrors agreements 11-52) the whole file is skipped with a notice instead of failing.
drop table if exists pg_temp.tambahan_skip;
create temp table tambahan_skip as
select exists (select 1 from unnest('{156,167,177,200,204,205,206,207,208}'::int[]) d where not exists (select 1 from kerjasama.documents k where k.id = d)) as skip;
do $$ begin if (select skip from pg_temp.tambahan_skip) then
  raise notice '10_kegiatan_tambahan_6: SIM Kerjasama agreements missing, kegiatan 346-370 skipped'; end if; end $$;


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

select pg_temp.bulk_act(346, 'Pertukaran Pelajar Spring Session 2025 Visual Communication di University of Technology Sydney', 63, 2, 'outbound', '2025-08-04', '2025-11-21', 'offline', 'UTS City Campus, Ultimo, Sydney', 'AU', 206, '{4,17}', 'Tiga mahasiswa DKV mengikuti satu semester Spring Session di School of Design UTS, mengambil mata kuliah Visual Communication Studio dan Digital Media. Kredit dikonversi ke kurikulum DKV melalui skema transfer kredit.', pg_temp.wib('2025-12-03', '09:00'), 'approved', pg_temp.wib('2025-12-12', '14:00'));
select pg_temp.bulk_pset(346, '{C21239954,C21239549,C21239991}', '{}', '{}');
select pg_temp.bulk_act(347, 'Kuliah Tamu Motion Graphics untuk Narasi Data oleh UTS School of Design', 63, 15, 'inbound', '2025-09-17', '2025-09-17', 'hybrid', 'Auditorium Gedung P PCU', 'ID', 206, '{4,9}', 'Kuliah tamu tentang perancangan motion graphics untuk menyampaikan data kompleks secara naratif, dilengkapi studi kasus infografis animasi media berita Australia. Diikuti mahasiswa mata kuliah Desain Animasi secara luring dan daring.', pg_temp.wib('2025-09-24', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Rachel Bennett", "institution": "University of Technology Sydney", "country_code": "AU", "role": "speaker"}]', p_co_units => '{32}');
select pg_temp.bulk_act(348, 'Inbound Short Program Batik Pesisir dan Arsip Visual Kota Lama Surabaya untuk Mahasiswa Hochschule Bremen', 63, 23, 'inbound', '2025-09-08', '2025-09-26', 'offline', 'Studio DKV Gedung P PCU', 'ID', 205, '{4,11}', 'Program singkat tiga minggu bagi mahasiswa Hochschule Bremen untuk mempelajari motif batik pesisir dan arsip visual kota lama Surabaya. Luaran berupa seri ilustrasi dan pola permukaan yang dipamerkan di akhir program.', pg_temp.wib('2025-10-06', '09:00'), 'approved', pg_temp.wib('2025-10-14', '14:00'));
select pg_temp.bulk_pset(348, '{}', '{X05259028}', '{}');
select pg_temp.bulk_act(349, 'Riset Bersama Tipografi Aksara Jawa untuk Antarmuka Digital dengan Hochschule Bremen', 63, 4, 'outbound', '2025-08-18', '2025-12-12', 'hybrid', 'Lab Tipografi DKV Gedung P PCU', 'ID', 205, '{4,9}', 'Penelitian bersama untuk merancang varian font aksara Jawa yang terbaca baik pada layar ponsel. Tim menguji keterbacaan pada antarmuka aplikasi dan menyiapkan draf artikel jurnal bersama peneliti desain Hochschule Bremen.', pg_temp.wib('2026-01-20', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Jan Hoffmann", "institution": "Hochschule Bremen", "country_code": "DE", "role": "researcher"}]');
select pg_temp.bulk_act(350, 'Workshop Game Art dan Character Design bersama UTS Games Studio', 63, 35, 'inbound', '2025-10-20', '2025-10-22', 'offline', 'Lab Komputer Grafis Gedung P PCU', 'ID', 206, '{4,8}', 'Workshop tiga hari tentang pipeline game art mulai dari concept sketch, character sheet, hingga aset 2D siap pakai di game engine. Peserta menghasilkan satu karakter orisinal yang direview langsung oleh mentor UTS.', pg_temp.wib('2025-10-30', '09:00'), null, null, p_ext => '[{"full_name": "Mr. Thomas Nguyen", "institution": "University of Technology Sydney", "country_code": "AU", "role": "speaker", "notes": "Lecturer, Games Development"}]');
select pg_temp.bulk_act(351, 'Pertukaran Budaya Fotografi Dokumenter Pasar Tradisional bersama Mahasiswa Taylor''s University', 63, 29, 'inbound', '2025-11-03', '2025-11-14', 'offline', 'Kampus PCU Siwalankerto', 'ID', 167, '{4,11}', 'Mahasiswa Taylor''s University mengikuti program pertukaran budaya dengan fokus fotografi dokumenter kehidupan pasar tradisional Surabaya bersama mahasiswa DKV. Hasil foto dikurasi menjadi e-zine bersama.', pg_temp.wib('2025-11-20', '09:00'), 'approved', pg_temp.wib('2025-11-28', '14:00'));
select pg_temp.bulk_pset(351, '{}', '{X06269030}', '{}');
select pg_temp.bulk_act(352, 'Online Course UX Research Fundamentals bersama UTS', 63, 79, 'inbound', '2025-10-06', '2025-11-28', 'online', 'Zoom Meeting', null, 206, '{4,9}', 'Kursus daring delapan minggu tentang metode riset pengguna: wawancara, usability testing, dan journey mapping. Materi disampaikan dosen UTS dan dipakai sebagai pengayaan mata kuliah Desain UI/UX.', pg_temp.wib('2025-12-05', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Priya Raman", "institution": "University of Technology Sydney", "country_code": "AU", "role": "visiting_lecturer"}]');
select pg_temp.bulk_act(353, 'Summer Program Ilustrasi dan Picture Book di University of Technology Sydney', 63, 23, 'outbound', '2026-01-05', '2026-01-23', 'offline', 'UTS City Campus, Ultimo, Sydney', 'AU', 206, '{4,17}', 'Empat mahasiswa DKV mengikuti program musim panas UTS tentang ilustrasi buku cerita anak, dari pengembangan karakter hingga storyboard dan dummy book. Didampingi satu dosen DKV.', pg_temp.wib('2026-02-02', '09:00'), 'approved', pg_temp.wib('2026-02-10', '14:00'));
select pg_temp.bulk_pset(353, '{C21239626,C21239301,C21249196,C21249481}', '{}', '{}');
select pg_temp.bulk_act(354, 'Pertukaran Pelajar Autumn Session 2026 Digital Media di University of Technology Sydney', 63, 2, 'outbound', '2026-02-23', '2026-06-19', 'offline', 'UTS City Campus, Ultimo, Sydney', 'AU', 206, '{4,17}', 'Pertukaran satu semester bagi tiga mahasiswa DKV di program Digital and Social Media UTS, dengan mata kuliah animasi, interaction design, dan media studies. Nilai dikonversi melalui transfer kredit.', pg_temp.wib('2026-06-29', '09:00'), 'approved', pg_temp.wib('2026-07-08', '14:00'));
select pg_temp.bulk_pset(354, '{C21239888,C21239659,C21249776}', '{}', '{}');
select pg_temp.bulk_act(355, 'Semester Pertukaran Mahasiswa UTS di Prodi DKV Genap 2025/2026', 63, 2, 'inbound', '2026-02-09', '2026-06-12', 'offline', 'Kampus PCU Siwalankerto', 'ID', 206, '{4,17}', 'Dua mahasiswa UTS mengikuti satu semester di Prodi DKV, mengambil mata kuliah Desain Komunikasi Visual Nusantara, Fotografi, dan Bahasa Indonesia untuk Penutur Asing.', pg_temp.wib('2026-06-22', '09:00'), 'approved', pg_temp.wib('2026-07-01', '14:00'));
select pg_temp.bulk_pset(355, '{}', '{X06269026,X06269027}', '{}');
select pg_temp.bulk_act(356, 'Guest Lecture Brand Identity untuk Destinasi Wisata oleh UTS', 63, 7, 'inbound', '2026-03-11', '2026-03-11', 'offline', 'Auditorium Gedung W PCU', 'ID', 206, '{8,11}', 'Kuliah umum tentang perancangan identitas merek destinasi wisata, membahas kasus rebranding kawasan kota di New South Wales dan peluang penerapannya untuk kawasan Kota Lama Surabaya.', pg_temp.wib('2026-03-18', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Sarah Mitchell", "institution": "University of Technology Sydney", "country_code": "AU", "role": "speaker"}]');
select pg_temp.bulk_act(357, 'Seminar Internasional Visualisasi Informasi dan Desain Interaksi bersama NTUST', 63, 10, 'inbound', '2026-04-15', '2026-04-16', 'hybrid', 'Auditorium Gedung W PCU', 'ID', 200, '{4,9,17}', 'Seminar dua hari yang mempertemukan peneliti Fakultas Humaniora dan Industri Kreatif dengan NTUST untuk membahas visualisasi informasi, dashboard publik, dan desain interaksi. Mahasiswa DKV mempresentasikan poster karya riset.', pg_temp.wib('2026-04-24', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Chen Wei-Lun", "institution": "National Taiwan University of Science and Technology", "country_code": "TW", "role": "speaker"}]', p_co_units => '{32}');
select pg_temp.bulk_act(358, 'Pengembangan Kurikulum Peminatan Animasi 2D dan 3D bersama UTS', 63, 11, 'inbound', '2026-03-02', '2026-05-29', 'hybrid', 'Ruang Rapat Prodi DKV Gedung P PCU', 'ID', 206, '{4}', 'Penyusunan ulang capaian pembelajaran dan rencana studi peminatan animasi dengan membandingkan struktur mata kuliah animasi UTS. Luaran berupa dokumen RPS baru untuk empat mata kuliah.', pg_temp.wib('2026-06-05', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Hannah Brooks", "institution": "University of Technology Sydney", "country_code": "AU", "role": "other", "notes": "Program coordinator, Animation"}]');
select pg_temp.bulk_act(359, 'Pengabdian Masyarakat Rebranding UMKM Kampung Kue Rungkut bersama Pemerintah Kota Surabaya', 63, 40, 'inbound', '2026-04-20', '2026-05-15', 'offline', 'Kampung Kue Rungkut Lor, Surabaya', 'ID', 207, '{1,8,11}', 'Dosen dan mahasiswa DKV bersama Dinas Koperasi dan UMKM Pemerintah Kota Surabaya mendampingi pelaku usaha kue di Rungkut Lor merancang ulang logo, kemasan, dan konten media sosial. Sebanyak dua belas usaha menerima paket identitas visual baru.', pg_temp.wib('2026-05-25', '09:00'), null, null, p_ext => '[{"full_name": "Ibu Retno Wulandari, S.E.", "institution": "Pemerintah Kota Surabaya", "country_code": "ID", "role": "staff_visitor"}]');
select pg_temp.bulk_act(360, 'Studi Ekskursi Film Dokumenter ke Institut Teknologi Bandung', 63, 24, 'outbound', '2026-05-11', '2026-05-15', 'offline', 'Kampus ITB Ganesha, Bandung', 'ID', 208, '{4,11}', 'Mahasiswa peminatan film mengunjungi studio dan laboratorium Fakultas Seni Rupa dan Desain ITB, mengikuti kelas produksi dokumenter, serta merekam film pendek tentang ruang publik Bandung.', pg_temp.wib('2026-05-22', '09:00'), 'approved', pg_temp.wib('2026-06-02', '14:00'));
select pg_temp.bulk_pset(360, '{C21249147,C21229377,C21229391,C21239562,C21249999,C21229931}', '{}', '{}');
select pg_temp.bulk_act(361, 'Publikasi Bersama Kajian Visual Kampanye Iklim di Media Sosial dengan Temasek Polytechnic', 63, 5, 'outbound', '2026-02-02', '2026-07-17', 'online', 'Microsoft Teams', null, 177, '{13,4}', 'Kolaborasi penulisan artikel yang menganalisis strategi visual kampanye perubahan iklim di Instagram Indonesia dan Singapura bersama dosen Temasek Polytechnic School of Design. Naskah dikirim ke jurnal desain bereputasi.', pg_temp.wib('2026-08-24', '09:00'), null, null, p_ext => '[{"full_name": "Ms. Megan Tan Hui Ling", "institution": "Temasek Polytechnic", "country_code": "SG", "role": "researcher"}]');
select pg_temp.bulk_act(362, 'Magang Desain UX/UI di Temasek Polytechnic Design School', 63, 21, 'outbound', '2026-06-29', '2026-07-31', 'offline', 'Temasek Polytechnic, Tampines, Singapore', 'SG', 177, '{8,9}', 'Tiga mahasiswa DKV magang di unit pengembangan pembelajaran digital Temasek Polytechnic, merancang prototipe antarmuka modul e-learning dan melakukan usability test bersama tim produk.', pg_temp.wib('2026-08-07', '09:00'), 'approved', pg_temp.wib('2026-08-17', '14:00'));
select pg_temp.bulk_pset(362, '{C21249451,C21239724,C21239896}', '{}', '{}');
select pg_temp.bulk_act(363, 'Short Program Desain Kemasan Berkelanjutan di KMUTT Bangkok', 63, 23, 'outbound', '2026-08-03', '2026-08-14', 'offline', 'KMUTT Bang Mod Campus, Bangkok', 'TH', 156, '{9,12}', 'Program singkat dua minggu di King Mongkut''s University of Technology Thonburi tentang desain kemasan ramah lingkungan, material alternatif, dan komunikasi visual label produk. Diikuti mahasiswa DKV dengan pendamping dari fakultas.', pg_temp.wib('2026-08-20', '09:00'), 'approved', pg_temp.wib('2026-08-31', '14:00'), p_co_units => '{32}');
select pg_temp.bulk_pset(363, '{C21259848,C21259343,C21259948}', '{}', '{}');
select pg_temp.bulk_act(364, 'Kuliah Tamu Sinematografi dan Color Grading dari UTS Film Studies', 63, 15, 'inbound', '2026-09-02', '2026-09-02', 'offline', 'Auditorium Gedung P PCU', 'ID', 206, '{4,8}', 'Kuliah tamu tentang bahasa visual sinematografi dan alur color grading untuk film pendek, disertai demo langsung penyuntingan warna pada footage karya mahasiswa DKV.', pg_temp.wib('2026-09-09', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Benjamin Clarke", "institution": "University of Technology Sydney", "country_code": "AU", "role": "visiting_lecturer"}]');
select pg_temp.bulk_act(365, 'Inbound Short Program Ilustrasi Cerita Rakyat Jawa Timur untuk Mahasiswa Calvin University', 63, 23, 'inbound', '2026-08-10', '2026-09-04', 'offline', 'Studio Ilustrasi Gedung P PCU', 'ID', 204, '{4,11,17}', 'Mahasiswa Calvin University mempelajari cerita rakyat Jawa Timur dan menerjemahkannya menjadi ilustrasi naratif bersama mahasiswa DKV. Karya akhir dihimpun dalam buku digital dwibahasa.', pg_temp.daysago(12, '09:00'), 'pending', pg_temp.daysago(12, '09:00'), p_co_units => '{32}');
select pg_temp.bulk_pset(365, '{}', '{X05259029}', '{}');
select pg_temp.bulk_act(366, 'Short Program Animasi dan Visual Effects di University of Technology Sydney', 63, 23, 'outbound', '2026-08-24', '2026-09-18', 'offline', 'UTS City Campus, Ultimo, Sydney', 'AU', 206, '{4,9}', 'Tiga mahasiswa DKV mengikuti program singkat empat minggu tentang compositing, motion tracking, dan efek visual untuk animasi pendek di studio media UTS.', pg_temp.daysago(7, '09:00'), 'pending', pg_temp.daysago(7, '09:00'));
select pg_temp.bulk_pset(366, '{C21259543,C21259428,C21259142}', '{}', '{}');
select pg_temp.bulk_act(367, 'Inbound Academic Exchange Desain Game Edukasi dari University of Technology Sydney', 63, 28, 'inbound', '2026-08-03', '2026-09-11', 'offline', 'Lab Game Art Gedung P PCU', 'ID', 206, '{4,9}', 'Dua mahasiswa UTS bergabung dengan studio game art DKV selama enam minggu untuk mengembangkan prototipe game edukasi bertema budaya Surabaya bersama mahasiswa PCU.', pg_temp.daysago(15, '09:00'), 'revision_requested', pg_temp.daysago(6, '09:00'), p_mnote => 'Mohon unggah Letter of Acceptance untuk Hamish Clarke dan perbaiki nomor mahasiswa asal Mia Robertson sesuai transkrip UTS.');
select pg_temp.bulk_pset(367, '{}', '{X06269026,X06269027}', '{}');
select pg_temp.bulk_act(368, 'Pameran Bersama Poster Tipografi Eksperimental PCU dan Hochschule Bremen', 63, 35, 'inbound', '2026-09-14', '2026-09-19', 'hybrid', 'Galeri Gedung P PCU', 'ID', 205, '{4,11,17}', 'Pameran enam hari yang menampilkan 60 poster tipografi eksperimental karya mahasiswa DKV dan Hochschule Bremen, dilengkapi tur virtual dan diskusi kuratorial daring bersama dosen Bremen.', pg_temp.wib('2026-09-25', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Jan Hoffmann", "institution": "Hochschule Bremen", "country_code": "DE", "role": "speaker", "notes": "Kurator tamu"}]');
select pg_temp.bulk_act(369, 'Riset Bersama Visual Storytelling Edukasi Mitigasi Banjir dengan UTS', 63, 4, 'outbound', '2026-11-02', '2027-01-29', 'hybrid', 'Lab Riset DKV Gedung P PCU', 'ID', 206, '{11,13}', 'Rencana riset bersama untuk merancang komik dan animasi pendek edukasi mitigasi banjir bagi siswa sekolah dasar di Surabaya, diuji efektivitasnya bersama tim UTS.', null, null, null, p_files => '{ia}');
select pg_temp.bulk_act(370, 'Staff Exchange Dosen DKV ke UTS School of Design', 63, 3, 'outbound', '2026-11-16', '2026-11-27', 'offline', 'UTS City Campus, Ultimo, Sydney', 'AU', 206, '{4,17}', 'Dua dosen DKV direncanakan mengajar bersama di kelas Visual Communication UTS dan mempelajari tata kelola studio kreatif kampus sebagai bahan pengembangan laboratorium DKV.', null, null, null, p_ext => '[{"full_name": "Prof. Sarah Mitchell", "institution": "University of Technology Sydney", "country_code": "AU", "role": "other", "notes": "Tuan rumah program"}]');

select pg_temp.bulk_verify(346, 370);
