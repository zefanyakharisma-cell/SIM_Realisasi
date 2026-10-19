-- seed-supabase/10_kegiatan_tambahan_5 (simks-partnership): additional bulk kegiatan 321-345, adapted from the local
-- demo seed supabase/seed/04_bulk_5.sql to the real SIM Kerjasama units (Program Studi submitters) and agreements.
-- Generated from a reviewed JSON list; every row passes the guards below (agreement valid for the dates, submission
-- after the end date, Mobility decision after the submission, participant set for every submitted mobility kegiatan,
-- no student in two overlapping kegiatan, unique names). Needs 03_accounts.sql and 09_registries_tambahan.sql.
-- Self-contained and idempotent (existing rows are skipped), so it can be run on its own: Supabase SQL Editor or one
-- statement batch. Writes only realisasi.*; SIM Kerjasama tables are only read.

-- The kegiatan reference SIM Kerjasama agreements 64, 106, 117, 150, 156, 161, 174, 175, 177, 200, 205, 206. Where any is missing (e.g. the local
-- --rehearse fixture, which only mirrors agreements 11-52) the whole file is skipped with a notice instead of failing.
drop table if exists pg_temp.tambahan_skip;
create temp table tambahan_skip as
select exists (select 1 from unnest('{64,106,117,150,156,161,174,175,177,200,205,206}'::int[]) d where not exists (select 1 from kerjasama.documents k where k.id = d)) as skip;
do $$ begin if (select skip from pg_temp.tambahan_skip) then
  raise notice '10_kegiatan_tambahan_5: SIM Kerjasama agreements missing, kegiatan 321-345 skipped'; end if; end $$;


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

select pg_temp.bulk_act(321, 'Student Exchange Interior Architecture di Hochschule Bremen Semester Ganjil 2025', 59, 2, 'outbound', '2025-09-08', '2025-12-26', 'offline', 'School of Architecture, Civil and Environmental Engineering, Hochschule Bremen', 'DE', 205, '{4,9,17}', 'Pertukaran pelajar satu semester mahasiswa Desain Interior di Hochschule Bremen dengan mata kuliah studio interior architecture dan desain furnitur. Kredit yang diperoleh dikonversi ke kurikulum Desain Interior PCU.', pg_temp.wib('2026-01-09', '09:00'), 'approved', pg_temp.wib('2026-01-16', '14:00'), p_co_units => '{32}');
select pg_temp.bulk_pset(321, '{C22239024,C22239955,C22239188}', '{}', '{}');
select pg_temp.bulk_act(322, 'Pameran dan Seminar Batik Kontemporer Motif Pesisiran Jawa Timur bersama UGM', 59, 35, 'inbound', '2025-10-02', '2025-10-03', 'offline', 'Galeri Gedung P PCU', 'ID', 117, '{4,11,12}', 'Pameran karya batik kontemporer bermotif pesisiran Jawa Timur yang diterapkan pada elemen interior, disertai seminar tentang reinterpretasi motif tradisional dalam desain tekstil modern bersama pembicara dari UGM.', pg_temp.wib('2025-10-20', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Dyah Ayu Pratiwi, M.A.", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "speaker", "notes": "Departemen Sejarah dan Seni, Fakultas Ilmu Budaya UGM"}]', p_co_units => '{32}');
select pg_temp.bulk_act(323, 'Kuliah Tamu Desain Interior Adaptif Iklim Tropis oleh Dosen University of Technology Sydney', 59, 15, 'inbound', '2025-10-20', '2025-10-22', 'hybrid', 'Studio Desain Interior Gedung P PCU', 'ID', 206, '{4,11,13}', 'Rangkaian kuliah tamu tiga hari tentang strategi desain interior pasif untuk iklim tropis lembap, termasuk studi kasus hunian di Australia utara dan sesi kritik studio mahasiswa.', pg_temp.wib('2025-11-05', '09:00'), null, null, p_ext => '[{"full_name": "Assoc. Prof. Sarah Whitfield", "institution": "University of Technology Sydney", "country_code": "AU", "role": "visiting_lecturer", "notes": "School of Design, Faculty of Design, Architecture and Building"}]', p_co_units => '{32}');
select pg_temp.bulk_act(324, 'Short Program Design Thinking for Social Innovation di KMUTT Bangkok', 59, 23, 'outbound', '2025-11-03', '2025-11-21', 'offline', 'School of Architecture and Design, KMUTT, Bangkok', 'TH', 156, '{4,10,17}', 'Program singkat tiga minggu di KMUTT yang melatih metode design thinking untuk inovasi sosial melalui proyek lapangan bersama komunitas di Bangkok. Luaran berupa prototipe ruang layanan dan presentasi akhir.', pg_temp.wib('2025-12-05', '09:00'), 'approved', pg_temp.wib('2025-12-12', '14:00'), p_co_units => '{32}');
select pg_temp.bulk_pset(324, '{C22249123,C22249999,C22229438,C22249635}', '{}', '{PG452412}');
select pg_temp.bulk_act(325, 'Riset Bersama Dokumentasi Digital Wayang Kulit Jawa Timuran dengan Ateneo de Manila University', 57, 4, 'inbound', '2025-08-18', '2025-12-12', 'hybrid', 'Laboratorium Media Gedung P PCU', 'ID', 161, '{4,9,11}', 'Penelitian bersama untuk mendigitalkan koleksi wayang kulit gaya Jawa Timuran melalui fotogrametri dan pemodelan 3D, serta menyusun arsip daring yang dapat diakses peneliti di Indonesia dan Filipina.', pg_temp.wib('2026-01-12', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Maria Isabel Santos", "institution": "Ateneo de Manila University", "country_code": "PH", "role": "researcher", "notes": "Department of Communication, School of Social Sciences"}]', p_co_units => '{32}');
select pg_temp.bulk_act(326, 'Inbound Exchange Interior Architecture dari University of Technology Sydney Semester Ganjil 2025', 59, 2, 'inbound', '2025-08-25', '2025-12-12', 'offline', 'Kampus PCU Siwalankerto', 'ID', 206, '{4,17}', 'Mahasiswa pertukaran dari University of Technology Sydney mengikuti satu semester perkuliahan studio desain interior dan kelas budaya Indonesia di PCU.', pg_temp.wib('2025-12-19', '09:00'), 'approved', pg_temp.wib('2025-12-30', '14:00'), p_co_units => '{32}');
select pg_temp.bulk_pset(326, '{}', '{X05259022}', '{}');
select pg_temp.bulk_act(327, 'Lomba Desain Produk Furnitur Rotan PCU–UKSW 2025', 59, 35, 'inbound', '2025-11-24', '2025-11-28', 'offline', 'Auditorium Gedung W PCU', 'ID', 106, '{8,9,12}', 'Kompetisi desain furnitur berbahan rotan untuk mahasiswa desain se-Jawa yang diselenggarakan bersama UKSW, dengan penjurian prototipe dan pameran karya finalis.', pg_temp.wib('2025-12-10', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Yohanes Kristiawan, M.Ds.", "institution": "Universitas Kristen Satya Wacana", "country_code": "ID", "role": "other", "notes": "Juri, Program Studi Desain Komunikasi Visual UKSW"}]', p_co_units => '{32}');
select pg_temp.bulk_act(328, 'Pengabdian Masyarakat Branding dan Kemasan Batik Tulis Tanjungbumi bersama UGM', 57, 40, 'outbound', '2026-01-12', '2026-01-16', 'offline', 'Sentra Batik Tulis Tanjungbumi, Bangkalan', 'ID', 64, '{1,8,12}', 'Pendampingan perajin batik tulis Tanjungbumi dalam merancang kemasan, identitas merek, dan konten media sosial agar produk siap dipasarkan secara daring, bersama tim pengabdian Departemen Ilmu Komunikasi UGM.', pg_temp.wib('2026-02-02', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Novi Kurnia, M.Si.", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "other", "notes": "Pendamping pengabdian masyarakat, Departemen Ilmu Komunikasi Fisipol UGM"}]', p_co_units => '{32}');
select pg_temp.bulk_act(329, 'Student Exchange Desain Produk dan Interior di Ateneo de Manila University Semester Genap 2026', 59, 2, 'outbound', '2026-02-02', '2026-05-29', 'offline', 'Ateneo de Manila University, Loyola Heights, Quezon City', 'PH', 161, '{4,17}', 'Mahasiswa Desain Interior menempuh satu semester di Ateneo de Manila University dengan fokus mata kuliah information design dan fine arts. Hasil studi dialihkreditkan ke kurikulum Desain Interior PCU.', pg_temp.wib('2026-06-12', '09:00'), 'approved', pg_temp.wib('2026-06-22', '14:00'), p_co_units => '{32}');
select pg_temp.bulk_pset(329, '{C22249514,C22239208,C22249824}', '{}', '{}');
select pg_temp.bulk_act(330, 'Credit Transfer Interior Architecture Temasek Polytechnic di PCU Semester Genap 2026', 59, 33, 'inbound', '2026-02-09', '2026-06-19', 'offline', 'Kampus PCU Siwalankerto', 'ID', 177, '{4,17}', 'Mahasiswa Temasek Polytechnic mengikuti program transfer kredit di PCU, mengambil studio desain interior, kriya kayu, dan kelas Bahasa Indonesia untuk penutur asing.', pg_temp.wib('2026-06-30', '09:00'), 'approved', pg_temp.wib('2026-07-08', '14:00'), p_co_units => '{32}');
select pg_temp.bulk_pset(330, '{}', '{X05259025}', '{}');
select pg_temp.bulk_act(331, 'Pengembangan Kurikulum Bersama Desain Interior Berkelanjutan dengan Hochschule Bremen', 59, 32, 'outbound', '2026-02-16', '2026-04-24', 'online', 'Zoom Meeting', null, 205, '{4,12}', 'Serangkaian lokakarya daring untuk menyusun mata kuliah bersama tentang desain interior berkelanjutan, mencakup capaian pembelajaran, rubrik penilaian studio, dan modul material ramah lingkungan.', pg_temp.wib('2026-05-06', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Lisa Hartmann", "institution": "Hochschule Bremen", "country_code": "DE", "role": "other", "notes": "Koordinator program Architecture and Interior Design"}]', p_co_units => '{32}');
select pg_temp.bulk_act(332, 'Pameran Bersama Wayang Kontemporer Indonesia–Taiwan di NTUST', 57, 35, 'outbound', '2026-03-16', '2026-03-27', 'offline', 'NTUST Design Gallery, Taipei', 'TW', 200, '{4,11,17}', 'Pameran karya dosen dan mahasiswa yang menafsirkan ulang tokoh wayang dalam media ilustrasi, video, dan instalasi, berdampingan dengan karya puppetry kontemporer mahasiswa NTUST.', pg_temp.wib('2026-04-10', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Chen Kuo-Hsiang", "institution": "National Taiwan University of Science and Technology", "country_code": "TW", "role": "other", "notes": "Kurator pendamping, Department of Design"}]', p_co_units => '{32}');
select pg_temp.bulk_act(333, 'Studi Ekskursi Arsitektur Vernakular dan Interior Heritage ke UGM Yogyakarta', 59, 24, 'outbound', '2026-04-06', '2026-04-10', 'offline', 'Kampus UGM Bulaksumur, Yogyakarta', 'ID', 117, '{4,11}', 'Kunjungan studi mahasiswa ke Departemen Arsitektur UGM dan bangunan heritage di Yogyakarta untuk mempelajari arsitektur vernakular Jawa serta konservasi interior bangunan kolonial dan ndalem.', pg_temp.wib('2026-04-20', '09:00'), 'approved', pg_temp.wib('2026-04-28', '14:00'), p_co_units => '{32}');
select pg_temp.bulk_pset(333, '{C22239295,C22249177,C22229221,C22259857,C22229994,C22239024}', '{}', '{PG780858}');
select pg_temp.bulk_act(334, 'Workshop Rekayasa Bambu untuk Desain Produk bersama KMUTT', 59, 43, 'inbound', '2026-05-11', '2026-05-13', 'offline', 'Workshop Kriya Gedung P PCU', 'ID', 156, '{9,12,13}', 'Pelatihan tiga hari teknik laminasi dan pembentukan bambu untuk furnitur dan produk rumah tangga, dipandu dosen KMUTT, dengan luaran prototipe kursi lipat bambu.', pg_temp.wib('2026-05-22', '09:00'), null, null, p_ext => '[{"full_name": "Asst. Prof. Dr. Pornchai Wongsuwan", "institution": "King Mongkut''s University of Technology Thonburi", "country_code": "TH", "role": "visiting_lecturer", "notes": "School of Architecture and Design"}]', p_co_units => '{32}');
select pg_temp.bulk_act(335, 'Program Budaya Batik dan Wayang untuk Mahasiswa Kanazawa Institute of Technology 2026', 59, 29, 'inbound', '2026-07-06', '2026-07-24', 'offline', 'Kampus PCU Siwalankerto', 'ID', 175, '{4,11,17}', 'Program budaya tiga minggu bagi mahasiswa Kanazawa Institute of Technology: kelas membatik, pembuatan wayang kardus, kunjungan ke sanggar di Surabaya, dan pameran karya di akhir program.', pg_temp.wib('2026-08-05', '09:00'), 'approved', pg_temp.wib('2026-08-12', '14:00'), p_co_units => '{32}');
select pg_temp.bulk_pset(335, '{}', '{X05259023}', '{}');
select pg_temp.bulk_act(336, 'Guest Lecture Speculative Product Design dari KMUTT', 59, 7, 'inbound', '2026-03-04', '2026-03-04', 'online', 'Microsoft Teams', null, 156, '{4,9}', 'Kuliah tamu daring tentang pendekatan desain spekulatif dalam pengembangan produk dan ruang masa depan, disertai diskusi proyek mahasiswa studio desain.', pg_temp.wib('2026-03-12', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Nattapong Srisuk", "institution": "King Mongkut''s University of Technology Thonburi", "country_code": "TH", "role": "speaker", "notes": "Industrial Design Program"}]', p_co_units => '{32}');
select pg_temp.bulk_act(337, 'Creative Industries Study Tour Sydney bersama University of Technology Sydney', 57, 22, 'outbound', '2026-06-29', '2026-07-17', 'offline', 'UTS Faculty of Arts and Social Sciences, Ultimo, Sydney', 'AU', 206, '{4,11}', 'Program tiga minggu di UTS: studio produksi media dan komunikasi visual ruang publik, kunjungan ke museum dan agensi kreatif di Sydney, serta presentasi proyek kolaboratif bersama mahasiswa UTS.', pg_temp.wib('2026-07-31', '09:00'), 'approved', pg_temp.wib('2026-08-10', '14:00'), p_co_units => '{32}');
select pg_temp.bulk_pset(337, '{E42259904,E42249976,E42239200,E42249697,E42239001}', '{}', '{PG761401}');
select pg_temp.bulk_act(338, 'Magang Desain Interior di Design Lab KMUTT Bangkok', 59, 21, 'outbound', '2026-08-03', '2026-09-11', 'offline', 'KMUTT Bangmod Campus, Bangkok', 'TH', 156, '{4,8}', 'Magang enam minggu di Design Lab KMUTT yang menangani proyek interior ruang belajar kampus, meliputi survei pengguna, gambar kerja, dan visualisasi 3D.', pg_temp.daysago(8, '09:00'), 'pending', pg_temp.daysago(8, '09:00'), p_co_units => '{32}');
select pg_temp.bulk_pset(338, '{C22249123,C22249999}', '{}', '{}');
select pg_temp.bulk_act(339, 'Inbound Short Program Kriya Nusantara untuk Mahasiswa Hochschule Bremen', 59, 23, 'inbound', '2026-08-10', '2026-08-28', 'offline', 'Kampus PCU Siwalankerto', 'ID', 205, '{4,17}', 'Program singkat tiga minggu bagi mahasiswa Hochschule Bremen untuk mempelajari kriya Nusantara (batik, anyaman, ukir kayu) melalui kelas praktik dan kunjungan ke sentra kerajinan Jawa Timur.', pg_temp.daysago(15, '09:00'), 'revision_requested', pg_temp.daysago(9, '14:00'), p_mnote => 'Transkrip nilai peserta belum diunggah dan poster kegiatan masih memakai logo lama. Mohon lengkapi bundel transkrip/poster/dokumentasi lalu ajukan ulang.', p_co_units => '{32}');
select pg_temp.bulk_pset(339, '{}', '{X06259021}', '{}');
select pg_temp.bulk_act(340, 'Riset Terapan Panel Interior dari Material Daur Ulang untuk Ruang Publik bersama Pakuwon', 59, 4, 'inbound', '2026-08-03', '2026-09-18', 'hybrid', 'Laboratorium Material Desain Gedung P PCU', 'ID', 150, '{9,11,12}', 'Penelitian terapan pengembangan panel interior dari limbah plastik dan serbuk kayu untuk area publik pusat perbelanjaan Pakuwon, termasuk uji ketahanan dan purwarupa panel akustik.', pg_temp.wib('2026-09-25', '09:00'), null, null, p_ext => '[{"full_name": "Ir. Hendra Gunawan, M.T.", "institution": "PT Pakuwon Jati Tbk", "country_code": "ID", "role": "researcher", "notes": "Divisi Perencanaan dan Desain Interior"}]', p_co_units => '{32}');
select pg_temp.bulk_act(341, 'Kompetisi Poster Warisan Budaya Asia Tenggara bersama Universiti Brunei Darussalam', 57, 35, 'outbound', '2026-08-17', '2026-09-04', 'online', 'Zoom Meeting', null, 174, '{4,11,17}', 'Kompetisi poster daring bertema warisan budaya takbenda Asia Tenggara yang dijuri bersama dosen PCU dan Universiti Brunei Darussalam, ditutup dengan pengumuman pemenang dan pameran virtual.', pg_temp.wib('2026-09-14', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Siti Norhayati binti Haji Ahmad", "institution": "Universiti Brunei Darussalam", "country_code": "BN", "role": "other", "notes": "Juri, Faculty of Arts and Social Sciences"}]', p_co_units => '{32}');
select pg_temp.bulk_act(342, 'Academic Exchange Desain Pameran dan Kuratorial di Kanazawa Institute of Technology', 59, 28, 'outbound', '2026-08-24', '2026-09-18', 'offline', 'Kanazawa Institute of Technology, Nonoichi, Ishikawa', 'JP', 175, '{4,17}', 'Pertukaran akademik empat minggu untuk mempelajari desain ruang pameran dan praktik kuratorial di Kanazawa Institute of Technology, termasuk keterlibatan dalam penyiapan pameran tahunan mahasiswa.', pg_temp.daysago(4, '09:00'), 'pending', pg_temp.daysago(4, '09:00'), p_co_units => '{32}');
select pg_temp.bulk_pset(342, '{C22229438,C22239955,C22249635}', '{}', '{}');
select pg_temp.bulk_act(343, 'Seminar Nasional Pelestarian Interior Bangunan Kolonial Surabaya bersama UGM', 59, 10, 'inbound', '2026-09-09', '2026-09-10', 'offline', 'Auditorium Gedung W PCU', 'ID', 117, '{4,11}', 'Seminar dua hari tentang konservasi dan adaptasi interior bangunan kolonial di Surabaya, menghadirkan akademisi UGM dan praktisi cagar budaya, disertai tur lapangan ke kawasan Kota Lama.', pg_temp.wib('2026-09-21', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Ir. Ikaputra, M.Eng.", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "speaker", "notes": "Departemen Teknik Arsitektur dan Perencanaan UGM"}]', p_co_units => '{32}');
select pg_temp.bulk_act(344, 'Winter Program Craft Heritage dan Desain Kriya di NTUST 2027', 59, 23, 'outbound', '2027-01-11', '2027-01-29', 'offline', 'Department of Design, NTUST, Taipei', 'TW', 200, '{4,8,11}', 'Rencana program musim dingin di NTUST untuk mempelajari pengembangan kriya tradisional menjadi produk desain kontemporer, termasuk kunjungan ke sentra kerajinan di Taiwan.', null, null, null, p_files => '{ia}', p_co_units => '{32}');
select pg_temp.bulk_pset(344, '{C22239188,C22249514}', '{}', '{}');
select pg_temp.bulk_act(345, 'Pameran Dies Natalis Craft Heritage Batik dan Wayang bersama UKSW', 59, 35, 'inbound', '2026-11-16', '2026-11-20', 'offline', 'Galeri Gedung P PCU', 'ID', 106, '{4,11}', 'Rencana pameran Dies Natalis yang menampilkan karya batik dan wayang kontemporer hasil kolaborasi dosen dan mahasiswa Desain Interior PCU dengan UKSW.', null, null, null, p_files => '{}', p_co_units => '{32}');

select pg_temp.bulk_verify(321, 345);
