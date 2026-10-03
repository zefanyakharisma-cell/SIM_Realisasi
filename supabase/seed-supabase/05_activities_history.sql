-- seed-supabase/05_activities_history (simks-partnership): 50 more kegiatan (RL-xxxx-0201 … 0250) spanning AY 2024/2025
-- to today, on REAL SIMKS documents, written only into realisasi.*. Idempotent: an activity that exists is skipped.
--
-- * Adds AY 2024/2025 (id 3, semesters 5/6) to the calendar so that year's kegiatan get a period (R-09).
-- * Every kegiatan's dates lie inside its agreement's validity (checked with realisasi.documents_valid_between, R-04).
--   Before 2025-10-17 only document 11 (Kyoto Sangyo University, from 2024-08-15) is valid, so AY 2024/2025 is built
--   on it; later kegiatan spread over UGM, Chulalongkorn, NTU, Yonsei, Amsterdam, NUS, Astra, Unilever, LMU, Ateneo,
--   Sydney and the renewals 33/34.
-- * Mix: mobility and non-mobility Jenis, inbound/outbound, offline/online/hybrid, 25 units across SBM, FTI, FHIK,
--   FTSP, FKIP, Kedokteran, LPPM and KUI, co-units, external speakers/lecturers/researchers, late submissions (R-10),
--   Mobility approvals, two kegiatan approved after a revision round, one revision still open, two in the queue,
--   drafts (one future, one ongoing, one abandoned), a post-freeze edit.
-- * Students are taken from mock_baak with intake years that fit the dates, and no NRP is claimed by two units on
--   overlapping dates (asserted at the end), so no unintended rule 2.1 conflicts appear.
-- * Snapshots: AY 2024/2025 is frozen like the scheduled job would have (2025-03-02, 2025-08-30). A live AY 2025/2026
--   snapshot that now misses seeded kegiatan is superseded by a system re-freeze at its as-of time (+1 s, so the new one is the latest).
-- Actors: submitters akun 3 (unit 4) and akun 4 (unit 5 and its prodi); every other unit's kegiatan was entered by
-- KUI (akun 1, io_admin). Mobility verifiers akun 10 and 11.
-- Ids: activities c5000000-0000-4000-8000-0000000002NN, event groups f5000000-…, codes RL-<year created>-02NN.

insert into realisasi.academic_years (id, label, start_date, end_date) values (3, '2024/2025', '2024-08-01', '2025-07-31')
on conflict (id) do update set label = excluded.label, start_date = excluded.start_date, end_date = excluded.end_date;
insert into realisasi.semesters (id, academic_year_id, term, start_date, end_date, cutoff_date) values
  (5, 3, 'ganjil', '2024-08-01', '2025-01-31', '2025-03-02'),
  (6, 3, 'genap',  '2025-02-01', '2025-07-31', '2025-08-30')
on conflict (id) do update set academic_year_id = excluded.academic_year_id, term = excluded.term,
  start_date = excluded.start_date, end_date = excluded.end_date, cutoff_date = excluded.cutoff_date;
select setval('realisasi.academic_years_id_seq', greatest((select max(id) from realisasi.academic_years), 1));
select setval('realisasi.semesters_id_seq', greatest((select max(id) from realisasi.semesters), 1));

create or replace function pg_temp.h_aid(n int) returns uuid language sql immutable as $$
  select ('c5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.h_gid(n int) returns uuid language sql immutable as $$
  select ('f5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.h_akun(p_akun int) returns uuid language sql stable as $$
  select id from kerjasama.profiles where akun_id = p_akun $$;
create or replace function pg_temp.h_pdf() returns bytea language sql immutable as $$
  select decode('255044462d312e340a312030206f626a0a3c3c2f547970652f436174616c6f672f50616765732032203020523e3e0a656e646f626a0a322030206f626a0a3c3c2f547970652f50616765732f4b6964735b33203020525d2f436f756e7420313e3e0a656e646f626a0a332030206f626a0a3c3c2f547970652f506167652f506172656e742032203020522f4d65646961426f785b30203020323030203230305d2f436f6e74656e74732034203020522f5265736f75726365733c3c3e3e3e3e0a656e646f626a0a342030206f626a0a3c3c2f4c656e67746820303e3e73747265616d0a0a656e6473747265616d0a656e646f626a0a787265660a3020350a303030303030303030302036353533352066200a30303030303030303039203030303030206e200a30303030303030303534203030303030206e200a30303030303030313035203030303030206e200a30303030303030313939203030303030206e200a747261696c65720a3c3c2f53697a6520352f526f6f742031203020523e3e0a7374617274787265660a3234350a2525454f460a', 'hex') $$;
create or replace function pg_temp.h_wib(d date, t time default '09:00') returns timestamptz language sql immutable as $$
  select (d + t) at time zone 'Asia/Jakarta' $$;
create or replace function pg_temp.h_daysago(n int, t time default '09:00') returns timestamptz language sql stable as $$
  select ((realisasi.today() - n) + t) at time zone 'Asia/Jakarta' $$;
create or replace function pg_temp.h_log(p_n int, p_kind text, p_track text, p_action text, p_actor uuid, p_at timestamptz,
                                       p_note text default null, p_diff jsonb default null, p_frozen boolean default false)
returns void language sql as $$
  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (pg_temp.h_aid(p_n), p_kind::realisasi.log_kind, p_track::realisasi.team, p_action, p_actor, p_note, p_diff, p_frozen, p_at) $$;

-- the submitting account for a unit: SBM -> akun 3, Prodi Manajemen and its programs -> akun 4, else KUI (akun 1)
create or replace function pg_temp.h_creator(p_unit int) returns uuid language sql stable as $$
  select pg_temp.h_akun(case when p_unit = 4 then 3
                           when p_unit = 5 or exists (select 1 from kerjasama.units u where u.id = p_unit and u.parent_id = 5) then 4
                           else 1 end) $$;

-- preconditions: accounts seeded, every referenced SIMKS document selectable
do $$
declare d int;
begin
  if pg_temp.h_akun(1) is null or pg_temp.h_akun(3) is null or pg_temp.h_akun(4) is null or pg_temp.h_akun(10) is null
     or pg_temp.h_akun(11) is null then
    raise exception 'run seed-supabase/03_accounts.sql first (account_roles for akun 1, 3, 4, 10, 11)';
  end if;
  foreach d in array array[11, 12, 15, 17, 19, 21, 23, 25, 27, 28, 29, 30, 31, 32, 34, 36, 40, 42, 44, 51, 52] loop
    if not exists (select 1 from kerjasama.documents where id = d and status not in ('in_process', 'rejected') and start_date is not null) then
      raise exception 'SIMKS document % missing or not selectable; adjust supabase/seed-supabase/05_activities_history.sql', d;
    end if;
  end loop;
end $$;

-- One kegiatan with its units, kerja sama, SDGs, external persons, files, participants (mobility) and history.
--   p_mstatus (mobility only): approved | pending | revision_requested; p_msince = when Mobility acted (or submit time)
--   p_rev: an earlier revision round {"note", "at", "resubmit"} before the final p_mstatus
create or replace function pg_temp.h_act(
  p_n int, p_name text, p_unit int, p_agenda int, p_dir text, p_start date, p_end date, p_mode text, p_venue text,
  p_country text, p_doc int, p_sdgs int[], p_desc text, p_submitted timestamptz,
  p_mstatus text default null, p_msince timestamptz default null, p_mnote text default null,
  p_int text[] default '{}', p_inb text[] default '{}', p_staff text[] default '{}',
  p_co int[] default '{}', p_ext jsonb default '[]', p_files text[] default '{ia,ir}', p_rev jsonb default null)
returns void language plpgsql as $$
declare v_id uuid := pg_temp.h_aid(p_n); v_g uuid := pg_temp.h_gid(p_n);
        v_creator uuid := pg_temp.h_creator(p_unit); v_mob boolean := realisasi.agenda_is_mobility(p_agenda);
        v_verifier uuid := pg_temp.h_akun(case when p_n % 2 = 0 then 10 else 11 end);
        v_created timestamptz; v_code text; k text; v_path text; e jsonb; v_ver int := 1; v_pset uuid; v_status text;
begin
  if exists (select 1 from realisasi.activities where id = v_id) then return; end if;
  if v_creator is null then raise exception 'activity %: no account for unit %', p_n, p_unit; end if;
  if not exists (select 1 from kerjasama.units where id = p_unit) then raise exception 'activity %: SIMKS unit % missing', p_n, p_unit; end if;
  if not exists (select 1 from kerjasama.agendas where id = p_agenda) then raise exception 'activity %: SIMKS agenda % missing', p_n, p_agenda; end if;
  if not exists (select 1 from realisasi.documents_valid_between(p_start, p_end) v where v.document_id = p_doc) then
    raise exception 'activity %: SIMKS document % not valid for % – %', p_n, p_doc, p_start, p_end;
  end if;
  if p_submitted is not null and p_end > (p_submitted at time zone 'Asia/Jakarta')::date then
    raise exception 'activity %: submitted before it ended (R-08)', p_n;
  end if;
  if v_mob and p_submitted is not null and (cardinality(p_int) + cardinality(p_inb) = 0 or p_mstatus is null) then
    raise exception 'activity %: a submitted mobility kegiatan needs students and a Mobility status', p_n;
  end if;

  -- drafts were opened a few days before the end date (never in the future); submissions three days before submitting
  v_created := case when p_submitted is not null then p_submitted - interval '3 days'
                    else least(pg_temp.h_wib(p_end) - interval '3 days', pg_temp.h_daysago(2)) end;
  v_code := 'RL-' || to_char(v_created at time zone 'Asia/Jakarta', 'YYYY') || '-' || lpad(p_n::text, 4, '0');

  insert into realisasi.event_groups (id, created_by, created_at) values (v_g, v_creator, v_created) on conflict do nothing;
  insert into realisasi.activities (id, code, name, agenda_id, direction, start_date, end_date, mode, venue, country_code,
              sks_recognized, description, submitter_unit_id, created_by, submitted_at, verified_at,
              mobility_status, mobility_since, event_group_id, created_at, updated_at)
  values (v_id, v_code, p_name, p_agenda, p_dir::realisasi.direction, p_start, p_end, p_mode::realisasi.activity_mode, p_venue,
          p_country, case when v_mob and p_dir = 'outbound' then case when p_end - p_start >= 60 then 20 else 3 end end,
          p_desc, p_unit, v_creator, p_submitted,
          case when p_submitted is not null and (not v_mob or p_mstatus = 'approved')
               then case when v_mob then p_msince else p_submitted end end,
          case when p_submitted is null or not v_mob then 'not_required' else p_mstatus end::realisasi.track_status,
          coalesce(p_msince, p_submitted, v_created), v_g, v_created,
          coalesce(p_msince, p_submitted, v_created));
  insert into realisasi.activity_units (activity_id, unit_id, is_submitter)
  select v_id, p_unit, true union all select v_id, u, false from unnest(p_co) u where u <> p_unit;
  insert into realisasi.activity_documents (activity_id, original_document_id, out_of_scope_warning)
  values (v_id, p_doc, not exists (select 1 from kerjasama.document_scope_units su where su.document_id = p_doc and su.unit_id = p_unit));
  insert into realisasi.activity_sdgs (activity_id, sdg_id) select v_id, s from unnest(p_sdgs) s;
  for e in select * from jsonb_array_elements(p_ext) loop
    insert into realisasi.activity_external_persons (activity_id, full_name, institution, country_code, role, notes)
    values (v_id, e ->> 'full_name', e ->> 'institution', e ->> 'country_code', (e ->> 'role')::realisasi.person_role, e ->> 'notes');
  end loop;
  foreach k in array p_files || case when v_mob and p_submitted is not null then '{mobility_bundle}'::text[] else '{}' end loop
    v_path := case when k = 'mobility_bundle' then 'realisasi-transcripts/' else 'realisasi-files/' end
              || v_id || '/' || k || '/' || md5(v_id::text || k)::uuid || '.pdf';
    insert into realisasi.file_blobs (path, bucket, data, mime, size_bytes, created_by, created_at)
    values (v_path, split_part(v_path, '/', 1), pg_temp.h_pdf(), 'application/pdf', length(pg_temp.h_pdf()), v_creator,
            v_created + interval '1 day')
    on conflict (path) do nothing;
    insert into realisasi.activity_files (activity_id, kind, version, storage_path, filename, size_bytes, mime, is_current, uploaded_by, uploaded_at)
    values (v_id, k::realisasi.file_kind, 1, v_path,
            case when k = 'mobility_bundle' then 'Transkrip_Poster_Dokumentasi_' else upper(k) || '_' end || v_code || '.pdf',
            length(pg_temp.h_pdf()), 'application/pdf', true, v_creator, v_created + interval '1 day');
  end loop;

  -- participants (mobility only): an earlier revised version, then the current one (a draft set for a draft)
  if v_mob and cardinality(p_int) + cardinality(p_inb) + cardinality(p_staff) > 0 then
    for v_ver in 1 .. case when p_rev is not null then 2 else 1 end loop
      v_pset := md5(v_id::text || ':v' || v_ver)::uuid;
      v_status := case when p_submitted is null then 'draft' when p_rev is not null and v_ver = 1 then 'revision_requested' else p_mstatus end;
      insert into realisasi.participant_set_versions (id, activity_id, version, status, submitted_by, submitted_at,
                  reviewed_by, reviewed_at, review_note)
      values (v_pset, v_id, v_ver, v_status::realisasi.pset_status, case when p_submitted is not null then v_creator end,
              case when v_ver = 2 then (p_rev ->> 'resubmit')::timestamptz else p_submitted end,
              case when v_status in ('approved', 'revision_requested') then v_verifier end,
              case when p_rev is not null and v_ver = 1 then (p_rev ->> 'at')::timestamptz
                   when v_status in ('approved', 'revision_requested') then p_msince end,
              case when p_rev is not null and v_ver = 1 then p_rev ->> 'note' when v_status = 'revision_requested' then p_mnote end);
      insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name)
      select v_pset, 'internal', s.nrp, s.full_name, s.faculty_name, s.prodi_name
        from unnest(p_int) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
      insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
                  home_institution, home_student_number, home_country_code)
      select v_pset, 'inbound', s.nrp, s.full_name, s.faculty_name, s.prodi_name, s.home_institution, 'HS-' || right(s.nrp, 4),
             s.home_country_code
        from unnest(p_inb) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
      insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
      select v_pset, e.employee_id, e.full_name, e.unit_name
        from unnest(p_staff) with ordinality x(id, o) join mock_hr.employees e on e.employee_id = x.id order by o;
    end loop;
    if (select count(*) from realisasi.participant_students ps join realisasi.participant_set_versions v on v.id = ps.set_version_id
         where v.activity_id = v_id and v.version = 1) <> cardinality(p_int) + cardinality(p_inb) then
      raise exception 'activity %: an NRP is not in mock_baak.students', p_n;
    end if;
  end if;

  perform pg_temp.h_log(p_n, 'system', null, 'create', v_creator, v_created);
  if p_submitted is null then return; end if;
  perform pg_temp.h_log(p_n, 'system', null, 'submit', v_creator, p_submitted);
  if not v_mob then return; end if;
  if p_rev is not null then
    perform pg_temp.h_log(p_n, 'verification', 'mobility', 'request_revision', v_verifier, (p_rev ->> 'at')::timestamptz, p_rev ->> 'note');
    perform pg_temp.h_log(p_n, 'revision', 'mobility', 'resubmit', v_creator, (p_rev ->> 'resubmit')::timestamptz);
  end if;
  if p_mstatus = 'approved' then
    perform pg_temp.h_log(p_n, 'verification', 'mobility', 'approve', v_verifier, p_msince, null,
                        jsonb_build_object('version', case when p_rev is not null then 2 else 1 end));
  elsif p_mstatus = 'revision_requested' then
    perform pg_temp.h_log(p_n, 'verification', 'mobility', 'request_revision', v_verifier, p_msince, p_mnote);
  end if;
end $$;

-- Mobility Jenis used: 2 Student Exchange, 28 Academic Exchange, 33 Credit Transfer (student_exchange); 17 Double Degree
-- (jd_dd); 22 Immersion, 23 Short Program, 29 Cultural Exchange (short_summer); 21 Magang, 24 Studi Ekskursi
-- (other_mobility). Non-mobility: 4 Joint Research, 15 Kuliah Tamu, 27 Academic Visit, 31 Staf Exchange, 35 Joint
-- Projects, 40 Pengabdian, 69 Pelatihan, 79 Online Course.

-- ==== AY 2024/2025 Ganjil (document 11, Kyoto Sangyo University) ====================================================
select pg_temp.h_act(201, 'Student Exchange Semester Ganjil 2024 di Kyoto Sangyo University', 7, 2, 'outbound',
  '2024-09-02', '2024-12-20', 'offline', 'Kyoto Sangyo University, Kamigamo Campus', 'JP', 11, '{4,17}',
  'Dua mahasiswa International Business Management mengikuti satu semester perkuliahan reguler di Faculty of Business '
  'Administration, Kyoto Sangyo University, dengan pengakuan 20 SKS.',
  pg_temp.h_wib('2025-01-06'), 'approved', pg_temp.h_wib('2025-01-15', '14:00'),
  p_int => '{D31238836,D31239872}');

select pg_temp.h_act(202, 'Kuliah Tamu Japanese Business Culture dari Kyoto Sangyo University', 4, 15, 'inbound',
  '2024-10-14', '2024-10-15', 'hybrid', 'Auditorium Gedung P PCU', 'ID', 11, '{4,8}',
  'Kuliah tamu dua sesi tentang budaya kerja dan etika bisnis Jepang untuk mahasiswa SBM, diikuti 140 peserta luring dan daring.',
  pg_temp.h_wib('2024-10-21'),
  p_ext => '[{"full_name":"Prof. Hiroshi Tanaka","institution":"Kyoto Sangyo University","country_code":"JP","role":"visiting_lecturer"}]');

select pg_temp.h_act(203, 'Riset Bersama Pariwisata Berkelanjutan Kyoto–Surabaya', 8, 4, 'outbound',
  '2024-09-16', '2025-01-31', 'online', 'Zoom Meeting', null, 11, '{8,11}',
  'Penelitian komparatif praktik pariwisata berkelanjutan di Kyoto dan Surabaya; luaran berupa naskah artikel bersama.',
  pg_temp.h_wib('2025-02-10'), p_co => '{4}',
  p_ext => '[{"full_name":"Dr. Yuki Nakamura","institution":"Kyoto Sangyo University","country_code":"JP","role":"researcher"}]');

select pg_temp.h_act(204, 'Cultural Exchange Japan–Indonesia Youth Festival di Kyoto', 63, 29, 'outbound',
  '2024-11-11', '2024-11-22', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{4,10,17}',
  'Mahasiswa DKV menampilkan karya ilustrasi bertema budaya Nusantara dan mengikuti lokakarya desain tradisional Jepang.',
  pg_temp.h_wib('2024-11-29'), 'approved', pg_temp.h_wib('2024-12-09', '14:00'),
  p_int => '{C21233005,C21233140}', p_staff => '{PG452412}', p_co => '{32}');

select pg_temp.h_act(205, 'Staff Exchange Pengembangan Kurikulum Akuntansi ke Kyoto Sangyo University', 6, 31, 'outbound',
  '2024-12-02', '2024-12-06', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{4,17}',
  'Dua dosen Prodi Akuntansi melakukan benchmarking kurikulum dan diskusi rencana kelas bersama (COIL) dengan mitra.',
  pg_temp.h_wib('2024-12-16'));

select pg_temp.h_act(206, 'Webinar Internasional Ekonomi Digital Asia Timur', 5, 35, 'inbound',
  '2025-01-22', '2025-01-22', 'online', 'Zoom Meeting', null, 11, '{8,9}',
  'Webinar terbuka dengan pembicara dari Kyoto Sangyo University tentang transformasi digital UMKM di Jepang dan Indonesia.',
  pg_temp.h_wib('2025-01-27'),
  p_ext => '[{"full_name":"Assoc. Prof. Kenta Yoshida","institution":"Kyoto Sangyo University","country_code":"JP","role":"speaker"},{"full_name":"Dr. Mei Okabe","institution":"Kyoto Sangyo University","country_code":"JP","role":"speaker"}]');

-- ==== AY 2024/2025 Genap ============================================================================================
-- approved after one revision round
select pg_temp.h_act(207, 'Short Program Spring Japanese Language and Culture di Kyoto Sangyo University', 4, 23, 'outbound',
  '2025-03-03', '2025-03-21', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{4}',
  'Program tiga minggu bahasa dan budaya Jepang (level dasar) bagi mahasiswa SBM, termasuk kunjungan industri di Kansai.',
  pg_temp.h_wib('2025-03-27'), 'approved', pg_temp.h_wib('2025-04-10', '14:00'),
  p_int => '{D31245931,D31246584,D32237864}',
  p_rev => jsonb_build_object('note', 'Poster dan transkrip satu peserta (D32237864) belum ada di PDF; mohon unggah ulang.',
                              'at', pg_temp.h_wib('2025-04-02', '10:00'), 'resubmit', pg_temp.h_wib('2025-04-07', '15:00')));

select pg_temp.h_act(208, 'Riset Bersama Smart Manufacturing dengan Kyoto Sangyo University', 67, 4, 'inbound',
  '2025-02-10', '2025-06-27', 'hybrid', 'Lab Sistem Produksi PCU', 'ID', 11, '{9,12}',
  'Riset penjadwalan produksi berbasis IoT untuk UKM manufaktur; peneliti mitra berkunjung dua minggu ke PCU.',
  pg_temp.h_wib('2025-07-08'), p_co => '{28}',
  p_ext => '[{"full_name":"Dr. Takeshi Mori","institution":"Kyoto Sangyo University","country_code":"JP","role":"researcher"}]');

select pg_temp.h_act(209, 'Magang Internasional Pengembangan Perangkat Lunak di Kyoto', 68, 21, 'outbound',
  '2025-06-02', '2025-07-25', 'offline', 'Kyoto Sangyo University, Faculty of Information Science and Engineering', 'JP', 11, '{4,8,9}',
  'Tiga mahasiswa Informatika magang delapan minggu di laboratorium riset mitra dengan pembimbing dosen PCU.',
  pg_temp.h_wib('2025-08-01'), 'approved', pg_temp.h_wib('2025-08-12', '14:00'),
  p_int => '{B11227366,B11234310,B11235580}', p_staff => '{PG564518}');

-- late submission (deadline 2025-08-24), verified on submit
select pg_temp.h_act(210, 'Service Learning Desa Wisata bersama Mahasiswa Kyoto Sangyo University', 20, 40, 'outbound',
  '2025-07-14', '2025-07-25', 'offline', 'Desa Wisata Tulungrejo, Kota Batu', 'ID', 11, '{1,4,11}',
  'Pengabdian bersama mahasiswa PCU dan mitra: pendampingan homestay, pemetaan potensi wisata, dan pelatihan bahasa Inggris.',
  pg_temp.h_wib('2025-08-26', '16:00'));

select pg_temp.h_act(211, 'Guest Lecture Arsitektur Kayu Tradisional Jepang', 54, 15, 'inbound',
  '2025-04-21', '2025-04-24', 'offline', 'Gedung P PCU', 'ID', 11, '{9,11}',
  'Rangkaian kuliah tamu dan studio singkat tentang sambungan kayu tradisional Jepang dan relevansinya bagi rumah tropis.',
  pg_temp.h_wib('2025-05-02'),
  p_ext => '[{"full_name":"Assoc. Prof. Kenji Morimoto","institution":"Kyoto Sangyo University","country_code":"JP","role":"visiting_lecturer"}]');

select pg_temp.h_act(212, 'Credit Transfer Semester Genap di Kyoto Sangyo University', 7, 33, 'outbound',
  '2025-04-07', '2025-07-18', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{4}',
  'Program transfer kredit satu semester; mata kuliah mitra diakui penuh dalam kurikulum International Business Management.',
  pg_temp.h_wib('2025-07-24'), 'approved', pg_temp.h_wib('2025-08-05', '14:00'),
  p_int => '{D31242651,D32233592}');

-- verified; IO Admin corrected the venue after the Genap freeze (post-freeze edit)
select pg_temp.h_act(213, 'Asia-Pacific Hospitality Forum 2025', 8, 35, 'inbound',
  '2025-05-15', '2025-05-16', 'hybrid', 'Auditorium Gedung W PCU', 'ID', 11, '{8,17}',
  'Forum tahunan program Hotel Management dengan pembicara mitra, sesi panel industri, dan kompetisi studi kasus mahasiswa.',
  pg_temp.h_wib('2025-05-22'),
  p_ext => '[{"full_name":"Prof. Aiko Fujimoto","institution":"Kyoto Sangyo University","country_code":"JP","role":"speaker"}]');
select pg_temp.h_log(213, 'update', null, 'edit', pg_temp.h_akun(1), pg_temp.h_wib('2025-09-10', '10:30'),
  'Koreksi lokasi sesuai laporan akhir.', '{"venue": ["Auditorium PCU", "Auditorium Gedung W PCU"]}', true)
 where not exists (select 1 from realisasi.activity_log where activity_id = pg_temp.h_aid(213) and action = 'edit');

-- abandoned draft (only IA uploaded), long past its reporting deadline
select pg_temp.h_act(214, 'Workshop Penulisan Akademik bersama Kyoto Sangyo University', 61, 35, 'inbound',
  '2025-06-10', '2025-06-11', 'online', 'Zoom Meeting', null, 11, '{4}',
  'Lokakarya penulisan artikel jurnal berbahasa Inggris untuk dosen dan mahasiswa pascasarjana.',
  null, p_files => '{ia}');

-- late: reported after the Genap 2024/2025 freeze (late addition)
select pg_temp.h_act(215, 'Riset Bersama Bahasa dan Identitas Diaspora Asia', 61, 4, 'outbound',
  '2025-05-05', '2025-07-31', 'online', 'Zoom Meeting', null, 11, '{4,10}',
  'Penelitian sosiolinguistik tentang penggunaan bahasa pada komunitas diaspora Indonesia di Jepang.',
  pg_temp.h_wib('2025-09-15', '11:00'), p_co => '{32}');

-- ==== AY 2025/2026 Ganjil ===========================================================================================
select pg_temp.h_act(216, 'Inbound Exchange Semester Ganjil 2025 dari Jepang', 4, 2, 'inbound',
  '2025-09-01', '2025-12-19', 'offline', 'Kampus PCU Siwalankerto', 'ID', 11, '{4,17}',
  'Tiga mahasiswa pertukaran dari Jepang mengikuti satu semester perkuliahan berbahasa Inggris di SBM.',
  pg_temp.h_wib('2026-01-05'), 'approved', pg_temp.h_wib('2026-01-12', '14:00'),
  p_inb => '{X01250003,X01250017,X01250024}');

select pg_temp.h_act(217, 'Kuliah Tamu Indonesian Economic Outlook bersama UGM', 6, 15, 'inbound',
  '2025-10-27', '2025-10-27', 'offline', 'Auditorium PCU', 'ID', 28, '{8}',
  'Kuliah umum prospek ekonomi Indonesia 2026 dan implikasinya bagi profesi akuntan.',
  pg_temp.h_wib('2025-11-03'),
  p_ext => '[{"full_name":"Dr. Ardi Nugroho, M.Sc.","institution":"Universitas Gadjah Mada","country_code":"ID","role":"speaker"}]');

select pg_temp.h_act(218, 'Student Exchange Yonsei University Semester Fall 2025', 5, 2, 'outbound',
  '2025-10-20', '2026-01-16', 'offline', 'Yonsei University, Sinchon Campus', 'KR', 31, '{4}',
  'Pertukaran mahasiswa Prodi Manajemen pada program Fall Semester (kedatangan tertunda karena visa).',
  pg_temp.h_wib('2026-01-22'), 'approved', pg_temp.h_wib('2026-02-02', '14:00'),
  p_int => '{D31240187,D31243593}');

select pg_temp.h_act(219, 'Riset Bersama Perilaku Konsumen Berkelanjutan dengan University of Amsterdam', 42, 4, 'outbound',
  '2025-11-03', '2026-01-30', 'online', 'Microsoft Teams', null, 32, '{8,12}',
  'Survei lintas negara (Indonesia–Belanda) tentang preferensi produk ramah lingkungan pada generasi Z.',
  pg_temp.h_wib('2026-02-09'),
  p_ext => '[{"full_name":"Dr. Femke van Dijk","institution":"University of Amsterdam","country_code":"NL","role":"researcher"}]');

select pg_temp.h_act(220, 'Thai Hospitality Immersion di Chulalongkorn University', 8, 22, 'outbound',
  '2025-12-01', '2025-12-12', 'offline', 'Chulalongkorn University, Bangkok', 'TH', 29, '{4,8}',
  'Program imersi dua minggu: kelas manajemen hospitaliti, kunjungan hotel, dan proyek kelompok bersama mahasiswa Thailand.',
  pg_temp.h_wib('2025-12-18'), 'approved', pg_temp.h_wib('2026-01-07', '14:00'),
  p_int => '{D32237864,D31246584}');

select pg_temp.h_act(221, 'Magang Industri Lean Manufacturing di PT Astra International', 67, 21, 'outbound',
  '2025-12-08', '2026-01-30', 'offline', 'PT Astra International Tbk, Sunter Jakarta', 'ID', 12, '{8,9}',
  'Tiga mahasiswa Teknik Industri magang delapan minggu di lini produksi dengan proyek perbaikan berbasis lean.',
  pg_temp.h_wib('2026-02-05'), 'approved', pg_temp.h_wib('2026-02-12', '14:00'),
  p_int => '{B11235901,B11237182,B11238623}', p_staff => '{PG488192}');

select pg_temp.h_act(222, 'Academic Visit Fakultas Teknologi Industri ke National Taiwan University', 28, 27, 'outbound',
  '2025-11-17', '2025-11-21', 'offline', 'National Taiwan University, Taipei', 'TW', 30, '{4,9,17}',
  'Kunjungan pimpinan FTI untuk menjajaki program gelar ganda dan riset bersama bidang AI dan sistem manufaktur.',
  pg_temp.h_wib('2025-11-28'), p_co => '{65,67,68}');

select pg_temp.h_act(223, 'Webinar K-Culture and Creative Economy bersama Yonsei University', 57, 35, 'inbound',
  '2025-12-10', '2025-12-10', 'online', 'Zoom Meeting', null, 31, '{8,17}',
  'Webinar tentang strategi komunikasi industri kreatif Korea untuk mahasiswa Ilmu Komunikasi dan DKV.',
  pg_temp.h_wib('2025-12-15'), p_co => '{63}',
  p_ext => '[{"full_name":"Prof. Lee Ji-hoon","institution":"Yonsei University","country_code":"KR","role":"speaker"}]');

select pg_temp.h_act(224, 'Pengabdian Masyarakat Literasi Digital UMKM bersama UGM', 20, 40, 'outbound',
  '2026-01-12', '2026-01-23', 'offline', 'Kabupaten Gunungkidul, DIY', 'ID', 28, '{1,4,8}',
  'Pendampingan pemasaran digital dan pencatatan keuangan sederhana bagi 40 pelaku UMKM bersama tim UGM.',
  pg_temp.h_wib('2026-01-29'), p_co => '{4}');

-- ==== AY 2025/2026 Genap ============================================================================================
select pg_temp.h_act(225, 'Double Degree Magister Manajemen dengan National Taiwan University', 48, 17, 'outbound',
  '2026-02-23', '2026-07-17', 'offline', 'National Taiwan University, Taipei', 'TW', 15, '{4,17}',
  'Mahasiswa Magister Manajemen menempuh semester kedua program gelar ganda di NTU College of Management.',
  pg_temp.h_wib('2026-07-23'), 'approved', pg_temp.h_wib('2026-07-31', '14:00'),
  p_int => '{H71235980}');

select pg_temp.h_act(226, 'Seminar Internasional Sustainable Supply Chain bersama Unilever Indonesia', 67, 35, 'inbound',
  '2026-03-11', '2026-03-12', 'offline', 'Auditorium PCU', 'ID', 21, '{9,12}',
  'Seminar dan lokakarya rantai pasok berkelanjutan dengan praktisi industri; 210 peserta dari 12 perguruan tinggi.',
  pg_temp.h_wib('2026-03-17'), p_co => '{4}',
  p_ext => '[{"full_name":"Ir. Ratna Kusumawati, M.B.A.","institution":"PT Unilever Indonesia Tbk","country_code":"ID","role":"speaker"}]');

select pg_temp.h_act(227, 'Riset Bersama Urban Heat Island Surabaya dengan University of Amsterdam', 35, 4, 'inbound',
  '2026-03-02', '2026-06-26', 'hybrid', 'Lab Lingkungan Binaan PCU', 'ID', 17, '{11,13}',
  'Pengukuran suhu permukaan kota dan simulasi desain ruang terbuka hijau; peneliti mitra berkunjung tiga minggu.',
  pg_temp.h_wib('2026-07-06'), p_co => '{54,55}',
  p_ext => '[{"full_name":"Dr. Sanne Bakker","institution":"University of Amsterdam","country_code":"NL","role":"researcher"}]');

select pg_temp.h_act(228, 'Student Exchange Semester Genap di National University of Singapore', 68, 2, 'outbound',
  '2026-02-23', '2026-05-08', 'offline', 'National University of Singapore, School of Computing', 'SG', 19, '{4,9}',
  'Dua mahasiswa Informatika mengikuti perkuliahan reguler di School of Computing NUS.',
  pg_temp.h_wib('2026-05-15'), 'approved', pg_temp.h_wib('2026-05-25', '14:00'),
  p_int => '{B11240422,B11244167}');

select pg_temp.h_act(229, 'Kuliah Tamu Precision Medicine dari National University of Singapore', 76, 15, 'inbound',
  '2026-04-08', '2026-04-09', 'hybrid', 'Gedung Fakultas Kedokteran PCU', 'ID', 19, '{3}',
  'Kuliah tamu kedokteran presisi dan genomik klinis bagi mahasiswa dan dosen Fakultas Kedokteran.',
  pg_temp.h_wib('2026-04-15'),
  p_ext => '[{"full_name":"Assoc. Prof. Tan Wei Ming","institution":"National University of Singapore","country_code":"SG","role":"visiting_lecturer"}]');

select pg_temp.h_act(230, 'Studi Ekskursi Arsitektur Kyoto dan Osaka', 54, 24, 'outbound',
  '2026-03-16', '2026-03-27', 'offline', 'Kyoto Sangyo University', 'JP', 27, '{11}',
  'Studi lapangan arsitektur kontemporer dan konservasi kawasan bersejarah di Kyoto dan Osaka.',
  pg_temp.h_wib('2026-04-01'), 'approved', pg_temp.h_wib('2026-04-09', '14:00'),
  p_int => '{A12223059}');

-- approved after one revision round
select pg_temp.h_act(231, 'Bangkok Summer Business Camp di Chulalongkorn University', 7, 23, 'outbound',
  '2026-06-29', '2026-07-10', 'offline', 'Chulalongkorn University, Sasin School of Management', 'TH', 25, '{4,8}',
  'Program musim panas dua minggu: kelas kewirausahaan ASEAN, kunjungan perusahaan, dan pitching proyek lintas negara.',
  pg_temp.h_wib('2026-07-15'), 'approved', pg_temp.h_wib('2026-07-30', '14:00'),
  p_int => '{D31240187,D31239872}',
  p_rev => jsonb_build_object('note', 'Transkrip peserta D31240187 belum ditandatangani mitra; mohon unggah ulang PDF.',
                              'at', pg_temp.h_wib('2026-07-21', '10:00'), 'resubmit', pg_temp.h_wib('2026-07-27', '13:00')));

select pg_temp.h_act(232, 'Pelatihan Sertifikasi K3 Kelistrikan bersama PT Astra International', 65, 69, 'inbound',
  '2026-05-18', '2026-05-20', 'offline', 'Lab Teknik Elektro PCU', 'ID', 23, '{8,9}',
  'Pelatihan dan uji sertifikasi K3 kelistrikan untuk mahasiswa tingkat akhir Teknik Elektro.',
  pg_temp.h_wib('2026-05-26'),
  p_ext => '[{"full_name":"Bambang Hartono, S.T.","institution":"PT Astra International Tbk","country_code":"ID","role":"other","notes":"Instruktur bersertifikat K3"}]');

select pg_temp.h_act(233, 'Visiting Researcher Akuntansi Forensik dari Chulalongkorn University', 6, 4, 'inbound',
  '2026-04-20', '2026-05-29', 'offline', 'Gedung P PCU', 'ID', 25, '{8,16}',
  'Peneliti mitra berkunjung enam minggu untuk riset deteksi kecurangan laporan keuangan di ASEAN.',
  pg_temp.h_wib('2026-06-05'), p_co => '{40}',
  p_ext => '[{"full_name":"Dr. Siriporn Wattanakul","institution":"Chulalongkorn University","country_code":"TH","role":"researcher"}]');

select pg_temp.h_act(234, 'Online Course Bahasa Jepang untuk Bisnis bersama Kyoto Sangyo University', 61, 79, 'inbound',
  '2026-02-16', '2026-05-29', 'online', 'Zoom Meeting', null, 27, '{4}',
  'Kursus daring 14 pertemuan bahasa Jepang bisnis yang diajar dosen mitra untuk mahasiswa lintas prodi.',
  pg_temp.h_wib('2026-06-08'), p_co => '{4}');

-- late: reported after the Genap 2025/2026 freeze (deadline 2026-07-26)
select pg_temp.h_act(235, 'Pengabdian Masyarakat Sanitasi Air Bersih bersama UGM', 55, 40, 'outbound',
  '2026-06-15', '2026-06-26', 'offline', 'Desa Ngargoyoso, Karanganyar', 'ID', 28, '{6,11}',
  'Pembangunan dan pelatihan perawatan sistem penyaringan air bersih skala desa bersama tim UGM.',
  pg_temp.h_wib('2026-09-02', '10:00'), p_co => '{20}');

-- ==== AY 2026/2027 Ganjil (to today) ================================================================================
-- ongoing semester exchange: draft, participants being prepared
select pg_temp.h_act(236, 'Inbound Exchange Yonsei University Semester Fall 2026', 5, 2, 'inbound',
  '2026-08-17', '2026-12-18', 'offline', 'Kampus PCU Siwalankerto', 'ID', 31, '{4,17}',
  'Mahasiswa pertukaran dari Korea mengikuti satu semester di Prodi Manajemen (kegiatan masih berjalan).',
  null, p_inb => '{X02260008,X02260015}', p_files => '{ia}');

select pg_temp.h_act(237, 'Kuliah Tamu Generative AI in Business dari National Taiwan University', 49, 15, 'inbound',
  '2026-09-28', '2026-09-29', 'hybrid', 'Gedung P PCU', 'ID', 52, '{4,9}',
  'Kuliah tamu pemanfaatan AI generatif dalam transformasi model bisnis untuk program Digital Business Transformation.',
  pg_temp.h_daysago(2, '10:00'),
  p_ext => '[{"full_name":"Prof. Lin Chia-Wei","institution":"National Taiwan University","country_code":"TW","role":"visiting_lecturer"}]');

-- in the Mobility queue
select pg_temp.h_act(238, 'Short Program Singapore Smart City di National University of Singapore', 28, 23, 'outbound',
  '2026-08-31', '2026-09-11', 'offline', 'National University of Singapore', 'SG', 36, '{9,11}',
  'Program singkat dua minggu tentang perencanaan kota cerdas, termasuk kunjungan ke Urban Redevelopment Authority.',
  pg_temp.h_daysago(12), 'pending', pg_temp.h_daysago(12),
  p_int => '{B11252003,B11256252,B11257273}', p_staff => '{PG190875}', p_co => '{68}');

select pg_temp.h_act(239, 'Riset Bersama Circular Economy Accounting dengan LMU Munich', 6, 4, 'outbound',
  '2026-09-01', '2026-09-25', 'online', 'Zoom Meeting', null, 42, '{12}',
  'Tahap awal riset pelaporan ekonomi sirkular: penyusunan instrumen dan pengumpulan data perusahaan terbuka.',
  pg_temp.h_daysago(5),
  p_ext => '[{"full_name":"Prof. Dr. Katharina Weber","institution":"Ludwig Maximilian University of Munich","country_code":"DE","role":"researcher"}]');

-- on the Chulalongkorn renewal (34, successor of 29)
select pg_temp.h_act(240, 'Joint Seminar Southeast Asian Hospitality Trends', 8, 35, 'inbound',
  '2026-09-24', '2026-09-25', 'offline', 'Auditorium PCU', 'ID', 34, '{8}',
  'Seminar bersama tentang tren hospitaliti pascapandemi dan pariwisata berkelanjutan di Asia Tenggara.',
  pg_temp.h_daysago(3),
  p_ext => '[{"full_name":"Asst. Prof. Nattaya Chaiyaporn","institution":"Chulalongkorn University","country_code":"TH","role":"speaker"}]');

select pg_temp.h_act(241, 'Guest Lecture Pendidikan Inklusif dari Ateneo de Manila University', 73, 15, 'inbound',
  '2026-09-08', '2026-09-09', 'online', 'Zoom Meeting', null, 44, '{4,10}',
  'Kuliah tamu praktik pendidikan inklusif di sekolah dasar Filipina bagi mahasiswa PGSD.',
  pg_temp.h_daysago(20), p_co => '{36}',
  p_ext => '[{"full_name":"Dr. Maria Isabel Reyes","institution":"Ateneo de Manila University","country_code":"PH","role":"visiting_lecturer"}]');

-- Mobility asked for a revision three days ago
select pg_temp.h_act(242, 'Academic Exchange Program Keguruan di Ateneo de Manila University', 36, 28, 'outbound',
  '2026-08-31', '2026-09-25', 'offline', 'Ateneo de Manila University, Quezon City', 'PH', 44, '{4}',
  'Mahasiswa PGSD mengikuti program pertukaran akademik empat minggu termasuk praktik mengajar di sekolah mitra.',
  pg_temp.h_daysago(6), 'revision_requested', pg_temp.h_daysago(3, '11:00'),
  p_mnote => 'Mohon unggah ulang PDF: dokumentasi kegiatan belum lengkap dan transkrip belum ada.',
  p_int => '{F51245128}', p_co => '{73}');

select pg_temp.h_act(243, 'Magang Industri Otomasi Kelistrikan di PT Astra International', 65, 21, 'outbound',
  '2026-08-03', '2026-09-25', 'offline', 'PT Astra International Tbk, Cikarang', 'ID', 23, '{8,9}',
  'Dua mahasiswa Teknik Elektro magang di divisi otomasi pabrik dengan proyek pemeliharaan prediktif.',
  pg_temp.h_daysago(7), 'approved', pg_temp.h_daysago(1, '14:00'),
  p_int => '{B12222426,B12223137}', p_staff => '{PG413450}');

select pg_temp.h_act(244, 'Pengabdian Masyarakat Kampung Tangguh Bencana bersama UGM', 20, 40, 'outbound',
  '2026-09-07', '2026-09-18', 'offline', 'Kabupaten Lumajang, Jawa Timur', 'ID', 40, '{11,13}',
  'Pelatihan mitigasi erupsi dan pemetaan jalur evakuasi partisipatif di tiga desa lereng Semeru.',
  pg_temp.h_daysago(8), p_co => '{35}');

select pg_temp.h_act(245, 'Workshop Design Thinking bersama University of Sydney', 63, 35, 'inbound',
  '2026-09-29', '2026-09-30', 'hybrid', 'Gedung P PCU', 'ID', 51, '{4,9}',
  'Lokakarya dua hari design thinking untuk mahasiswa DKV dan Desain Interior dengan fasilitator mitra.',
  pg_temp.h_daysago(1, '15:30'), p_co => '{59}',
  p_ext => '[{"full_name":"Dr. Olivia Grant","institution":"University of Sydney","country_code":"AU","role":"speaker"}]');

select pg_temp.h_act(246, 'Riset Bersama Water-Sensitive Urban Design Tahap II dengan University of Amsterdam', 54, 4, 'outbound',
  '2026-08-10', '2026-09-30', 'online', 'Microsoft Teams', null, 17, '{6,11}',
  'Lanjutan riset desain kota peka air: validasi model genangan dan lokakarya bersama pemangku kepentingan.',
  pg_temp.h_daysago(0, '08:30'), p_co => '{35}');

select pg_temp.h_act(247, 'Staff Exchange Pengelolaan Kantor Internasional ke National University of Singapore', 2, 31, 'outbound',
  '2026-09-14', '2026-09-18', 'offline', 'National University of Singapore, Global Relations Office', 'SG', 36, '{17}',
  'Staf KUI mempelajari tata kelola mobilitas mahasiswa dan sistem pelaporan kerja sama di kantor internasional mitra.',
  pg_temp.h_daysago(9));

-- in the Mobility queue
select pg_temp.h_act(248, 'Inbound Exchange Bisnis Asia Tenggara 2026', 4, 2, 'inbound',
  '2026-08-10', '2026-09-25', 'offline', 'Kampus PCU Siwalankerto', 'ID', 25, '{4,10}',
  'Mahasiswa pertukaran dari Thailand mengikuti modul bisnis Asia Tenggara selama tujuh minggu di SBM.',
  pg_temp.h_daysago(4), 'pending', pg_temp.h_daysago(4),
  p_inb => '{X01260068}');

-- future kegiatan: draft without files yet
select pg_temp.h_act(249, 'Kuliah Tamu Medical Education Innovation dari NUS', 76, 15, 'inbound',
  '2026-10-12', '2026-10-13', 'online', 'Zoom Meeting', null, 19, '{3,4}',
  'Kuliah tamu inovasi pendidikan kedokteran berbasis simulasi (direncanakan).',
  null, p_files => '{}');

select pg_temp.h_act(250, 'Academic Visit Delegasi LMU Munich ke PCU', 28, 27, 'inbound',
  '2026-09-21', '2026-09-22', 'offline', 'Gedung T PCU', 'ID', 42, '{4,17}',
  'Kunjungan delegasi LMU untuk menindaklanjuti MoA: presentasi program, kunjungan laboratorium, dan diskusi pertukaran staf.',
  pg_temp.h_daysago(10), p_co => '{2}',
  p_ext => '[{"full_name":"Dr. Markus Hoffmann","institution":"Ludwig Maximilian University of Munich","country_code":"DE","role":"staff_visitor"},{"full_name":"Julia Becker, M.A.","institution":"Ludwig Maximilian University of Munich","country_code":"DE","role":"staff_visitor"}]');

select setval('realisasi.activity_code_seq', greatest(250, (select last_value from realisasi.activity_code_seq)));

-- No NRP claimed by two units on overlapping dates through these kegiatan (rule 2.1 would open a conflict)
do $$
declare v text;
begin
  select string_agg(distinct x.nrp || ' (' || a.code || ' / ' || o.code || ')', ', ') into v
    from realisasi.activities a
    join realisasi.activities o on o.id <> a.id and o.status <> 'draft' and o.submitter_unit_id <> a.submitter_unit_id
                               and o.start_date <= a.end_date and a.start_date <= o.end_date
    cross join lateral (select realisasi._claimed_nrps(a.id) as nrp) x
   where a.id between pg_temp.h_aid(201) and pg_temp.h_aid(250) and a.status <> 'draft'
     and x.nrp in (select realisasi._claimed_nrps(o.id));
  if v is not null then raise exception 'seeded kegiatan claim students of another unit on overlapping dates: %', v; end if;
end $$;

-- Snapshots ---------------------------------------------------------------------------------------------------------
-- AY 2024/2025 frozen like the scheduled job would have (system caller: frozen_by null)
select realisasi.freeze_snapshot(3, 'ganjil_ytd', '2025-03-02 01:00+07')
 where not exists (select 1 from realisasi.kpi_snapshots where academic_year_id = 3 and kind = 'ganjil_ytd' and superseded_by is null);
select realisasi.freeze_snapshot(3, 'genap_full_year', '2025-08-30 01:00+07')
 where not exists (select 1 from realisasi.kpi_snapshots where academic_year_id = 3 and kind = 'genap_full_year' and superseded_by is null);

-- A live system snapshot of a LATER period that was frozen before this history existed no longer matches what the
-- scheduled job would have frozen (missing kegiatan, different late-addition baseline): supersede it with a system
-- re-freeze at its as-of time (+1 s so _prev_snapshot picks it over the superseded one). Idempotent: after the re-freeze the item sets match. (On a fresh deploy 90_freeze
-- runs after this file, so nothing is stale here.)
do $$
declare s realisasi.kpi_snapshots;
begin
  for s in select k.* from realisasi.kpi_snapshots k
            where k.superseded_by is null and k.frozen_by is null and k.academic_year_id <> 3
            order by k.frozen_at
  loop
    if exists ((select distinct i.kpi_code, i.bucket, i.ref_type, i.ref_id
                  from realisasi.kpi_items(s.window_start, s.window_end, s.cutoff_date, s.academic_year_id, s.frozen_at, null) i
                except
                select i.kpi_code, i.bucket, i.ref_type, i.ref_id from realisasi.kpi_snapshot_items i where i.snapshot_id = s.id)
               union all
               (select i.kpi_code, i.bucket, i.ref_type, i.ref_id from realisasi.kpi_snapshot_items i where i.snapshot_id = s.id
                except
                select distinct i.kpi_code, i.bucket, i.ref_type, i.ref_id
                  from realisasi.kpi_items(s.window_start, s.window_end, s.cutoff_date, s.academic_year_id, s.frozen_at, null) i)) then
      perform realisasi._freeze(s.academic_year_id, s.kind, s.frozen_at + interval '1 second', null,
                                'Data historis kegiatan 2024–2026 ditambahkan (seed).', s.id);
    end if;
  end loop;
end $$;

-- Date the seeded freezes' notifications (and outbox rows) at the snapshot's frozen_at and mark them read for io_admin,
-- as 90_freeze does, so the bell shows one notification per snapshot.
update realisasi.notifications n
   set created_at = k.frozen_at,
       read_at = case when p.app_role = 'io_admin' then k.frozen_at + interval '1 day' end
  from realisasi.kpi_snapshots k, kerjasama.profiles p
 where n.kind = 'snapshot_frozen' and n.link = '/realisasi/laporan?report=arsip&snapshot=' || k.id
   and p.id = n.recipient_id and k.frozen_by is null and n.created_at is distinct from k.frozen_at;
update realisasi.email_outbox o set created_at = k.frozen_at
  from realisasi.kpi_snapshots k
 where k.frozen_by is null and o.body like '%/realisasi/laporan?report=arsip&snapshot=' || k.id
   and o.created_at is distinct from k.frozen_at;
