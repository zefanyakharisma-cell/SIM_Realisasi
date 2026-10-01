-- 0010_rpc_duplicates_known: event groups (R-32..R-35) and Known Activities register (R-51..R-54).

create function realisasi._require_partnership() returns uuid
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v uuid := realisasi._require_uid();
begin
  if not realisasi.in_team('partnership') then perform realisasi._forbidden(); end if;
  return v;
end $$;

-- merge the groups of two activities into the group of the earlier-created one (internal)
create function realisasi._merge_groups(p_a uuid, p_b uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare a realisasi.activities; b realisasi.activities; v_target uuid; v_source uuid; v_moved uuid[]; v_all uuid[]; x uuid;
        v_log bigint; v_uid uuid := auth.uid();
begin
  -- lock both rows in id order so concurrent link calls cannot deadlock (L7)
  perform 1 from realisasi.activities where id in (p_a, p_b) order by id for update;
  select * into a from realisasi.activities where id = p_a;
  select * into b from realisasi.activities where id = p_b;
  if a.event_group_id = b.event_group_id then
    perform realisasi._raise('DUP_SAME_GROUP', 'Kedua kegiatan sudah berada dalam satu grup kegiatan.');
  end if;
  if (a.created_at, a.code) <= (b.created_at, b.code) then
    v_target := a.event_group_id; v_source := b.event_group_id;
  else
    v_target := b.event_group_id; v_source := a.event_group_id;
  end if;
  select array_agg(id order by code) into v_moved from realisasi.activities where event_group_id = v_source;
  update realisasi.activities set event_group_id = v_target where event_group_id = v_source;
  delete from realisasi.event_groups where id = v_source;
  select array_agg(id order by code) into v_all from realisasi.activities where event_group_id = v_target;
  foreach x in array v_all loop
    v_log := realisasi._log(x, 'verification', 'partnership', 'link_duplicate', p_note,
                            jsonb_build_object('event_group_id', v_target, 'moved', to_jsonb(v_moved)));
    -- linking changes KPI counts of verified activities: flag it as a post-freeze change when frozen (M5, R-31)
    update realisasi.activity_log set in_frozen_period = true
     where id = v_log and exists (select 1 from realisasi.activities z where z.id = x and z.status = 'verified')
       and realisasi.in_frozen_period(x);
  end loop;
  -- open candidates whose pair now shares the group are resolved (L4)
  update realisasi.duplicate_candidates dc set status = 'linked', resolved_by = v_uid, resolved_at = realisasi.now_ts()
   where dc.status = 'open' and dc.activity_a = any(v_all) and dc.activity_b = any(v_all);
  return jsonb_build_object('event_group_id', v_target, 'activity_ids', to_jsonb(v_all));
end $$;

create function realisasi.link_duplicates(p_candidate_id bigint, p_note text default null) returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_partnership(); c realisasi.duplicate_candidates; v_res jsonb;
begin
  select * into c from realisasi.duplicate_candidates where id = p_candidate_id for update;
  if not found then perform realisasi._not_found(); end if;
  if c.status <> 'open' then perform realisasi._state_invalid(); end if;
  if exists (select 1 from realisasi.activities where id in (c.activity_a, c.activity_b) and status in ('draft','rejected')) then
    perform realisasi._state_invalid();                                 -- L4: same rule as link_activities
  end if;
  v_res := realisasi._merge_groups(c.activity_a, c.activity_b, nullif(btrim(p_note), ''));
  update realisasi.duplicate_candidates set status = 'linked', resolved_by = v_uid, resolved_at = realisasi.now_ts()
   where id = p_candidate_id;
  return v_res;
end $$;

create function realisasi.link_activities(p_activity_a uuid, p_activity_b uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_partnership(); a realisasi.activities; b realisasi.activities; v_res jsonb;
begin
  if p_activity_a is null or p_activity_b is null or p_activity_a = p_activity_b then perform realisasi._invalid('activity'); end if;
  select * into a from realisasi.activities where id = p_activity_a;
  if not found then perform realisasi._not_found(); end if;
  select * into b from realisasi.activities where id = p_activity_b;
  if not found then perform realisasi._not_found(); end if;
  if a.status in ('draft','rejected') or b.status in ('draft','rejected') then perform realisasi._state_invalid(); end if;
  v_res := realisasi._merge_groups(a.id, b.id, nullif(btrim(p_note), ''));
  insert into realisasi.duplicate_candidates (activity_a, activity_b, score, status, resolved_by, resolved_at)
  values (least(a.id, b.id), greatest(a.id, b.id), round(similarity(lower(a.name), lower(b.name))::numeric, 2),
          'linked', v_uid, realisasi.now_ts())
  on conflict (activity_a, activity_b) do update set status = 'linked', resolved_by = excluded.resolved_by, resolved_at = excluded.resolved_at;
  return v_res;
end $$;

create function realisasi.dismiss_duplicate(p_candidate_id bigint, p_note text default null) returns void
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_partnership(); c realisasi.duplicate_candidates;
begin
  select * into c from realisasi.duplicate_candidates where id = p_candidate_id for update;
  if not found then perform realisasi._not_found(); end if;
  if c.status <> 'open' then perform realisasi._state_invalid(); end if;
  update realisasi.duplicate_candidates set status = 'dismissed', resolved_by = v_uid, resolved_at = realisasi.now_ts()
   where id = p_candidate_id;
  perform realisasi._log(c.activity_a, 'verification', 'partnership', 'dismiss_duplicate', nullif(btrim(p_note), ''),
                         jsonb_build_object('candidate_id', c.id));
  perform realisasi._log(c.activity_b, 'verification', 'partnership', 'dismiss_duplicate', nullif(btrim(p_note), ''),
                         jsonb_build_object('candidate_id', c.id));
end $$;

create function realisasi.unlink_activity(p_activity uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_uid(); a realisasi.activities; v_new uuid; r record; v_first boolean := true;
begin
  if realisasi.my_role() is distinct from 'io_admin' then
    perform realisasi._raise('R34_UNLINK_ADMIN_ONLY', 'Hanya Admin IO yang dapat membatalkan tautan duplikat.');
  end if;
  a := realisasi._get_activity(p_activity);
  if nullif(btrim(p_note), '') is null then
    perform realisasi._raise('VALIDATION_REQUIRED', 'Kolom wajib belum diisi: note.', '{"fields":["note"]}');
  end if;
  if realisasi.activity_linked_count(p_activity) = 0 then perform realisasi._state_invalid(); end if;
  perform 1 from realisasi.activities where event_group_id = a.event_group_id order by id for update;
  insert into realisasi.event_groups (created_by, created_at) values (v_uid, realisasi.now_ts()) returning id into v_new;
  update realisasi.activities set event_group_id = v_new where id = p_activity;
  update realisasi.duplicate_candidates set status = 'dismissed', resolved_by = v_uid, resolved_at = realisasi.now_ts()
   where status = 'linked' and (activity_a = p_activity or activity_b = p_activity);
  perform realisasi._log(p_activity, 'update', 'partnership', 'unlink_duplicate', btrim(p_note),
                         jsonb_build_object('event_group_id', jsonb_build_array(a.event_group_id, v_new)));
  -- L4: the remaining members stay together only while connected by 'linked' candidates. The component with the
  -- earliest-created member keeps the old group; every other component gets a new group (logged as an unlink).
  for r in
    with recursive mem as (
      select id, created_at, code from realisasi.activities where event_group_id = a.event_group_id
    ), edge as (
      select dc.activity_a x, dc.activity_b y from realisasi.duplicate_candidates dc
       where dc.status = 'linked' and dc.activity_a in (select id from mem) and dc.activity_b in (select id from mem)
      union all
      select dc.activity_b, dc.activity_a from realisasi.duplicate_candidates dc
       where dc.status = 'linked' and dc.activity_a in (select id from mem) and dc.activity_b in (select id from mem)
    ), reach(src, dst) as (
      select id, id from mem
      union
      select reach.src, edge.y from reach join edge on edge.x = reach.dst
    ), comp as (
      select r1.src as id, (array_agg(m.id order by m.created_at, m.code))[1] as rep, min(m.created_at) as first_at, min(m.code) as first_code
        from reach r1 join mem m on m.id = r1.dst group by r1.src
    )
    select rep, array_agg(id order by id) as ids, min(first_at) as first_at, min(first_code) as first_code
      from comp group by rep order by min(first_at), min(first_code)
  loop
    if v_first then v_first := false; continue; end if;     -- earliest component keeps the old group
    insert into realisasi.event_groups (created_by, created_at) values (v_uid, realisasi.now_ts()) returning id into v_new;
    update realisasi.activities set event_group_id = v_new where id = any(r.ids);
    perform realisasi._log(x, 'update', 'partnership', 'unlink_duplicate', btrim(p_note),
                           jsonb_build_object('event_group_id', jsonb_build_array(a.event_group_id, v_new), 'split_from', p_activity))
      from unnest(r.ids) x;
  end loop;
  return jsonb_build_object('event_group_id', (select event_group_id from realisasi.activities where id = p_activity),
                            'activity_ids', jsonb_build_array(p_activity));
end $$;

-- Known activities ---------------------------------------------------------------
create function realisasi._known_values(p_data jsonb, p_old realisasi.known_activities) returns realisasi.known_activities
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare k realisasi.known_activities := p_old; v_missing text[] := '{}';
begin
  if p_data is null or jsonb_typeof(p_data) <> 'object' then perform realisasi._invalid('payload'); end if;
  if p_data ? 'title' then k.title := realisasi._jtext(p_data, 'title'); end if;
  if p_data ? 'activity_date' then
    begin k.activity_date := nullif(p_data ->> 'activity_date', '')::date; exception when others then perform realisasi._invalid('activity_date'); end;
  end if;
  if p_data ? 'unit_id' then
    begin k.unit_id := nullif(p_data ->> 'unit_id', '')::int; exception when others then perform realisasi._invalid('unit_id'); end;
  end if;
  if p_data ? 'partner_name' then k.partner_name := realisasi._jtext(p_data, 'partner_name'); end if;
  if p_data ? 'country_code' then k.country_code := upper(realisasi._jtext(p_data, 'country_code')); end if;
  if p_data ? 'is_international' then
    begin k.is_international := (p_data ->> 'is_international')::boolean; exception when others then perform realisasi._invalid('is_international'); end;
  end if;
  if p_data ? 'source' then
    begin k.source := realisasi._jtext(p_data, 'source')::realisasi.known_source; exception when others then perform realisasi._invalid('source'); end;
  end if;
  if p_data ? 'source_reference' then k.source_reference := realisasi._jtext(p_data, 'source_reference'); end if;
  if p_data ? 'notes' then k.notes := realisasi._jtext(p_data, 'notes'); end if;

  if k.title is null then v_missing := v_missing || 'title'::text; end if;
  if k.activity_date is null then v_missing := v_missing || 'activity_date'::text; end if;
  if k.is_international is null then v_missing := v_missing || 'is_international'::text; end if;
  if k.source is null then v_missing := v_missing || 'source'::text; end if;
  if cardinality(v_missing) > 0 then
    perform realisasi._raise('VALIDATION_REQUIRED', 'Kolom wajib belum diisi: ' || array_to_string(v_missing, ', ') || '.',
                             jsonb_build_object('fields', to_jsonb(v_missing)));
  end if;
  if k.unit_id is not null and not exists (select 1 from kerjasama.units where id = k.unit_id) then perform realisasi._invalid('unit_id'); end if;
  if k.country_code is not null and not exists (select 1 from kerjasama.countries where code = k.country_code) then
    perform realisasi._invalid('country_code');
  end if;
  return k;
end $$;

create function realisasi.create_known_activity(p_data jsonb) returns bigint
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_partnership(); k realisasi.known_activities; v_id bigint;
begin
  k := realisasi._known_values(p_data, null);
  insert into realisasi.known_activities (title, activity_date, unit_id, partner_name, country_code, is_international,
              source, source_reference, notes, created_by, created_at)
  values (k.title, k.activity_date, k.unit_id, k.partner_name, k.country_code, k.is_international,
          k.source, k.source_reference, k.notes, v_uid, realisasi.now_ts())
  returning id into v_id;
  return v_id;
end $$;

create function realisasi._get_known(p_id bigint) returns realisasi.known_activities
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare k realisasi.known_activities;
begin
  select * into k from realisasi.known_activities where id = p_id for update;
  if not found then perform realisasi._not_found(); end if;
  return k;
end $$;

create function realisasi.update_known_activity(p_id bigint, p_data jsonb) returns void
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_partnership(); k realisasi.known_activities;
begin
  k := realisasi._get_known(p_id);
  if k.status = 'matched' then perform realisasi._state_invalid(); end if;
  k := realisasi._known_values(p_data, k);
  update realisasi.known_activities
     set title = k.title, activity_date = k.activity_date, unit_id = k.unit_id, partner_name = k.partner_name,
         country_code = k.country_code, is_international = k.is_international, source = k.source,
         source_reference = k.source_reference, notes = k.notes
   where id = p_id;
end $$;

create function realisasi.known_match_suggestions(p_id bigint) returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare k realisasi.known_activities;
begin
  perform realisasi._require_uid();
  if not realisasi.is_io() then perform realisasi._forbidden(); end if;
  select * into k from realisasi.known_activities where id = p_id;
  if not found then perform realisasi._not_found(); end if;
  return coalesce((select jsonb_agg(row_to_json(s)::jsonb order by s.score desc, s.code) from (
      select a.id as activity_id, a.code, a.name, a.start_date, a.end_date,
             coalesce((select array_agg(u.name order by au.is_submitter desc, u.name) from realisasi.activity_units au
                         join kerjasama.units u on u.id = au.unit_id where au.activity_id = a.id), '{}') as unit_names,
             a.status, round(similarity(lower(a.name), lower(k.title))::numeric, 2) as score
        from realisasi.activities a
       where a.status not in ('draft','rejected')
         and (k.unit_id is null or exists (select 1 from realisasi.activity_units au where au.activity_id = a.id and au.unit_id = k.unit_id))
         -- L9 (R-52): the known date lies within the activity span widened by the window
         and k.activity_date between a.start_date - realisasi.setting_int('known_match_window_days')
                                 and a.end_date + realisasi.setting_int('known_match_window_days')
         and similarity(lower(a.name), lower(k.title)) >= realisasi.setting_num('known_name_similarity')
       order by score desc, a.code limit 5) s), '[]'::jsonb);
end $$;

create function realisasi.match_known_activity(p_id bigint, p_activity uuid) returns void
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_partnership(); k realisasi.known_activities;
begin
  k := realisasi._get_known(p_id);
  if k.status = 'matched' then perform realisasi._raise('R53_ALREADY_MATCHED', 'Entri ini sudah dicocokkan dengan kegiatan SIM.'); end if;
  if k.status = 'dismissed' then perform realisasi._state_invalid(); end if;
  if not exists (select 1 from realisasi.activities where id = p_activity) then perform realisasi._not_found(); end if;
  if exists (select 1 from realisasi.activities where id = p_activity and status in ('draft','rejected')) then
    perform realisasi._state_invalid();
  end if;
  update realisasi.known_activities set status = 'matched', matched_activity_id = p_activity where id = p_id;
end $$;

create function realisasi.unmatch_known_activity(p_id bigint) returns void
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_partnership(); k realisasi.known_activities;
begin
  k := realisasi._get_known(p_id);
  if k.status <> 'matched' then perform realisasi._state_invalid(); end if;
  update realisasi.known_activities set status = 'unmatched', matched_activity_id = null where id = p_id;
end $$;

create function realisasi.dismiss_known_activity(p_id bigint, p_note text) returns void
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_partnership(); k realisasi.known_activities;
begin
  k := realisasi._get_known(p_id);
  if k.status <> 'unmatched' then perform realisasi._state_invalid(); end if;
  update realisasi.known_activities
     set status = 'dismissed',
         notes = case when nullif(btrim(p_note), '') is null then notes
                      else concat_ws(E'\n', notes, 'Diabaikan: ' || btrim(p_note)) end
   where id = p_id;
end $$;

create function realisasi.nudge_known_activity(p_id bigint) returns timestamptz
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_partnership(); k realisasi.known_activities;
        v_days int := realisasi.setting_int('nudge_resend_days'); v_now timestamptz := realisasi.now_ts();
begin
  k := realisasi._get_known(p_id);
  if k.status <> 'unmatched' then perform realisasi._state_invalid(); end if;
  if k.unit_id is null then perform realisasi._raise('R54_NO_UNIT', 'Entri belum memiliki unit; tentukan unit sebelum mengingatkan.'); end if;
  if k.nudged_at is not null and k.nudged_at > v_now - make_interval(days => v_days) then
    perform realisasi._raise('R54_NUDGE_TOO_SOON',
      format('Pengingat sudah dikirim pada %s; dapat dikirim ulang setelah %s hari.',
             realisasi._fmt_date((k.nudged_at at time zone 'Asia/Jakarta')::date), v_days),
      jsonb_build_object('nudged_at', k.nudged_at, 'resend_days', v_days));
  end if;
  perform realisasi._notify_unit(k.unit_id, 'known_nudge', 'Mohon laporkan: ' || k.title,
    'IO mencatat kegiatan "' || k.title || '" (' || realisasi._fmt_date(k.activity_date) || ') yang belum dilaporkan di SIM Realisasi.',
    '/realisasi/kegiatan/baru');
  update realisasi.known_activities set nudged_at = v_now where id = p_id;
  return v_now;
end $$;
