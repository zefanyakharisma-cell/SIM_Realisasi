-- 0007_rpc_submission: lookups, drafts, participants, checklist, submit, student-conflict scan.

-- Agenda rules (Revisi V.1): an agenda is a mobility kegiatan when realisasi.agenda_rules gives it a category
create function realisasi.agenda_category(p_agenda int) returns realisasi.mobility_category
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select mobility_category from realisasi.agenda_rules where agenda_id = p_agenda
$$;

create function realisasi.agenda_is_mobility(p_agenda int) returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select realisasi.agenda_category(p_agenda) is not null
$$;

-- Lookups (Schema §4) ------------------------------------------------------
-- Registry lookups: only roles that enter participants (submitter, mobility team, io_admin); at most 500 ids (L5)
create function realisasi._require_registry_reader(p_n int) returns void
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
begin
  perform realisasi._require_uid();
  if not (coalesce(realisasi.my_role() in ('submitter','io_admin'), false) or realisasi.in_team('mobility')) then
    perform realisasi._forbidden();
  end if;
  if coalesce(p_n, 0) > 500 then perform realisasi._invalid('ids'); end if;
end $$;

create function realisasi.lookup_students(p_nrps text[]) returns setof mock_baak.students
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
begin
  perform realisasi._require_registry_reader(cardinality(p_nrps));
  return query select s.* from mock_baak.students s where s.nrp = any(p_nrps) order by s.nrp;
end $$;

create function realisasi.lookup_employees(p_ids text[]) returns setof mock_hr.employees
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
begin
  perform realisasi._require_registry_reader(cardinality(p_ids));
  return query select e.* from mock_hr.employees e where e.employee_id = any(p_ids) order by e.employee_id;
end $$;

create function realisasi.documents_valid_between(p_start date, p_end date, p_unit_id int default null)
returns table(document_id int, doc_number text, title text, kind text, status text, start_date date, end_date date,
              auto_renewed boolean, is_archived boolean, chain_id int, current_doc_number text, partners jsonb,
              in_scope boolean)
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select d.id, d.doc_number, d.title, d.kind, d.status, d.start_date, d.end_date, d.auto_renewed,
         d.status = 'archived', realisasi.chain_root(d.id),
         (select c.doc_number from kerjasama.documents c where c.id = realisasi.chain_current(d.id)),
         coalesce((select jsonb_agg(jsonb_build_object('partner_id', p.id, 'name', p.name, 'country_code', p.country_code,
                                                       'country_name', co.name, 'is_lead', dp.is_lead)
                                    order by dp.is_lead desc, p.name)
                     from kerjasama.document_partners dp join kerjasama.partners p on p.id = dp.partner_id
                     left join kerjasama.countries co on co.code = p.country_code
                    where dp.document_id = d.id), '[]'::jsonb),
         (p_unit_id is null or exists (select 1 from kerjasama.document_scope_units su
                                        where su.document_id = d.id and su.unit_id = p_unit_id))
    from kerjasama.documents d
   where p_start is not null and p_end is not null
     and d.status not in ('in_process','rejected')
     and d.start_date <= p_end
     -- validity end (H2): termination date; for an auto-renewed document the day before its first valid successor
     -- starts (open-ended when it has none); otherwise end_date
     and case when d.terminated_at is not null then d.terminated_at::date >= p_start
              when d.auto_renewed then not exists (select 1 from kerjasama.documents x where x.predecessor_id = d.id
                                                     and x.status not in ('in_process','rejected') and x.start_date is not null
                                                     and greatest(d.end_date, x.start_date - 1) < p_start)
              else d.end_date >= p_start end
   order by d.doc_number
$$;

-- Small internal helpers ------------------------------------------------------
create function realisasi._jtext(p jsonb, p_key text) returns text
language sql immutable set search_path = realisasi, extensions, public, pg_temp as $$
  select nullif(btrim(p ->> p_key), '')
$$;

create function realisasi._int_array(p jsonb, p_field text) returns int[]
language plpgsql set search_path = realisasi, extensions, public, pg_temp as $$
declare v int[];
begin
  if p is null or jsonb_typeof(p) = 'null' then return '{}'; end if;
  if jsonb_typeof(p) <> 'array' then
    perform realisasi._raise('VALIDATION_INVALID', format('Nilai tidak valid: %s.', p_field), jsonb_build_object('fields', jsonb_build_array(p_field)));
  end if;
  begin
    select coalesce(array_agg(distinct (x #>> '{}')::int order by (x #>> '{}')::int), '{}') into v from jsonb_array_elements(p) x;
  exception when others then
    perform realisasi._raise('VALIDATION_INVALID', format('Nilai tidak valid: %s.', p_field), jsonb_build_object('fields', jsonb_build_array(p_field)));
  end;
  return v;
end $$;

create function realisasi._invalid(p_field text) returns void
language sql security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select realisasi._raise('VALIDATION_INVALID', format('Nilai tidak valid: %s.', p_field),
                          jsonb_build_object('fields', jsonb_build_array(p_field)))
$$;

create function realisasi._status_result(p_id uuid) returns jsonb
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select jsonb_build_object('id', a.id, 'status', a.status,
                            'mobility_status', a.mobility_status, 'verified_at', a.verified_at)
    from realisasi.activities a where a.id = p_id
$$;

create function realisasi._draft_pset(p_activity uuid) returns uuid
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select id from realisasi.participant_set_versions where activity_id = p_activity and status = 'draft'
$$;

-- draft version if present, else latest version (any status)
create function realisasi._relevant_pset(p_activity uuid) returns uuid
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce(realisasi._draft_pset(p_activity),
                  (select id from realisasi.participant_set_versions where activity_id = p_activity
                    order by version desc limit 1))
$$;

create function realisasi._pset_rows(p_version uuid) returns int
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select ((select count(*) from realisasi.participant_students where set_version_id = p_version)
        + (select count(*) from realisasi.participant_staff where set_version_id = p_version))::int
$$;

-- current state of an activity as a payload-shaped jsonb (used for diffs)
create function realisasi._activity_state(p_id uuid) returns jsonb
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select jsonb_build_object(
    'name', a.name, 'agenda_id', a.agenda_id, 'direction', a.direction, 'start_date', a.start_date, 'end_date', a.end_date,
    'mode', a.mode, 'venue', a.venue, 'country_code', a.country_code,
    'sks_recognized', a.sks_recognized, 'description', a.description,
    'submitter_unit_id', a.submitter_unit_id,
    'co_unit_ids', coalesce((select jsonb_agg(unit_id order by unit_id) from realisasi.activity_units
                              where activity_id = a.id and not is_submitter), '[]'),
    'document_id', (select original_document_id from realisasi.activity_documents where activity_id = a.id),
    'sdg_ids', coalesce((select jsonb_agg(sdg_id order by sdg_id) from realisasi.activity_sdgs where activity_id = a.id), '[]'),
    'external_persons', coalesce((select jsonb_agg(jsonb_build_object('full_name', e.full_name, 'institution', e.institution,
                                     'country_code', e.country_code, 'role', e.role, 'notes', e.notes) order by e.id)
                                    from realisasi.activity_external_persons e where e.activity_id = a.id), '[]'))
  from realisasi.activities a where a.id = p_id
$$;

create function realisasi._json_diff(p_old jsonb, p_new jsonb) returns jsonb
language sql immutable set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce(jsonb_object_agg(k, jsonb_build_array(p_old -> k, p_new -> k) order by k), '{}'::jsonb)
    from jsonb_object_keys(p_new) k
   where (p_old -> k) is distinct from (p_new -> k)
$$;

-- Core create/update of the Detail payload. p_mode: create | draft | revision | verified. Returns the diff.
create function realisasi._apply_activity_payload(p_id uuid, p_data jsonb, p_mode text) returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare
  v_old jsonb := case when p_id is null then '{}'::jsonb else realisasi._activity_state(p_id) end;
  v_m jsonb;            -- merged payload
  v_missing text[] := '{}';
  v_name text; v_agenda int; v_dir realisasi.direction; v_start date; v_end date; v_mode realisasi.activity_mode;
  v_venue text; v_country text; v_sks numeric; v_desc text; v_unit int;
  v_co int[]; v_doc int; v_docs int[]; v_sdgs int[]; v_ext jsonb; v_e jsonb; v_i int;
  v_bad int; v_bad_number text; v_uid uuid := auth.uid();
  v_k text; v_id uuid; v_group uuid;
begin
  if p_data is null or jsonb_typeof(p_data) <> 'object' then perform realisasi._invalid('payload'); end if;
  -- merge: absent keys keep their value on update
  v_m := v_old;
  for v_k in select jsonb_object_keys(p_data) loop
    if v_k in ('name','agenda_id','direction','start_date','end_date','mode','venue','country_code','sks_recognized',
               'description','submitter_unit_id','co_unit_ids','document_id','sdg_ids','external_persons') then
      v_m := v_m || jsonb_build_object(v_k, p_data -> v_k);
    end if;
  end loop;

  -- required fields
  foreach v_k in array array['name','agenda_id','direction','start_date','end_date','mode','description','submitter_unit_id'] loop
    if realisasi._jtext(v_m, v_k) is null then v_missing := v_missing || v_k; end if;
  end loop;
  if cardinality(v_missing) > 0 then
    perform realisasi._raise('VALIDATION_REQUIRED', 'Kolom wajib belum diisi: ' || array_to_string(v_missing, ', ') || '.',
                             jsonb_build_object('fields', to_jsonb(v_missing)));
  end if;

  -- typed parsing
  v_name := realisasi._jtext(v_m, 'name');
  v_desc := realisasi._jtext(v_m, 'description');
  v_venue := realisasi._jtext(v_m, 'venue');
  v_country := upper(realisasi._jtext(v_m, 'country_code'));
  begin v_agenda := (v_m ->> 'agenda_id')::int; exception when others then perform realisasi._invalid('agenda_id'); end;
  begin v_dir := (v_m ->> 'direction')::realisasi.direction; exception when others then perform realisasi._invalid('direction'); end;
  begin v_start := (v_m ->> 'start_date')::date; exception when others then perform realisasi._invalid('start_date'); end;
  begin v_end := (v_m ->> 'end_date')::date; exception when others then perform realisasi._invalid('end_date'); end;
  begin v_mode := (v_m ->> 'mode')::realisasi.activity_mode; exception when others then perform realisasi._invalid('mode'); end;
  begin v_sks := nullif(v_m ->> 'sks_recognized', '')::numeric(4,1); exception when others then perform realisasi._invalid('sks_recognized'); end;
  begin v_unit := (v_m ->> 'submitter_unit_id')::int; exception when others then perform realisasi._invalid('submitter_unit_id'); end;
  v_co := realisasi._int_array(v_m -> 'co_unit_ids', 'co_unit_ids');
  begin v_doc := nullif(v_m ->> 'document_id', '')::int; exception when others then perform realisasi._invalid('document_id'); end;
  v_docs := case when v_doc is null then '{}'::int[] else array[v_doc] end;   -- Revisi V.1: one kerja sama per kegiatan
  v_sdgs := realisasi._int_array(v_m -> 'sdg_ids', 'sdg_ids');
  v_ext := coalesce(nullif(v_m -> 'external_persons', 'null'::jsonb), '[]'::jsonb);
  if jsonb_typeof(v_ext) <> 'array' then perform realisasi._invalid('external_persons'); end if;

  if v_end < v_start then
    perform realisasi._raise('END_BEFORE_START', 'Tanggal selesai tidak boleh sebelum tanggal mulai.',
                             jsonb_build_object('fields', jsonb_build_array('end_date')));
  end if;
  if v_sks is not null and v_sks < 0 then perform realisasi._invalid('sks_recognized'); end if;

  -- Jenis Kegiatan = SIMKS agenda; must exist, and be active when newly chosen
  if not exists (select 1 from kerjasama.agendas g where g.id = v_agenda
                   and (g.is_active or (v_old ->> 'agenda_id')::int = v_agenda)) then
    perform realisasi._invalid('agenda_id');
  end if;
  -- SKS diakui only applies to mobility kegiatan (Revisi V.1 item 5)
  if not realisasi.agenda_is_mobility(v_agenda) then v_sks := null; end if;
  if v_country is not null and not exists (select 1 from kerjasama.countries where code = v_country) then
    perform realisasi._invalid('country_code');
  end if;
  -- Revisi V.1: SIM Realisasi is used by Unit Akademik only (submitter and units involved)
  if not exists (select 1 from kerjasama.units where id = v_unit and is_academic) then perform realisasi._invalid('submitter_unit_id'); end if;
  if exists (select 1 from unnest(v_co) u where not exists (select 1 from kerjasama.units x where x.id = u and x.is_academic)) then
    perform realisasi._invalid('co_unit_ids');
  end if;
  v_co := array(select u from unnest(v_co) u where u <> v_unit order by u);
  if exists (select 1 from unnest(v_sdgs) s where s not between 1 and 17) then perform realisasi._invalid('sdg_ids'); end if;

  -- external persons
  v_i := 0;
  for v_e in select * from jsonb_array_elements(v_ext) loop
    if realisasi._jtext(v_e, 'full_name') is null or realisasi._jtext(v_e, 'institution') is null
       or realisasi._jtext(v_e, 'country_code') is null or realisasi._jtext(v_e, 'role') is null then
      perform realisasi._raise('VALIDATION_REQUIRED', 'Kolom wajib belum diisi: external_persons.',
                               jsonb_build_object('fields', jsonb_build_array('external_persons'), 'index', v_i));
    end if;
    if not exists (select 1 from kerjasama.countries where code = upper(v_e ->> 'country_code')) then
      perform realisasi._invalid('external_persons');
    end if;
    begin perform (v_e ->> 'role')::realisasi.person_role; exception when others then perform realisasi._invalid('external_persons'); end;
    v_i := v_i + 1;
  end loop;
  v_ext := coalesce((select jsonb_agg(jsonb_build_object('full_name', btrim(e ->> 'full_name'), 'institution', btrim(e ->> 'institution'),
                        'country_code', upper(e ->> 'country_code'), 'role', e ->> 'role', 'notes', realisasi._jtext(e, 'notes')) order by o)
                       from jsonb_array_elements(v_ext) with ordinality x(e, o)), '[]'::jsonb);

  -- R-04: every agreement must be valid for the activity dates
  select d.id, d.doc_number into v_bad, v_bad_number
    from unnest(v_docs) x(id) left join kerjasama.documents d on d.id = x.id
   where not exists (select 1 from realisasi.documents_valid_between(v_start, v_end) v where v.document_id = x.id)
   order by x.id limit 1;
  if found then
    perform realisasi._raise('R04_AGREEMENT_NOT_VALID',
      format('Kerja sama %s tidak berlaku pada tanggal kegiatan.', coalesce(v_bad_number, '#' || v_bad)),
      jsonb_build_object('document_ids', jsonb_build_array(v_bad), 'fields', jsonb_build_array('document_id')));
  end if;

  -- apply ------------------------------------------------------------------
  if p_id is null then
    insert into realisasi.event_groups (created_by, created_at) values (v_uid, realisasi.now_ts()) returning id into v_group;
    insert into realisasi.activities (name, agenda_id, direction, start_date, end_date, mode, venue, country_code, sks_recognized,
                                      description, submitter_unit_id, created_by, event_group_id, created_at)
    values (v_name, v_agenda, v_dir, v_start, v_end, v_mode, v_venue, v_country, v_sks, v_desc, v_unit,
            v_uid, v_group, realisasi.now_ts())
    returning id into v_id;
  else
    v_id := p_id;
    update realisasi.activities
       set name = v_name, agenda_id = v_agenda, direction = v_dir, start_date = v_start, end_date = v_end, mode = v_mode,
           venue = v_venue, country_code = v_country, sks_recognized = v_sks,
           description = v_desc, submitter_unit_id = v_unit
     where id = p_id;
  end if;

  -- units (submitter + co-units)
  delete from realisasi.activity_units where activity_id = v_id and unit_id <> v_unit and unit_id <> all(v_co);
  insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, v_unit, true)
    on conflict (activity_id, unit_id) do update set is_submitter = true;
  insert into realisasi.activity_units (activity_id, unit_id, is_submitter) select v_id, u, false from unnest(v_co) u
    on conflict (activity_id, unit_id) do update set is_submitter = false;

  -- agreements: keep existing links (and their partner snapshots, R-06), add/remove the difference
  delete from realisasi.activity_documents where activity_id = v_id and original_document_id <> all(v_docs);
  insert into realisasi.activity_documents (activity_id, original_document_id)
    select v_id, d from unnest(v_docs) d on conflict do nothing;
  update realisasi.activity_documents ad
     set out_of_scope_warning = not exists (select 1 from kerjasama.document_scope_units su
                                             where su.document_id = ad.original_document_id and su.unit_id = v_unit)
   where ad.activity_id = v_id;

  -- SDGs
  delete from realisasi.activity_sdgs where activity_id = v_id and sdg_id <> all(v_sdgs::smallint[]);
  insert into realisasi.activity_sdgs (activity_id, sdg_id) select v_id, s::smallint from unnest(v_sdgs) s on conflict do nothing;

  -- external persons (replace-all when changed)
  if coalesce(v_old -> 'external_persons', '[]'::jsonb) is distinct from v_ext then
    delete from realisasi.activity_external_persons where activity_id = v_id;
    insert into realisasi.activity_external_persons (activity_id, full_name, institution, country_code, role, notes)
    select v_id, e ->> 'full_name', e ->> 'institution', e ->> 'country_code', (e ->> 'role')::realisasi.person_role, e ->> 'notes'
      from jsonb_array_elements(v_ext) with ordinality x(e, o) order by o;
  end if;

  return jsonb_build_object('id', v_id,
                            'diff', case when p_id is null then '{}'::jsonb
                                         else realisasi._json_diff(v_old, realisasi._activity_state(v_id)) end);
end $$;

-- Load an activity the caller may see (NOT_FOUND otherwise), locking it.
create function realisasi._get_activity(p_id uuid, p_lock boolean default true) returns realisasi.activities
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v realisasi.activities;
begin
  if p_lock then
    select * into v from realisasi.activities where id = p_id for update;
  else
    select * into v from realisasi.activities where id = p_id;
  end if;
  if not found or not realisasi.can_view_activity(p_id) then perform realisasi._not_found(); end if;
  return v;
end $$;

-- save_activity_draft ---------------------------------------------------------
create function realisasi.save_activity_draft(p_id uuid, p_data jsonb) returns uuid
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_uid(); v_role text := realisasi.my_role();
        v_act realisasi.activities; v_res jsonb; v_unit int;
begin
  if p_data is null or jsonb_typeof(p_data) <> 'object' then perform realisasi._invalid('payload'); end if;
  begin v_unit := (p_data ->> 'submitter_unit_id')::int; exception when others then perform realisasi._invalid('submitter_unit_id'); end;

  if p_id is null then
    if v_role = 'submitter' then
      if v_unit is not null and v_unit is distinct from realisasi.my_unit() then
        perform realisasi._raise('R14_UNIT_NOT_ALLOWED', 'Anda hanya dapat mengajukan kegiatan untuk unit Anda sendiri.');
      end if;
    elsif v_role is distinct from 'io_admin' then
      perform realisasi._forbidden();
    end if;
    v_res := realisasi._apply_activity_payload(null, p_data, 'create');
    perform realisasi._log((v_res ->> 'id')::uuid, 'system', null, 'create');
    return (v_res ->> 'id')::uuid;
  end if;

  v_act := realisasi._get_activity(p_id);
  if not realisasi._is_unit_editor(p_id) then perform realisasi._forbidden(); end if;
  if not (v_act.status = 'draft' or v_act.mobility_status = 'revision_requested') then perform realisasi._state_invalid(); end if;
  if p_data ? 'submitter_unit_id' and v_unit is distinct from v_act.submitter_unit_id then
    if v_act.status <> 'draft' then perform realisasi._invalid('submitter_unit_id'); end if;
    if v_role = 'submitter' and v_unit is distinct from realisasi.my_unit() then
      perform realisasi._raise('R14_UNIT_NOT_ALLOWED', 'Anda hanya dapat mengajukan kegiatan untuk unit Anda sendiri.');
    end if;
  end if;
  v_res := realisasi._apply_activity_payload(p_id, p_data, case when v_act.status = 'draft' then 'draft' else 'revision' end);
  if v_act.status <> 'draft' and (v_res -> 'diff') <> '{}'::jsonb then
    perform realisasi._log(p_id, 'revision', 'mobility', 'edit_detail', null, v_res -> 'diff');
  end if;
  return p_id;
end $$;

-- delete_draft (R-15) ------------------------------------------------------------
-- who may delete a draft: IO Admin any draft; a submitter only the drafts they created
create function realisasi._can_delete_draft(p_id uuid) returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce(realisasi.my_role() = 'io_admin', false)
      or (coalesce(realisasi.my_role() = 'submitter', false)
          and exists (select 1 from realisasi.activities a where a.id = p_id and a.created_by = auth.uid()))
$$;

create function realisasi.delete_draft(p_id uuid) returns void
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_uid(); v_act realisasi.activities;
begin
  v_act := realisasi._get_activity(p_id);
  if not realisasi._can_delete_draft(p_id) then perform realisasi._forbidden(); end if;
  if v_act.status <> 'draft' then perform realisasi._raise('R15_NOT_DRAFT', 'Hanya draf yang dapat dihapus.'); end if;

  delete from realisasi.file_blobs
   where path like 'realisasi-files/' || p_id::text || '/%' or path like 'realisasi-transcripts/' || p_id::text || '/%';
  delete from realisasi.activity_files where activity_id = p_id;
  delete from realisasi.participant_students where set_version_id in (select id from realisasi.participant_set_versions where activity_id = p_id);
  delete from realisasi.participant_staff where set_version_id in (select id from realisasi.participant_set_versions where activity_id = p_id);
  delete from realisasi.participant_set_versions where activity_id = p_id;
  delete from realisasi.activity_sdgs where activity_id = p_id;
  delete from realisasi.activity_external_persons where activity_id = p_id;
  delete from realisasi.activity_documents where activity_id = p_id;
  delete from realisasi.activity_partner_snapshot where activity_id = p_id;
  delete from realisasi.activity_units where activity_id = p_id;
  delete from realisasi.activity_log where activity_id = p_id;
  delete from realisasi.participant_conflicts where activity_a = p_id or activity_b = p_id;
  delete from realisasi.activities where id = p_id;
  delete from realisasi.event_groups g where g.id = v_act.event_group_id
     and not exists (select 1 from realisasi.activities a where a.event_group_id = g.id);
end $$;

-- Participants ----------------------------------------------------------------------
-- copy the latest version into a new draft version (internal)
create function realisasi._copy_pset_to_draft(p_activity uuid) returns uuid
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_src uuid; v_new uuid; v_ver int;
begin
  select id into v_src from realisasi.participant_set_versions where activity_id = p_activity order by version desc limit 1;
  select coalesce(max(version), 0) + 1 into v_ver from realisasi.participant_set_versions where activity_id = p_activity;
  insert into realisasi.participant_set_versions (activity_id, version, status) values (p_activity, v_ver, 'draft')
  returning id into v_new;
  if v_src is not null then
    insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
                home_institution, home_student_number, home_country_code)
    select v_new, section, nrp, full_name, faculty_name, prodi_name, home_institution, home_student_number,
           home_country_code
      from realisasi.participant_students where set_version_id = v_src order by id;
    insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
    select v_new, employee_id, full_name, unit_name from realisasi.participant_staff where set_version_id = v_src order by id;
  end if;
  return v_new;
end $$;

create function realisasi.ensure_participant_draft(p_activity uuid) returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_uid(); v_act realisasi.activities; v_id uuid; v_created boolean := false;
begin
  v_act := realisasi._get_activity(p_activity);
  if not realisasi._can_edit_participants(p_activity) then
    if realisasi._is_unit_editor(p_activity) or realisasi.in_team('mobility') then perform realisasi._state_invalid(); end if;
    perform realisasi._forbidden();
  end if;
  v_id := realisasi._draft_pset(p_activity);
  if v_id is null then
    v_id := realisasi._copy_pset_to_draft(p_activity);
    v_created := true;
  end if;
  return jsonb_build_object('version_id', v_id,
                            'version', (select version from realisasi.participant_set_versions where id = v_id),
                            'created', v_created);
end $$;

create function realisasi.save_participants(p_activity uuid, p_students jsonb, p_staff jsonb) returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare
  v_draft jsonb; v_vid uuid; v_ver int;
  v_rows jsonb; v_list text;
  v_students jsonb := coalesce(nullif(p_students, 'null'::jsonb), '[]'::jsonb);
  v_staff jsonb := coalesce(nullif(p_staff, 'null'::jsonb), '[]'::jsonb);
  r record;
begin
  perform realisasi._require_uid();
  if jsonb_typeof(v_students) <> 'array' then perform realisasi._invalid('students'); end if;
  if jsonb_typeof(v_staff) <> 'array' then perform realisasi._invalid('staff'); end if;
  v_draft := realisasi.ensure_participant_draft(p_activity);
  v_vid := (v_draft ->> 'version_id')::uuid; v_ver := (v_draft ->> 'version')::int;

  if to_regclass('pg_temp._ps_in') is null then
    create temp table _ps_in (idx int, section text, nrp text, home_institution text, home_student_number text,
                                          home_country_code text) on commit drop;
  end if;
  if to_regclass('pg_temp._pst_in') is null then
    create temp table _pst_in (idx int, employee_id text) on commit drop;
  end if;
  truncate _ps_in; truncate _pst_in;

  insert into _ps_in
  select (o - 1)::int, e ->> 'section', upper(btrim(e ->> 'nrp')), realisasi._jtext(e, 'home_institution'),
         realisasi._jtext(e, 'home_student_number'), upper(realisasi._jtext(e, 'home_country_code'))
    from jsonb_array_elements(v_students) with ordinality x(e, o);
  insert into _pst_in select (o - 1)::int, upper(btrim(e ->> 'employee_id'))
    from jsonb_array_elements(v_staff) with ordinality x(e, o);

  if exists (select 1 from _ps_in where section is null or section not in ('internal','inbound')) then
    perform realisasi._invalid('section');
  end if;
  if exists (select 1 from _ps_in where nrp is null or nrp = '') then perform realisasi._invalid('nrp'); end if;
  if exists (select 1 from _pst_in where employee_id is null or employee_id = '') then perform realisasi._invalid('employee_id'); end if;

  -- R-22 duplicates
  select jsonb_agg(jsonb_build_object('section', section, 'index', idx, 'id', nrp, 'code', 'R22_DUPLICATE_NRP') order by idx),
         min(nrp)
    into v_rows, v_list
    from (select *, row_number() over (partition by nrp order by idx) rn from _ps_in) d where rn > 1;
  if v_rows is not null then
    perform realisasi._raise('R22_DUPLICATE_NRP', format('NRP %s tercantum lebih dari sekali.', v_list), jsonb_build_object('rows', v_rows));
  end if;
  select jsonb_agg(jsonb_build_object('section', 'staff', 'index', idx, 'id', employee_id, 'code', 'R22_DUPLICATE_EMPLOYEE') order by idx),
         min(employee_id)
    into v_rows, v_list
    from (select *, row_number() over (partition by employee_id order by idx) rn from _pst_in) d where rn > 1;
  if v_rows is not null then
    perform realisasi._raise('R22_DUPLICATE_EMPLOYEE', format('ID pegawai %s tercantum lebih dari sekali.', v_list), jsonb_build_object('rows', v_rows));
  end if;

  -- R-16 unknown NRPs (all rows reported)
  select jsonb_agg(jsonb_build_object('section', i.section, 'index', i.idx, 'id', i.nrp, 'code', 'R16_NRP_NOT_FOUND') order by i.idx),
         string_agg(i.nrp, ', ' order by i.idx)
    into v_rows, v_list
    from _ps_in i where not exists (select 1 from mock_baak.students s where s.nrp = i.nrp);
  if v_rows is not null then
    perform realisasi._raise('R16_NRP_NOT_FOUND', format('NRP tidak ditemukan di data BAAK: %s.', v_list), jsonb_build_object('rows', v_rows));
  end if;

  -- section / category match (R-16, R-17)
  select i.idx, i.nrp, i.section into r from _ps_in i join mock_baak.students s on s.nrp = i.nrp
   where i.section = 'internal' and s.category = 'inbound_exchange' order by i.idx limit 1;
  if found then
    perform realisasi._raise('R16_SECTION_MISMATCH',
      format('NRP %s terdaftar sebagai mahasiswa inbound; pindahkan ke bagian yang sesuai.', r.nrp),
      jsonb_build_object('rows', (select jsonb_agg(jsonb_build_object('section', i.section, 'index', i.idx, 'id', i.nrp, 'code', 'R16_SECTION_MISMATCH') order by i.idx)
                                    from _ps_in i join mock_baak.students s on s.nrp = i.nrp
                                   where i.section = 'internal' and s.category = 'inbound_exchange')));
  end if;
  select i.idx, i.nrp, i.section into r from _ps_in i join mock_baak.students s on s.nrp = i.nrp
   where i.section = 'inbound' and s.category <> 'inbound_exchange' order by i.idx limit 1;
  if found then
    perform realisasi._raise('R17_NOT_INBOUND',
      format('NRP %s bukan mahasiswa inbound (kategori inbound_exchange).', r.nrp),
      jsonb_build_object('rows', (select jsonb_agg(jsonb_build_object('section', i.section, 'index', i.idx, 'id', i.nrp, 'code', 'R17_NOT_INBOUND') order by i.idx)
                                    from _ps_in i join mock_baak.students s on s.nrp = i.nrp
                                   where i.section = 'inbound' and s.category <> 'inbound_exchange')));
  end if;

  -- R-19 unknown employees
  select jsonb_agg(jsonb_build_object('section', 'staff', 'index', i.idx, 'id', i.employee_id, 'code', 'R19_EMPLOYEE_NOT_FOUND') order by i.idx),
         string_agg(i.employee_id, ', ' order by i.idx)
    into v_rows, v_list
    from _pst_in i where not exists (select 1 from mock_hr.employees e where e.employee_id = i.employee_id);
  if v_rows is not null then
    perform realisasi._raise('R19_EMPLOYEE_NOT_FOUND', format('ID pegawai tidak ditemukan di data SDM: %s.', v_list), jsonb_build_object('rows', v_rows));
  end if;

  select i.idx, i.nrp into r from _ps_in i join mock_baak.students s on s.nrp = i.nrp
   where i.section = 'inbound' and coalesce(i.home_institution, s.home_institution) is null order by i.idx limit 1;
  if found then
    perform realisasi._raise('R17_INBOUND_DATA_REQUIRED',
      format('Mahasiswa inbound %s wajib memiliki institusi asal.', r.nrp),
      jsonb_build_object('rows', jsonb_build_array(jsonb_build_object('section', 'inbound', 'index', r.idx, 'id', r.nrp, 'code', 'R17_INBOUND_DATA_REQUIRED'))));
  end if;

  -- replace all rows of the draft version (names copied from the registries)
  delete from realisasi.participant_students where set_version_id = v_vid;
  delete from realisasi.participant_staff where set_version_id = v_vid;
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
              home_institution, home_student_number, home_country_code)
  select v_vid, i.section::realisasi.student_section, i.nrp, s.full_name, s.faculty_name, s.prodi_name,
         case when i.section = 'inbound' then coalesce(i.home_institution, s.home_institution) end,
         case when i.section = 'inbound' then i.home_student_number end,
         case when i.section = 'inbound' then coalesce(i.home_country_code, s.home_country_code) end
    from _ps_in i join mock_baak.students s on s.nrp = i.nrp order by i.idx;
  insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
  select v_vid, i.employee_id, e.full_name, e.unit_name from _pst_in i join mock_hr.employees e on e.employee_id = i.employee_id
   order by i.idx;

  return jsonb_build_object(
    'version_id', v_vid, 'version', v_ver,
    'students', (select count(*) from _ps_in), 'staff', (select count(*) from _pst_in),
    'warnings', coalesce((select jsonb_agg(w order by o) from (
        select jsonb_build_object('section', i.section, 'id', i.nrp, 'status', s.status) w, i.idx o
          from _ps_in i join mock_baak.students s on s.nrp = i.nrp where s.status <> 'active'
        union all
        select jsonb_build_object('section', 'staff', 'id', i.employee_id, 'status', e.status), 100000 + i.idx
          from _pst_in i join mock_hr.employees e on e.employee_id = i.employee_id where e.status <> 'active') q), '[]'::jsonb));
end $$;

-- Checklist (internal, raises nothing) ------------------------------------------
create function realisasi._checklist(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare
  a realisasi.activities;
  v_out jsonb := '[]'::jsonb; v_missing text[] := '{}'; v_bad text; v_list text;
  v_pset uuid; v_rows int; v_mob boolean; v_draft uuid; v_has boolean;
begin
  select * into a from realisasi.activities where id = p_id;
  if not found then return '[]'::jsonb; end if;
  v_mob := realisasi.agenda_is_mobility(a.agenda_id);
  v_pset := realisasi._relevant_pset(p_id);
  v_draft := realisasi._draft_pset(p_id);
  v_rows := coalesce(realisasi._pset_rows(v_pset), 0);

  -- R07_REQUIRED_FIELD
  if nullif(btrim(a.name), '') is null then v_missing := v_missing || 'name'::text; end if;
  if nullif(btrim(a.description), '') is null then v_missing := v_missing || 'description'::text; end if;
  if nullif(btrim(a.venue), '') is null then v_missing := v_missing || 'venue'::text; end if;
  if a.mode <> 'online' and a.country_code is null then v_missing := v_missing || 'country_code'::text; end if;
  v_out := v_out || jsonb_build_object('code', 'R07_REQUIRED_FIELD', 'ok', cardinality(v_missing) = 0,
    'message', case when cardinality(v_missing) = 0 then 'Data wajib sudah lengkap.'
                    else 'Data wajib belum lengkap: ' || array_to_string(v_missing, ', ') || '.' end,
    'fields', to_jsonb(v_missing));

  -- R07_AGREEMENT_REQUIRED (Revisi V.1: exactly one kerja sama)
  v_has := exists (select 1 from realisasi.activity_documents where activity_id = p_id);
  v_out := v_out || jsonb_build_object('code', 'R07_AGREEMENT_REQUIRED', 'ok', v_has,
    'message', case when v_has then 'Kerja sama sudah dipilih.' else 'Pilih kerja sama yang direalisasikan.' end);

  -- R04_AGREEMENT_NOT_VALID
  select string_agg(d.doc_number, ', ' order by d.doc_number) into v_bad
    from realisasi.activity_documents ad join kerjasama.documents d on d.id = ad.original_document_id
   where ad.activity_id = p_id
     and not exists (select 1 from realisasi.documents_valid_between(a.start_date, a.end_date) v where v.document_id = d.id);
  v_out := v_out || jsonb_build_object('code', 'R04_AGREEMENT_NOT_VALID', 'ok', v_bad is null,
    'message', case when v_bad is null then 'Kerja sama berlaku pada tanggal kegiatan.'
                    else format('Kerja sama %s tidak berlaku pada tanggal kegiatan.', v_bad) end);

  -- R08
  v_out := v_out || jsonb_build_object('code', 'R08_END_AFTER_TODAY', 'ok', a.end_date <= realisasi.today(),
    'message', case when a.end_date <= realisasi.today() then 'Kegiatan sudah selesai.'
                    else 'Kegiatan belum selesai. Tanggal selesai harus hari ini atau sebelumnya.' end);
  -- R09
  v_out := v_out || jsonb_build_object('code', 'R09_NO_ACADEMIC_YEAR', 'ok', a.academic_year_id is not null,
    'message', case when a.academic_year_id is not null then 'Tahun akademik terdaftar.'
                    else 'Tanggal mulai berada di luar tahun akademik yang terdaftar. Hubungi Admin IO.' end);
  -- R07 IA / IR
  v_has := exists (select 1 from realisasi.activity_files where activity_id = p_id and kind = 'ia' and is_current);
  v_out := v_out || jsonb_build_object('code', 'R07_IA_REQUIRED', 'ok', v_has,
    'message', case when v_has then 'Implementation Arrangement (PDF) sudah diunggah.' else 'Implementation Arrangement (PDF) wajib diunggah.' end);
  v_has := exists (select 1 from realisasi.activity_files where activity_id = p_id and kind = 'ir' and is_current);
  v_out := v_out || jsonb_build_object('code', 'R07_IR_REQUIRED', 'ok', v_has,
    'message', case when v_has then 'Implementation Report (PDF) sudah diunggah.' else 'Implementation Report (PDF) wajib diunggah.' end);
  -- R13 mobility bundle (Revisi V.1 item 8): transkrip + poster + dokumentasi in one PDF
  v_has := exists (select 1 from realisasi.activity_files where activity_id = p_id and kind = 'mobility_bundle' and is_current);
  v_out := v_out || jsonb_build_object('code', 'R13_MOBILITY_BUNDLE_REQUIRED', 'ok', not v_mob or v_has,
    'message', case when not v_mob then 'Tidak diperlukan untuk jenis kegiatan ini.'
                    when v_has then 'Berkas mobilitas (transkrip, poster, dokumentasi) sudah diunggah.'
                    else 'Kegiatan mobilitas wajib mengunggah Transkrip Mahasiswa, Poster Kegiatan, dan Dokumentasi Kegiatan dalam satu file PDF.' end);

  -- R11
  v_out := v_out || jsonb_build_object('code', 'R11_PARTICIPANTS_REQUIRED', 'ok', not (v_mob and v_rows = 0),
    'message', case when not v_mob then 'Tidak diperlukan untuk jenis kegiatan ini.'
                    when v_rows > 0 then 'Data peserta sesuai ketentuan jenis kegiatan.'
                    else 'Kegiatan mobilitas wajib memiliki data peserta.' end);
  -- R12 (by the kegiatan's Inbound/Outbound choice)
  v_has := exists (select 1 from realisasi.participant_students where set_version_id = v_pset and section = 'internal');
  v_out := v_out || jsonb_build_object('code', 'R12_OUTBOUND_STUDENT_REQUIRED',
    'ok', not v_mob or a.direction <> 'outbound' or v_has,
    'message', case when not v_mob or a.direction <> 'outbound' then 'Tidak diperlukan untuk kegiatan ini.'
                    when v_has then 'Mahasiswa PETRA sudah tercantum.'
                    else 'Kegiatan outbound wajib memiliki minimal satu mahasiswa PETRA.' end);
  v_has := exists (select 1 from realisasi.participant_students where set_version_id = v_pset and section = 'inbound');
  v_out := v_out || jsonb_build_object('code', 'R12_INBOUND_STUDENT_REQUIRED',
    'ok', not v_mob or a.direction <> 'inbound' or v_has,
    'message', case when not v_mob or a.direction <> 'inbound' then 'Tidak diperlukan untuk kegiatan ini.'
                    when v_has then 'Mahasiswa inbound sudah tercantum.'
                    else 'Kegiatan inbound wajib memiliki minimal satu mahasiswa inbound.' end);
  -- R16
  select string_agg(ps.nrp, ', ' order by ps.id) into v_list from realisasi.participant_students ps
   where ps.set_version_id = v_pset and not exists (select 1 from mock_baak.students s where s.nrp = ps.nrp);
  v_out := v_out || jsonb_build_object('code', 'R16_NRP_NOT_FOUND', 'ok', v_list is null,
    'message', case when v_list is null then 'Semua NRP ditemukan di data BAAK.' else format('NRP tidak ditemukan di data BAAK: %s.', v_list) end);
  -- R17
  select string_agg(ps.nrp, ', ' order by ps.id) into v_list from realisasi.participant_students ps
   where ps.set_version_id = v_pset and ps.section = 'inbound' and ps.home_institution is null;
  v_out := v_out || jsonb_build_object('code', 'R17_INBOUND_DATA_REQUIRED', 'ok', v_list is null,
    'message', case when v_list is null then 'Data mahasiswa inbound lengkap.'
                    else format('Mahasiswa inbound %s wajib memiliki institusi asal.', v_list) end);
  -- R19
  select string_agg(st.employee_id, ', ' order by st.id) into v_list from realisasi.participant_staff st
   where st.set_version_id = v_pset and not exists (select 1 from mock_hr.employees e where e.employee_id = st.employee_id);
  v_out := v_out || jsonb_build_object('code', 'R19_EMPLOYEE_NOT_FOUND', 'ok', v_list is null,
    'message', case when v_list is null then 'Semua ID pegawai ditemukan di data SDM.' else format('ID pegawai tidak ditemukan di data SDM: %s.', v_list) end);
  -- R21
  v_out := v_out || jsonb_build_object('code', 'R21_NEW_VERSION_REQUIRED',
    'ok', not (v_mob and a.mobility_status = 'revision_requested' and v_draft is null),
    'message', case when not v_mob or a.mobility_status <> 'revision_requested' then 'Tidak diperlukan.'
                    when v_draft is not null then 'Versi peserta baru sudah dibuat.'
                    else 'Perbarui data peserta (versi baru) sebelum mengajukan ulang.' end);

  if realisasi.today() > a.reporting_deadline then
    v_out := v_out || jsonb_build_object('code', 'LATE_NOTICE', 'ok', true, 'late', true,
      'message', format('Batas pelaporan %s telah lewat — kegiatan akan ditandai Terlambat.', realisasi._fmt_date(a.reporting_deadline)));
  end if;
  return v_out;
end $$;

create function realisasi.submission_checklist(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
begin
  perform realisasi._require_uid();
  if not exists (select 1 from realisasi.activities where id = p_id) or not realisasi.can_view_activity(p_id) then
    perform realisasi._not_found();
  end if;
  return realisasi._checklist(p_id);
end $$;

-- Student conflicts (Revisi V.1, Verifikasi Mobilitas rule 2.1), internal ----------------------------------------
-- Students an activity claims: the counting section (internal for outbound, inbound for inbound) of its approved
-- participant version, else of its pending one. Drafts and non-mobility activities claim nobody.
create function realisasi._claimed_nrps(p_activity uuid) returns setof text
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select s.nrp
    from realisasi.activities a
    join lateral (select v.id from realisasi.participant_set_versions v
                   where v.activity_id = a.id and v.status in ('approved','pending')
                   order by (v.status = 'approved') desc, v.version desc limit 1) v on true
    join realisasi.participant_students s on s.set_version_id = v.id
         and s.section = case when a.direction = 'outbound' then 'internal' else 'inbound' end::realisasi.student_section
   where a.id = p_activity and a.status <> 'draft' and realisasi.agenda_is_mobility(a.agenda_id)
$$;

-- (Re)scan one activity: an open conflict for every claimed NRP that another unit's non-draft activity with
-- overlapping dates also claims. The same unit on two activities is never a conflict (rule 2.2). Open conflicts
-- that no longer hold (student removed, dates/unit changed) are dropped; resolved ones are kept as decided.
create function realisasi._scan_conflicts(p_activity uuid) returns int
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare n int := 0; v_code text;
begin
  -- serialise scans so two concurrent submits claiming the same students see each other
  perform pg_advisory_xact_lock(hashtext('realisasi.conflict_scan'));
  if to_regclass('pg_temp._cf_pairs') is null then
    create temp table _cf_pairs (nrp text, a uuid, b uuid) on commit drop;
  end if;
  truncate _cf_pairs;
  insert into _cf_pairs
  select x.nrp, least(me.id, o.id), greatest(me.id, o.id)
    from realisasi.activities me
    join realisasi.activities o on o.id <> me.id and o.status <> 'draft'
                               and o.submitter_unit_id <> me.submitter_unit_id
                               and o.start_date <= me.end_date and me.start_date <= o.end_date
    cross join lateral (select realisasi._claimed_nrps(me.id) as nrp) x
   where me.id = p_activity
     and x.nrp in (select realisasi._claimed_nrps(o.id));

  delete from realisasi.participant_conflicts c
   where c.status = 'open' and (c.activity_a = p_activity or c.activity_b = p_activity)
     and not exists (select 1 from _cf_pairs p where p.nrp = c.nrp and p.a = c.activity_a and p.b = c.activity_b);

  insert into realisasi.participant_conflicts (nrp, activity_a, activity_b, created_at)
  select nrp, a, b, realisasi.now_ts() from _cf_pairs
  on conflict (nrp, activity_a, activity_b) do nothing;
  get diagnostics n = row_count;

  if n > 0 then
    select code into v_code from realisasi.activities where id = p_activity;
    perform realisasi._notify_team('mobility', 'conflict_found', 'Duplikat mahasiswa: ' || v_code,
      format('%s mahasiswa pada kegiatan %s juga diklaim unit lain pada tanggal yang sama. Pilih kegiatan yang diakui.', n, v_code),
      '/realisasi/verifikasi/mobilitas#duplikat');
  end if;
  return n;
end $$;

-- submit_activity -------------------------------------------------------------------
-- Revisi V.1: no Partnership verification. A non-mobility kegiatan is verified on submit; a mobility kegiatan goes to
-- the Mobility queue (pending) and is scanned for student conflicts.
create function realisasi.submit_activity(p_id uuid) returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare
  v_uid uuid := realisasi._require_uid(); a realisasi.activities;
  v_check jsonb; v_fail jsonb; v_draft uuid; v_mob boolean; v_conf int := 0; v_ts timestamptz := realisasi.now_ts();
begin
  a := realisasi._get_activity(p_id);
  if not realisasi._is_unit_editor(p_id) then perform realisasi._forbidden(); end if;
  if not (a.status = 'draft' or (a.status = 'revision_requested' and a.mobility_status = 'revision_requested')) then
    perform realisasi._state_invalid();
  end if;

  v_check := realisasi._checklist(p_id);
  select jsonb_agg(jsonb_build_object('code', c ->> 'code', 'message', c ->> 'message') order by o) into v_fail
    from jsonb_array_elements(v_check) with ordinality x(c, o) where not (c ->> 'ok')::boolean;
  if v_fail is not null then
    perform realisasi._raise(v_fail -> 0 ->> 'code', v_fail -> 0 ->> 'message', jsonb_build_object('failures', v_fail));
  end if;

  v_mob := realisasi.agenda_is_mobility(a.agenda_id);
  v_draft := realisasi._draft_pset(p_id);

  if v_mob then
    -- an older version still pending is replaced by the new one (one_pending_pset)
    update realisasi.participant_set_versions set status = 'superseded'
     where activity_id = p_id and status = 'pending' and id <> v_draft;
    update realisasi.participant_set_versions set status = 'pending', submitted_by = v_uid, submitted_at = v_ts where id = v_draft;
  elsif v_draft is not null then
    delete from realisasi.participant_students where set_version_id = v_draft;
    delete from realisasi.participant_staff where set_version_id = v_draft;
    delete from realisasi.participant_set_versions where id = v_draft;
  end if;

  update realisasi.activities
     set submitted_at = coalesce(submitted_at, v_ts),
         mobility_status = case when v_mob then 'pending' else 'not_required' end::realisasi.track_status,
         mobility_since = v_ts
   where id = p_id;

  if a.status = 'draft' then
    perform realisasi._log(p_id, 'system', null, 'submit');
  else
    perform realisasi._log(p_id, 'revision', 'mobility', 'resubmit');
  end if;

  if v_mob then
    perform realisasi._notify_team('mobility', 'submission_received',
      case when a.status = 'draft' then 'Perlu diverifikasi: ' else 'Revisi diajukan: ' end || a.code,
      'Kegiatan "' || a.name || '" menunggu Verifikasi Mobilitas.', '/realisasi/verifikasi/mobilitas');
    v_conf := realisasi._scan_conflicts(p_id);
  else
    perform realisasi._notify_unit(a.submitter_unit_id, 'activity_verified', 'Kegiatan tercatat: ' || a.code,
      'Kegiatan "' || a.name || '" sudah tercatat dan dihitung dalam capaian Renstra.', '/realisasi/kegiatan/' || a.id);
  end if;

  select * into a from realisasi.activities where id = p_id;
  return realisasi._status_result(p_id) || jsonb_build_object('is_late', a.is_late, 'conflicts_found', v_conf);
end $$;
