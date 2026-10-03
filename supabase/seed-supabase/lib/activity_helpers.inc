-- seed-supabase/lib/activity_helpers.inc: session-local (pg_temp) helpers shared by 05_activities_history,
-- 06_participants and 07_activities_more. Included with \ir; defines functions only, writes nothing.
--   h_act       one kegiatan with units, kerja sama, SDGs, external persons, files, participants and history
--   h_fill      add students (by prodi / partner, never across units on overlapping dates) up to a target size
--   h_assert_no_conflicts, h_refreeze_stale, h_date_freeze_notifications   checks and snapshot upkeep
-- Re-including is harmless (create or replace). No temp tables: a temp table that outlives its transaction stalls
-- Supabase's SQL API connection, so lookup data lives in functions.

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

-- which prodi a unit's outbound students come from (nearest mapped unit up the tree; a faculty takes all its prodi)
create or replace function pg_temp.h_unit_prodi() returns table(unit_id int, prodi text) language sql immutable as $$
  select * from (values
  (4, 'Manajemen'), (4, 'Akuntansi'), (4, 'International Business Management'), (4, 'Hotel Management'),
  (5, 'Manajemen'), (6, 'Akuntansi'), (7, 'International Business Management'), (8, 'Hotel Management'),
  (48, 'Magister Manajemen'), (51, 'Magister Manajemen'),
  (28, 'Informatika'), (28, 'Teknik Elektro'), (28, 'Teknik Industri'),
  (65, 'Teknik Elektro'), (67, 'Teknik Industri'), (68, 'Informatika'),
  (32, 'Desain Komunikasi Visual'), (32, 'Sastra Inggris'), (32, 'Ilmu Komunikasi'),
  (57, 'Ilmu Komunikasi'), (61, 'Sastra Inggris'), (63, 'Desain Komunikasi Visual'),
  (35, 'Arsitektur'), (35, 'Teknik Sipil'), (54, 'Arsitektur'), (55, 'Teknik Sipil'),
  (36, 'Pendidikan Guru Sekolah Dasar'), (73, 'Pendidikan Guru Sekolah Dasar'),
  (30, 'Kedokteran'), (76, 'Kedokteran'),
  (28, 'Teknik Mesin'), (69, 'Teknik Mesin'), (59, 'Desain Interior'), (60, 'Desain Interior'), (62, 'Desain Komunikasi Visual'),
  (58, 'Bahasa Mandarin'), (34, 'Kedokteran Gigi'), (74, 'Kedokteran Gigi'), (29, 'Magister Manajemen')) v(unit_id, prodi) $$;

create or replace function pg_temp.h_prodi_of(p_unit int) returns text[] language sql stable as $$
  with recursive up(id, parent_id, depth) as (
    select u.id, u.parent_id, 0 from kerjasama.units u where u.id = p_unit
    union all select u.id, u.parent_id, up.depth + 1 from kerjasama.units u join up on u.id = up.parent_id where up.depth < 5)
  select array_agg(m.prodi) from pg_temp.h_unit_prodi() m
   where m.unit_id = (select up.id from up where exists (select 1 from pg_temp.h_unit_prodi() x where x.unit_id = up.id)
                       order by up.depth limit 1) $$;

-- Add students to an activity's current participant set until it holds p_target counted students (+ staff up to
-- p_staff). Returns how many students were added.
create or replace function pg_temp.h_fill(p_activity uuid, p_target int, p_staff int default 0) returns int
language plpgsql as $$
declare a realisasi.activities; v_set uuid; v_section text; v_have int; v_need int; v_added int := 0;
        v_prodi text[]; v_partner text; v_ref int; v_years int;
begin
  select * into a from realisasi.activities where id = p_activity;
  if not found then return 0; end if;
  select id into v_set from realisasi.participant_set_versions where activity_id = p_activity order by version desc limit 1;
  if v_set is null then raise exception 'activity %: no participant set', a.code; end if;
  v_section := case when a.direction = 'outbound' then 'internal' else 'inbound' end;
  select count(*) into v_have from realisasi.participant_students where set_version_id = v_set and section::text = v_section;
  v_need := p_target - v_have;

  -- academic intake that is enrolled on the start date (the AY starting in August)
  v_ref := extract(year from a.start_date)::int - case when extract(month from a.start_date) < 8 then 1 else 0 end;
  if v_section = 'internal' then
    v_prodi := pg_temp.h_prodi_of(a.submitter_unit_id);
    if v_prodi is null then raise exception 'activity %: no prodi mapping for unit %', a.code, a.submitter_unit_id; end if;
  else
    select p.name into v_partner from realisasi.activity_documents ad
      join kerjasama.document_partners dp on dp.document_id = ad.original_document_id and dp.is_lead
      join kerjasama.partners p on p.id = dp.partner_id
     where ad.activity_id = p_activity limit 1;
  end if;

  if v_need > 0 then
    with taken as (   -- students another unit claims on overlapping dates (any version, drafts included)
      select ps.nrp from realisasi.participant_students ps
        join realisasi.participant_set_versions v on v.id = ps.set_version_id
        join realisasi.activities o on o.id = v.activity_id
       where o.id <> a.id and o.submitter_unit_id <> a.submitter_unit_id
         and o.start_date <= a.end_date and a.start_date <= o.end_date),
    pick as (
      select s.* from mock_baak.students s
       where s.status <> 'inactive'
         and not exists (select 1 from realisasi.participant_students x where x.set_version_id = v_set and x.nrp = s.nrp)
         and s.nrp not in (select nrp from taken)
         and case when v_section = 'internal' then
                s.category = 'regular' and s.prodi_name = any(v_prodi)
                and s.intake_year <= v_ref
                and s.intake_year > v_ref - case when s.prodi_name = 'Magister Manajemen' then 2 else 4 end
                and s.intake_year < v_ref   -- no first-semester students abroad
              else
                s.category = 'inbound_exchange' and s.home_institution = v_partner
                and s.intake_year = extract(year from a.start_date)::int
              end
       order by exists (select 1 from realisasi.participant_students u where u.nrp = s.nrp), md5(s.nrp || a.code)
       limit v_need)
    insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
                home_institution, home_student_number, home_country_code)
    select v_set, v_section::realisasi.student_section, p.nrp, p.full_name, p.faculty_name, p.prodi_name,
           p.home_institution, case when v_section = 'inbound' then 'HS-' || right(p.nrp, 4) end, p.home_country_code
      from pick p;
    get diagnostics v_added = row_count;
    if v_added < v_need then
      raise exception 'activity %: only % of % eligible students available', a.code, v_added, v_need;
    end if;
  end if;

  if p_staff > (select count(*) from realisasi.participant_staff where set_version_id = v_set) then
    insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
    select v_set, e.employee_id, e.full_name, e.unit_name from mock_hr.employees e
     where e.status = 'active'
       and not exists (select 1 from realisasi.participant_staff x where x.set_version_id = v_set and x.employee_id = e.employee_id)
     order by md5(e.employee_id || a.code)
     limit p_staff - (select count(*) from realisasi.participant_staff where set_version_id = v_set);
  end if;
  return v_added;
end $$;

-- One kegiatan with its units, kerja sama, SDGs, external persons, files, participants (mobility) and history.
--   p_mstatus (mobility only): approved | pending | revision_requested; p_msince = when Mobility acted (or submit time)
--   p_rev: an earlier revision round {"note", "at", "resubmit"} before the final p_mstatus
--   p_auto / p_auto_staff: instead of listing NRPs, let pg_temp.h_fill pick that many students (and staff); with p_rev the
--   revised version 1 holds all but one of them (the student the revision note was about)
create or replace function pg_temp.h_act(
  p_n int, p_name text, p_unit int, p_agenda int, p_dir text, p_start date, p_end date, p_mode text, p_venue text,
  p_country text, p_doc int, p_sdgs int[], p_desc text, p_submitted timestamptz,
  p_mstatus text default null, p_msince timestamptz default null, p_mnote text default null,
  p_int text[] default '{}', p_inb text[] default '{}', p_staff text[] default '{}',
  p_co int[] default '{}', p_ext jsonb default '[]', p_files text[] default '{ia,ir}', p_rev jsonb default null,
  p_auto int default 0, p_auto_staff int default 0)
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
  if v_mob and p_submitted is not null and ((cardinality(p_int) + cardinality(p_inb) = 0 and p_auto = 0) or p_mstatus is null) then
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
  if v_mob and cardinality(p_int) + cardinality(p_inb) + cardinality(p_staff) + p_auto > 0 then
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
    if p_auto = 0 and (select count(*) from realisasi.participant_students ps join realisasi.participant_set_versions v on v.id = ps.set_version_id
         where v.activity_id = v_id and v.version = 1) <> cardinality(p_int) + cardinality(p_inb) then
      raise exception 'activity %: an NRP is not in mock_baak.students', p_n;
    end if;
    if p_auto > 0 then
      perform pg_temp.h_fill(v_id, p_auto, p_auto_staff);
      if p_rev is not null then   -- version 1 (sent back) lacked the last student added in version 2
        insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
                    home_institution, home_student_number, home_country_code)
        select md5(v_id::text || ':v1')::uuid, s.section, s.nrp, s.full_name, s.faculty_name, s.prodi_name,
               s.home_institution, s.home_student_number, s.home_country_code
          from realisasi.participant_students s where s.set_version_id = md5(v_id::text || ':v2')::uuid
         order by s.id limit greatest(p_auto - 1, 1)
        on conflict do nothing;
      end if;
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

-- the only student conflicts are the ones the seeds create on purpose (04: RL-2026-0006 / RL-2026-0013)
create or replace function pg_temp.h_assert_no_conflicts() returns void language plpgsql as $$
declare v text;
begin
  select string_agg(distinct x.nrp || ' (' || a.code || ' / ' || o.code || ')', ', ') into v
    from realisasi.activities a
    join realisasi.activities o on o.id > a.id and o.status <> 'draft' and o.submitter_unit_id <> a.submitter_unit_id
                               and o.start_date <= a.end_date and a.start_date <= o.end_date
    cross join lateral (select realisasi._claimed_nrps(a.id) as nrp) x
   where a.status <> 'draft' and x.nrp in (select realisasi._claimed_nrps(o.id))
     and not exists (select 1 from realisasi.participant_conflicts c
                      where c.nrp = x.nrp and c.activity_a = least(a.id, o.id) and c.activity_b = greatest(a.id, o.id));
  if v is not null then raise exception 'unintended student conflicts: %', v; end if;
end $$;

-- supersede system snapshots whose items differ from what the scheduled job would freeze now (oldest period first, so
-- later snapshots see the re-frozen previous period as their late-addition baseline)
-- (p_ay limits it to one academic year: on Supabase each re-freeze runs as its own short statement)
create or replace function pg_temp.h_refreeze_stale(p_reason text, p_ay int default null) returns int language plpgsql as $$
declare s realisasi.kpi_snapshots; n int := 0;
begin
  for s in select k.* from realisasi.kpi_snapshots k where k.superseded_by is null and k.frozen_by is null
                and (p_ay is null or k.academic_year_id = p_ay) order by k.frozen_at loop
    if exists ((select distinct i.kpi_code, i.bucket, i.ref_type, i.ref_id
                  from realisasi.kpi_items(s.window_start, s.window_end, s.cutoff_date, s.academic_year_id, s.frozen_at, null) i
                except
                select i.kpi_code, i.bucket, i.ref_type, i.ref_id from realisasi.kpi_snapshot_items i where i.snapshot_id = s.id)
               union all
               (select i.kpi_code, i.bucket, i.ref_type, i.ref_id from realisasi.kpi_snapshot_items i where i.snapshot_id = s.id
                except
                select distinct i.kpi_code, i.bucket, i.ref_type, i.ref_id
                  from realisasi.kpi_items(s.window_start, s.window_end, s.cutoff_date, s.academic_year_id, s.frozen_at, null) i)) then
      perform realisasi._freeze(s.academic_year_id, s.kind, s.frozen_at + interval '1 second', null, p_reason, s.id);
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;

-- date system freezes' notifications (and outbox rows) at the snapshot's frozen_at, read for io_admin (as 90_freeze)
create or replace function pg_temp.h_date_freeze_notifications() returns void language sql as $$
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
$$;
