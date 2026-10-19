-- seed-supabase/10_kegiatan_tambahan_3 (simks-partnership): additional bulk kegiatan 271-295, adapted from the local
-- demo seed supabase/seed/04_bulk_3.sql to the real SIM Kerjasama units (Program Studi submitters) and agreements.
-- Generated from a reviewed JSON list; every row passes the guards below (agreement valid for the dates, submission
-- after the end date, Mobility decision after the submission, participant set for every submitted mobility kegiatan,
-- no student in two overlapping kegiatan, unique names). Needs 03_accounts.sql and 09_registries_tambahan.sql.
-- Self-contained and idempotent (existing rows are skipped), so it can be run on its own: Supabase SQL Editor or one
-- statement batch. Writes only realisasi.*; SIM Kerjasama tables are only read.

-- The kegiatan reference SIM Kerjasama agreements 15, 25, 30, 31, 70, 100, 112, 127, 143, 156, 158, 159, 160, 166, 167, 174. Where any is missing (e.g. the local
-- --rehearse fixture, which only mirrors agreements 11-52) the whole file is skipped with a notice instead of failing.
drop table if exists pg_temp.tambahan_skip;
create temp table tambahan_skip as
select exists (select 1 from unnest('{15,25,30,31,70,100,112,127,143,156,158,159,160,166,167,174}'::int[]) d where not exists (select 1 from kerjasama.documents k where k.id = d)) as skip;
do $$ begin if (select skip from pg_temp.tambahan_skip) then
  raise notice '10_kegiatan_tambahan_3: SIM Kerjasama agreements missing, kegiatan 271-295 skipped'; end if; end $$;


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

select pg_temp.bulk_act(271, 'Riset Bersama Sustainability Reporting UMKM Manufaktur dengan Universitas Pelita Harapan', 6, 4, 'outbound', '2025-09-01', '2025-12-15', 'offline', 'Fakultas Ekonomi dan Bisnis Universitas Pelita Harapan, Tangerang', 'ID', 112, '{12,8,17}', 'Penelitian bersama untuk menyusun model pelaporan keberlanjutan sederhana berbasis standar GRI bagi UMKM manufaktur di Jawa Timur dan Banten. Luaran berupa instrumen pengungkapan ESG dan draf artikel jurnal bersama.', pg_temp.wib('2025-12-19', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Rizky Aditya Wibisono, S.E., M.Ak.", "institution": "Universitas Pelita Harapan", "country_code": "ID", "role": "researcher", "notes": "Peneliti utama dari Program Studi Akuntansi FEB UPH"}]', p_co_units => '{4}');
select pg_temp.bulk_act(272, 'Student Exchange Akuntansi Yonsei School of Business Fall 2025', 6, 2, 'outbound', '2025-09-01', '2025-12-19', 'offline', 'Yonsei University Sinchon Campus, Seoul', 'KR', 143, '{4,17}', 'Tiga mahasiswa Akuntansi mengikuti satu semester perkuliahan di Yonsei School of Business, termasuk mata kuliah International Financial Reporting dan Managerial Accounting. Nilai dikonversi ke kurikulum Prodi Akuntansi PCU.', pg_temp.wib('2026-01-06', '09:00'), 'approved', pg_temp.wib('2026-01-15', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(272, '{D32249150,D32259472,D32249331}', '{}', '{}');
select pg_temp.bulk_act(273, 'Kuliah Tamu International Taxation and Transfer Pricing dari National Taiwan University', 5, 15, 'inbound', '2025-10-22', '2025-10-22', 'offline', 'Auditorium Gedung W PCU', 'ID', 30, '{4,8,17}', 'Kuliah tamu bagi mahasiswa Manajemen dan Akuntansi tentang perpajakan internasional, BEPS, dan dokumentasi transfer pricing pada grup usaha Taiwan–Indonesia. Diikuti sekitar 180 mahasiswa.', pg_temp.wib('2025-11-03', '09:00'), null, null, p_ext => '[{"full_name": "Assoc. Prof. Chen Wei-Ting", "institution": "National Taiwan University", "country_code": "TW", "role": "speaker", "notes": "Department of Accounting, College of Management"}]', p_co_units => '{6}');
select pg_temp.bulk_act(274, 'Short Program Hospitality & Tourism Management di KMUTT Bangkok', 5, 23, 'outbound', '2025-11-10', '2025-11-21', 'offline', 'KMUTT Bangmod Campus, Bangkok', 'TH', 156, '{8,4}', 'Program singkat dua minggu tentang manajemen hospitality, revenue management hotel, dan pariwisata berkelanjutan di Thailand, dilengkapi kunjungan industri ke hotel dan operator wisata di Bangkok.', pg_temp.wib('2025-12-02', '09:00'), 'approved', pg_temp.wib('2025-12-10', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(274, '{D31249692,D31239726,D31229821,D31229027}', '{}', '{}');
select pg_temp.bulk_act(275, 'Online Course Sustainable Finance and ESG Investing bersama University of Amsterdam', 5, 79, 'outbound', '2025-10-01', '2025-11-26', 'online', 'Microsoft Teams', null, 166, '{13,8,4}', 'Kursus daring delapan pertemuan mengenai keuangan berkelanjutan, analisis skor ESG, dan green bonds yang diampu dosen Amsterdam Business School. Peserta menyusun analisis portofolio ESG sebagai tugas akhir.', pg_temp.wib('2025-12-05', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Maarten de Vries", "institution": "University of Amsterdam", "country_code": "NL", "role": "visiting_lecturer", "notes": "Amsterdam Business School"}]', p_co_units => '{4}');
select pg_temp.bulk_act(276, 'International Conference on Accounting and Sustainable Finance (ICASF) 2025', 6, 10, 'inbound', '2025-11-27', '2025-11-28', 'hybrid', 'Gedung P PCU', 'ID', 112, '{8,12,17}', 'Konferensi internasional dua hari yang diselenggarakan School of Business and Management PCU bersama FEB Universitas Pelita Harapan dengan 64 makalah tentang akuntansi keberlanjutan, tata kelola, dan keuangan hijau. Prosiding terbit dengan ISBN.', pg_temp.wib('2025-12-08', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Dian Kartikasari, S.E., M.Si., Ak.", "institution": "Universitas Pelita Harapan", "country_code": "ID", "role": "speaker", "notes": "Keynote speaker"}, {"full_name": "Dr. Bagus Hendra Saputra, S.E., M.M.", "institution": "Universitas Pelita Harapan", "country_code": "ID", "role": "speaker"}]', p_co_units => '{5,4}');
select pg_temp.bulk_act(277, 'Inbound Exchange Curtin Business School di Prodi Akuntansi Semester Ganjil 2025/2026', 6, 2, 'inbound', '2025-09-01', '2026-01-16', 'offline', 'Kampus PCU Siwalankerto', 'ID', 160, '{4,17}', 'Mahasiswa Curtin Business School mengikuti satu semester perkuliahan di PCU, termasuk mata kuliah Asian Business Environment, Akuntansi Keuangan Lanjutan, dan Bahasa Indonesia untuk Penutur Asing.', pg_temp.wib('2026-01-27', '09:00'), 'approved', pg_temp.wib('2026-02-05', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(277, '{}', '{X05259014}', '{}');
select pg_temp.bulk_act(278, 'Pendampingan Pembukuan Digital UMKM Kuliner Siwalankerto bersama Universitas Negeri Surabaya', 5, 40, 'outbound', '2026-01-05', '2026-01-23', 'offline', 'Balai RW Kelurahan Siwalankerto, Surabaya', 'ID', 70, '{1,8,10}', 'Dosen dan mahasiswa Manajemen bersama tim Fakultas Ekonomika dan Bisnis Unesa mendampingi 25 pelaku UMKM kuliner menyusun pembukuan sederhana dengan aplikasi akuntansi gratis serta memisahkan keuangan usaha dan rumah tangga.', pg_temp.wib('2026-02-10', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Nurul Hidayati, S.E., M.Ak.", "institution": "Universitas Negeri Surabaya", "country_code": "ID", "role": "other", "notes": "Koordinator pengabdian masyarakat FEB Unesa"}]', p_co_units => '{4}');
select pg_temp.bulk_act(279, 'Inbound Exchange Yonsei University Spring 2026 di School of Business and Management', 6, 2, 'inbound', '2026-02-02', '2026-06-12', 'offline', 'Kampus PCU Siwalankerto', 'ID', 31, '{4,17}', 'Mahasiswa Yonsei University mengikuti semester genap di PCU dengan fokus pada akuntansi manajemen dan kewirausahaan di pasar Asia Tenggara, termasuk proyek konsultasi untuk UMKM Surabaya.', pg_temp.wib('2026-06-22', '09:00'), 'approved', pg_temp.wib('2026-06-30', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(279, '{}', '{X06259015}', '{}');
select pg_temp.bulk_act(280, 'Kunjungan Akademik Chulalongkorn Business School ke PCU 2026', 5, 27, 'inbound', '2026-02-24', '2026-02-25', 'offline', 'Gedung P PCU', 'ID', 25, '{4,17}', 'Delegasi Chulalongkorn Business School membahas benchmarking kurikulum International Business, skema transfer kredit, dan rencana penambahan kuota pertukaran mahasiswa untuk tahun akademik 2026/2027.', pg_temp.wib('2026-03-06', '09:00'), null, null, p_ext => '[{"full_name": "Asst. Prof. Dr. Pornchai Wongsawat", "institution": "Chulalongkorn University", "country_code": "TH", "role": "staff_visitor", "notes": "International Affairs Coordinator, Chulalongkorn Business School"}, {"full_name": "Dr. Natthaya Srisuk", "institution": "Chulalongkorn University", "country_code": "TH", "role": "staff_visitor", "notes": "Director, BBA International Program"}]', p_co_units => '{4}');
select pg_temp.bulk_act(281, 'Short Program Indonesian Business Culture untuk Mahasiswa Taylor''s University', 5, 23, 'inbound', '2026-03-02', '2026-03-13', 'offline', 'Gedung P PCU', 'ID', 167, '{4,8,17}', 'Program singkat dua minggu bagi mahasiswa Taylor''s Business School tentang budaya bisnis Indonesia, praktik bisnis keluarga Tionghoa-Indonesia, dan kunjungan perusahaan di Surabaya dan Gresik.', pg_temp.wib('2026-03-20', '09:00'), 'approved', pg_temp.wib('2026-03-27', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(281, '{}', '{X06269012}', '{}');
select pg_temp.bulk_act(282, 'Magang Hospitality Management di Taipei melalui National Taiwan University', 5, 21, 'outbound', '2026-02-02', '2026-04-30', 'offline', 'National Taiwan University, Taipei', 'TW', 30, '{8,4}', 'Magang tiga bulan di hotel mitra National Taiwan University di Taipei pada divisi front office, F&B, dan revenue management. Mahasiswa menyusun laporan magang yang diakui sebagai mata kuliah Magang Industri.', pg_temp.wib('2026-05-12', '09:00'), 'approved', pg_temp.wib('2026-05-20', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(282, '{D31229451,D31239549,D31249207}', '{}', '{}');
select pg_temp.bulk_act(283, 'Publikasi Bersama Kepatuhan Pajak UMKM Indonesia–Korea dengan Yonsei University', 5, 37, 'outbound', '2026-02-16', '2026-05-29', 'online', 'Microsoft Teams', null, 31, '{8,16,17}', 'Penulisan artikel bersama tentang faktor kepatuhan pajak UMKM di Indonesia dan Korea Selatan menggunakan data survei kedua negara. Naskah dikirim ke jurnal internasional bereputasi (Scopus Q2).', pg_temp.wib('2026-06-08', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Park Min-jae", "institution": "Yonsei University", "country_code": "KR", "role": "researcher", "notes": "Yonsei School of Business"}]', p_co_units => '{6}');
select pg_temp.bulk_act(284, 'Workshop Lean Startup dan Business Model Validation bersama Fontys', 5, 35, 'inbound', '2026-03-18', '2026-03-19', 'hybrid', 'Gedung P PCU', 'ID', 159, '{8,9,4}', 'Workshop kewirausahaan dua hari bagi mahasiswa inkubator bisnis PCU tentang validasi model bisnis, customer discovery, dan penyusunan pitch deck, difasilitasi pelatih dari Fontys Centre for Entrepreneurship.', pg_temp.wib('2026-03-30', '09:00'), null, null, p_ext => '[{"full_name": "Lotte van den Berg, MBA", "institution": "Fontys University of Applied Sciences", "country_code": "NL", "role": "speaker", "notes": "Fontys Centre for Entrepreneurship"}]', p_co_units => '{4}');
select pg_temp.bulk_act(285, 'Pengembangan Kurikulum Bersama Akuntansi Keberlanjutan dengan National Taiwan University', 6, 11, 'outbound', '2026-04-13', '2026-04-17', 'offline', 'NTU College of Management, Taipei', 'TW', 15, '{4,12,13}', 'Tim dosen Akuntansi menyusun bersama silabus mata kuliah Sustainability Accounting and Assurance yang akan ditawarkan di kedua universitas, termasuk studi kasus perusahaan Taiwan dan Indonesia.', pg_temp.wib('2026-04-28', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Lin Hsiao-Mei", "institution": "National Taiwan University", "country_code": "TW", "role": "other", "notes": "Department of Accounting, NTU College of Management"}]', p_co_units => '{4}');
select pg_temp.bulk_act(286, 'Studi Ekskursi Pasar Modal dan Fintech Seoul bersama Yonsei University', 6, 24, 'outbound', '2026-05-11', '2026-05-16', 'offline', 'Yonsei University Sinchon Campus, Seoul', 'KR', 31, '{8,9,4}', 'Kunjungan studi mahasiswa Akuntansi ke Korea Exchange, perusahaan fintech di Seoul, dan kelas bersama di Yonsei School of Business tentang regulasi pasar modal dan pelaporan keuangan digital.', pg_temp.wib('2026-05-26', '09:00'), 'approved', pg_temp.wib('2026-06-03', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(286, '{D32229204,D32239758,D32249505,D32259900,D32229279,D32249196,D32259976}', '{}', '{}');
select pg_temp.bulk_act(287, 'Kuliah Tamu Forensic Accounting dan Pencegahan Fraud dari Universitas Surabaya', 6, 7, 'inbound', '2026-06-03', '2026-06-03', 'offline', 'Auditorium Gedung W PCU', 'ID', 158, '{16,4}', 'Kuliah tamu tentang teknik akuntansi forensik, red flag kecurangan laporan keuangan, dan studi kasus investigasi fraud di BUMN bagi mahasiswa Akuntansi semester enam.', pg_temp.wib('2026-07-28', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Hendra Gunawan Sutrisno, S.E., M.Ak., CFrA", "institution": "Universitas Surabaya", "country_code": "ID", "role": "speaker", "notes": "Fakultas Bisnis dan Ekonomika Ubaya"}]', p_co_units => '{4}');
select pg_temp.bulk_act(288, 'Short Program Global Supply Chain & Logistics di Chulalongkorn University', 5, 23, 'outbound', '2026-08-03', '2026-08-14', 'offline', 'Chulalongkorn Business School, Bangkok', 'TH', 25, '{9,8,4}', 'Program singkat dua minggu tentang manajemen rantai pasok global, logistik ASEAN, dan kunjungan ke Laem Chabang Port serta pusat distribusi di Bangkok bagi mahasiswa Manajemen.', pg_temp.wib('2026-08-24', '09:00'), 'approved', pg_temp.wib('2026-09-01', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(288, '{D31249692,D31239726,D31229821,D31229027,D31229451}', '{}', '{}');
select pg_temp.bulk_act(289, 'Cultural Exchange Bisnis Keluarga Taiwan bersama National Taiwan University', 5, 29, 'outbound', '2026-08-24', '2026-09-04', 'offline', 'National Taiwan University, Taipei', 'TW', 30, '{4,8,17}', 'Pertukaran budaya dua minggu untuk mempelajari tata kelola dan suksesi bisnis keluarga Taiwan melalui kelas bersama, kunjungan perusahaan keluarga, dan homestay di Taipei.', pg_temp.daysago(12, '09:00'), 'pending', pg_temp.daysago(12, '09:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(289, '{D31239726,D31229027,D31249207,D31249746}', '{}', '{}');
select pg_temp.bulk_act(290, 'Academic Exchange Mahasiswa Universiti Brunei Darussalam di PCU 2026', 5, 28, 'inbound', '2026-08-17', '2026-09-18', 'offline', 'Gedung P PCU', 'ID', 174, '{4,17}', 'Mahasiswa UBD School of Business and Economics mengikuti perkuliahan Bisnis Internasional dan Akuntansi Perpajakan selama lima minggu serta proyek riset kecil tentang investasi Brunei di Jawa Timur.', pg_temp.daysago(6, '09:00'), 'pending', pg_temp.daysago(6, '09:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(290, '{}', '{X05259013}', '{}');
select pg_temp.bulk_act(291, 'Program Imersi Accounting Analytics dan Audit Berbasis Data di Yonsei University', 5, 22, 'outbound', '2026-08-10', '2026-08-21', 'offline', 'Yonsei University Sinchon Campus, Seoul', 'KR', 31, '{4,9}', 'Program imersi dua minggu tentang analitik data akuntansi, audit berbasis data, dan visualisasi keuangan dengan Python dan Power BI di Yonsei School of Business.', pg_temp.daysago(15, '09:00'), 'revision_requested', pg_temp.daysago(9, '09:00'), p_mnote => 'Transkrip nilai dua mahasiswa belum diunggah dan surat keterangan selesai program dari Yonsei University belum ditandatangani. Mohon lengkapi bundel mobilitas lalu ajukan ulang.', p_co_units => '{6}');
select pg_temp.bulk_pset(291, '{D31239549,D31249207,D31259757,D31249746,D31239185}', '{}', '{}');
select pg_temp.bulk_act(292, 'Seminar Nasional Perpajakan Digital dan Coretax Administration System', 6, 10, 'inbound', '2026-09-09', '2026-09-09', 'hybrid', 'Auditorium Gedung W PCU', 'ID', 158, '{16,8,17}', 'Seminar nasional tentang implementasi Coretax DJP, e-Faktur generasi baru, dan dampaknya bagi praktik akuntansi perusahaan, menghadirkan akademisi Ubaya dan praktisi perpajakan korporasi dari PT Sampoerna Strategic Square.', pg_temp.wib('2026-09-18', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Agus Widodo Prasetyo, S.E., M.Ak., BKP", "institution": "Universitas Surabaya", "country_code": "ID", "role": "speaker"}, {"full_name": "Yohanes Setiadi, S.E., M.Ak., BKP", "institution": "PT Sampoerna Strategic Square", "country_code": "ID", "role": "speaker", "notes": "Tax Manager"}]', p_co_units => '{5}');
select pg_temp.bulk_act(293, 'Faculty Exchange Dosen Corporate Finance PCU di Fontys Venlo', 5, 31, 'outbound', '2026-09-14', '2026-09-25', 'offline', 'Fontys Venlo Campus', 'NL', 100, '{4,17}', 'Dua dosen Keuangan Prodi Manajemen mengajar modul Corporate Finance in Emerging Markets di Fontys Venlo dan menjajaki penelitian bersama tentang pembiayaan UKM di Indonesia dan Belanda.', pg_temp.wib('2026-09-29', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Thomas Janssen", "institution": "Fontys University of Applied Sciences", "country_code": "NL", "role": "other", "notes": "Host lecturer Fontys Venlo"}]', p_co_units => '{4}');
select pg_temp.bulk_act(294, 'Riset Bersama Integrated Reporting Perusahaan Keluarga dengan National Taiwan University', 6, 4, 'outbound', '2026-11-02', '2027-01-29', 'hybrid', 'NTU College of Management, Taipei', 'TW', 15, '{12,8,17}', 'Rencana riset bersama tentang penerapan integrated reporting dan pengungkapan keberlanjutan pada perusahaan keluarga tercatat di Bursa Efek Indonesia dan Taiwan Stock Exchange.', null, null, null, p_files => '{ia}', p_co_units => '{4}');
select pg_temp.bulk_act(295, 'Kuliah Tamu Hotel Revenue Management dari KMUTT', 5, 15, 'inbound', '2026-09-30', '2026-09-30', 'online', 'Zoom Meeting', null, 127, '{8,4}', 'Kuliah tamu daring tentang strategi dynamic pricing, forecasting okupansi, dan distribusi kanal online pada industri perhotelan Thailand bagi mahasiswa Manajemen konsentrasi hospitality.', null, null, null, p_ext => '[{"full_name": "Asst. Prof. Dr. Siriporn Chaiyaporn", "institution": "King Mongkut''s University of Technology Thonburi", "country_code": "TH", "role": "speaker"}]', p_co_units => '{4}');

select pg_temp.bulk_verify(271, 295);
