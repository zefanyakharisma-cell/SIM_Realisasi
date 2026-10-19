-- bulk/_helpers.inc: helpers for the bulk Kegiatan seed (04_bulk_1..8.sql = RL-2026-0101..0300), included with
-- "\ir bulk/_helpers.inc". Same row shapes as 03_activities.sql (ids a0000000-…-000000000NNN, event groups
-- e0000000-…NNN), plus guards so a bulk row can never contradict the business rules the scenarios rely on:
--   * the agreement is valid for the activity dates (R-04, documents_valid_between)
--   * submitted on/after the end date and not in the future; the mobility decision comes after the submission
--   * mobility kegiatan carry a participant set whose status matches the Mobility track; non-mobility ones carry none
--   * a student never sits in two activities with overlapping dates (so no rule 2.1 conflicts appear)
-- Idempotent: an existing activity is skipped.

create or replace function pg_temp.aid(n int) returns uuid language sql immutable as $$
  select ('a0000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.gid(n int) returns uuid language sql immutable as $$
  select ('e0000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
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
declare v_id uuid := pg_temp.aid(p_n); v_g uuid := pg_temp.gid(p_n); v_code text := 'RL-2026-' || lpad(p_n::text, 4, '0');
        v_creator uuid; v_created timestamptz; k text; v_path text; e jsonb; v_mob boolean; u int;
        c_mob uuid := '00000000-0000-4000-8000-000000000003';
begin
  if exists (select 1 from realisasi.activities where id = v_id) then return; end if;
  -- guards
  if p_n not between 101 and 300 then raise exception 'bulk %: number outside 101..300', p_n; end if;
  if not exists (select 1 from kerjasama.units where id = p_unit) then raise exception 'bulk %: unit % missing', p_n, p_unit; end if;
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

  v_creator := coalesce((select id from kerjasama.profiles where app_role = 'submitter' and unit_id = p_unit order by id limit 1),
                        '00000000-0000-4000-8000-000000000001');
  v_created := coalesce(p_submitted, pg_temp.wib(p_end)) - interval '3 days';
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
          case when v_status in ('approved', 'revision_requested') then '00000000-0000-4000-8000-000000000003'::uuid end,
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
  select count(*) into v_n from realisasi.activities a where a.id = any (select pg_temp.aid(g) from generate_series(p_from, p_to) g);
  if v_n <> p_to - p_from + 1 then raise exception 'bulk_verify %..%: % of % kegiatan present', p_from, p_to, v_n, p_to - p_from + 1; end if;
  select string_agg(a.code, ', ') into v_bad from realisasi.activities a
   where a.id = any (select pg_temp.aid(g) from generate_series(p_from, p_to) g)
     and realisasi.agenda_is_mobility(a.agenda_id) and a.submitted_at is not null
     and not exists (select 1 from realisasi.participant_set_versions v where v.activity_id = a.id);
  if v_bad is not null then raise exception 'bulk_verify: mobility kegiatan without participants: %', v_bad; end if;
  perform setval('realisasi.activity_code_seq', greatest(300, (select last_value from realisasi.activity_code_seq)));
end $$;
