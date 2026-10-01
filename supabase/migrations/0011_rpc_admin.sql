-- 0011_rpc_admin: settings, calendar, Jenis, holidays (io_admin) + notifications / export log.

create function realisasi._require_admin() returns uuid
language plpgsql security definer set search_path = realisasi, public, extensions, pg_temp as $$
declare v uuid := realisasi._require_uid();
begin
  if realisasi.my_role() is distinct from 'io_admin' then perform realisasi._forbidden(); end if;
  return v;
end $$;

create function realisasi._settings_invalid(p_key text) returns void
language sql security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select realisasi._raise('SETTINGS_INVALID', format('Pengaturan %s tidak valid.', p_key), jsonb_build_object('key', p_key))
$$;

create function realisasi.update_settings(p_values jsonb) returns jsonb
language plpgsql security definer set search_path = realisasi, public, extensions, pg_temp as $$
declare v_uid uuid := realisasi._require_admin(); k text; v jsonb; v_merged jsonb;
  c_int text[] := array['grace_period_months','reporting_deadline_days','sla_yellow_days','sla_red_days',
                        'revision_reminder_days','revision_escalate_days','dup_date_window_days',
                        'known_match_window_days','nudge_resend_days','deadline_reminder_before_days'];
  c_num text[] := array['dup_name_similarity','known_name_similarity'];
begin
  if p_values is null or jsonb_typeof(p_values) <> 'object' then perform realisasi._settings_invalid('payload'); end if;
  for k, v in select * from jsonb_each(p_values) loop
    if k = any(c_int) then
      if jsonb_typeof(v) <> 'number' or (v #>> '{}')::numeric < 0 or (v #>> '{}')::numeric <> trunc((v #>> '{}')::numeric) then
        perform realisasi._settings_invalid(k);
      end if;
    elsif k = any(c_num) then
      if jsonb_typeof(v) <> 'number' or (v #>> '{}')::numeric <= 0 or (v #>> '{}')::numeric > 1 then
        perform realisasi._settings_invalid(k);
      end if;
    elsif k = 'demo_today' then
      if jsonb_typeof(v) not in ('null','string') then perform realisasi._settings_invalid(k); end if;
      if jsonb_typeof(v) = 'string' then
        begin perform (v #>> '{}')::date; exception when others then perform realisasi._settings_invalid(k); end;
        if (v #>> '{}') !~ '^\d{4}-\d{2}-\d{2}$' then perform realisasi._settings_invalid(k); end if;
      end if;
    else
      perform realisasi._settings_invalid(k);
    end if;
  end loop;
  select jsonb_object_agg(key, value) || p_values into v_merged from realisasi.settings;
  if (v_merged ->> 'sla_red_days')::int <= (v_merged ->> 'sla_yellow_days')::int then perform realisasi._settings_invalid('sla_red_days'); end if;
  if (v_merged ->> 'revision_escalate_days')::int <= (v_merged ->> 'revision_reminder_days')::int then
    perform realisasi._settings_invalid('revision_escalate_days');
  end if;
  insert into realisasi.settings (key, value, updated_by)
  select key, value, v_uid from jsonb_each(p_values)
  on conflict (key) do update set value = excluded.value, updated_by = excluded.updated_by;
  return (select jsonb_object_agg(key, value order by key) from realisasi.settings);
end $$;

-- re-derive academic year / semester of every activity after calendar changes
create function realisasi._rederive_periods() returns int
language plpgsql security definer set search_path = realisasi, public, extensions, pg_temp as $$
declare n int;
begin
  with calc as (
    select a.id,
           (select ay.id from realisasi.academic_years ay where a.start_date between ay.start_date and ay.end_date
             order by ay.start_date limit 1) as ay_id,
           (select s.id from realisasi.semesters s where a.start_date between s.start_date and s.end_date
             order by s.start_date limit 1) as sem_id
      from realisasi.activities a)
  update realisasi.activities a set academic_year_id = c.ay_id, semester_id = c.sem_id
    from calc c
   where c.id = a.id and (a.academic_year_id is distinct from c.ay_id or a.semester_id is distinct from c.sem_id);
  get diagnostics n = row_count;
  return n;
end $$;

create function realisasi._cal_invalid() returns void
language sql security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select realisasi._raise('CAL_INVALID_RANGE', 'Rentang tanggal kalender tidak valid atau tumpang tindih.')
$$;

create function realisasi.upsert_academic_year(p_id int, p_label text, p_start date, p_end date) returns int
language plpgsql security definer set search_path = realisasi, public, extensions, pg_temp as $$
declare v_uid uuid := realisasi._require_admin(); v_id int; v_gend date;
begin
  if nullif(btrim(p_label), '') is null then
    perform realisasi._raise('VALIDATION_REQUIRED', 'Kolom wajib belum diisi: label.', '{"fields":["label"]}');
  end if;
  if p_start is null or p_end is null or p_end <= p_start then perform realisasi._cal_invalid(); end if;
  if exists (select 1 from realisasi.academic_years where id is distinct from p_id
               and daterange(start_date, end_date, '[]') && daterange(p_start, p_end, '[]')) then
    perform realisasi._cal_invalid();
  end if;
  if exists (select 1 from realisasi.academic_years where id is distinct from p_id and label = btrim(p_label)) then
    perform realisasi._invalid('label');
  end if;
  if p_id is null then
    insert into realisasi.academic_years (label, start_date, end_date) values (btrim(p_label), p_start, p_end) returning id into v_id;
    v_gend := (p_start + interval '6 months' - interval '1 day')::date;
    if v_gend >= p_end then perform realisasi._cal_invalid(); end if;
    insert into realisasi.semesters (academic_year_id, term, start_date, end_date, cutoff_date) values
      (v_id, 'ganjil', p_start, v_gend, v_gend + 30),
      (v_id, 'genap', v_gend + 1, p_end, p_end + 30);
  else
    if not exists (select 1 from realisasi.academic_years where id = p_id) then perform realisasi._not_found(); end if;
    if exists (select 1 from realisasi.semesters where academic_year_id = p_id and (start_date < p_start or end_date > p_end)) then
      perform realisasi._cal_invalid();
    end if;
    update realisasi.academic_years set label = btrim(p_label), start_date = p_start, end_date = p_end where id = p_id;
    v_id := p_id;
  end if;
  perform realisasi._rederive_periods();
  return v_id;
end $$;

create function realisasi.upsert_semester(p_id int, p_ay_id int, p_term realisasi.semester_term,
                                          p_start date, p_end date, p_cutoff date) returns int
language plpgsql security definer set search_path = realisasi, public, extensions, pg_temp as $$
declare v_uid uuid := realisasi._require_admin(); ay realisasi.academic_years; v_id int;
begin
  select * into ay from realisasi.academic_years where id = p_ay_id;
  if not found then perform realisasi._not_found(); end if;
  if p_term is null or p_start is null or p_end is null or p_cutoff is null or p_end < p_start or p_cutoff < p_end
     or p_start < ay.start_date or p_end > ay.end_date then
    perform realisasi._cal_invalid();
  end if;
  if exists (select 1 from realisasi.semesters where id is distinct from p_id
               and daterange(start_date, end_date, '[]') && daterange(p_start, p_end, '[]')) then
    perform realisasi._cal_invalid();
  end if;
  if exists (select 1 from realisasi.semesters where id is distinct from p_id and academic_year_id = p_ay_id and term = p_term) then
    perform realisasi._cal_invalid();
  end if;
  if p_id is null then
    insert into realisasi.semesters (academic_year_id, term, start_date, end_date, cutoff_date)
    values (p_ay_id, p_term, p_start, p_end, p_cutoff) returning id into v_id;
  else
    update realisasi.semesters set academic_year_id = p_ay_id, term = p_term, start_date = p_start, end_date = p_end,
                                   cutoff_date = p_cutoff where id = p_id returning id into v_id;
    if v_id is null then perform realisasi._not_found(); end if;
  end if;
  perform realisasi._rederive_periods();
  return v_id;
end $$;

create function realisasi.upsert_activity_type(p_id int, p_data jsonb) returns int
language plpgsql security definer set search_path = realisasi, public, extensions, pg_temp as $$
declare v_uid uuid := realisasi._require_admin(); t realisasi.activity_types; v_id int;
begin
  if p_data is null or jsonb_typeof(p_data) <> 'object' then perform realisasi._invalid('payload'); end if;
  if p_id is not null then
    select * into t from realisasi.activity_types where id = p_id;
    if not found then perform realisasi._not_found(); end if;
  else
    t.direction := 'none'; t.counts_as_mobility := false; t.counts_for_s1 := true; t.requires_mobility_review := false;
    t.is_active := true; t.sort_order := coalesce((select max(sort_order) + 1 from realisasi.activity_types), 1);
  end if;
  begin
    if p_data ? 'name' then t.name := realisasi._jtext(p_data, 'name'); end if;
    if p_data ? 'direction' then t.direction := (p_data ->> 'direction')::realisasi.direction; end if;
    if p_data ? 'counts_as_mobility' then t.counts_as_mobility := (p_data ->> 'counts_as_mobility')::boolean; end if;
    if p_data ? 'counts_for_s1' then t.counts_for_s1 := (p_data ->> 'counts_for_s1')::boolean; end if;
    if p_data ? 'requires_mobility_review' then t.requires_mobility_review := (p_data ->> 'requires_mobility_review')::boolean; end if;
    if p_data ? 'is_active' then t.is_active := (p_data ->> 'is_active')::boolean; end if;
    if p_data ? 'sort_order' then t.sort_order := (p_data ->> 'sort_order')::int; end if;
  exception when others then
    perform realisasi._invalid('activity_type');
  end;
  if t.name is null then perform realisasi._raise('VALIDATION_REQUIRED', 'Kolom wajib belum diisi: name.', '{"fields":["name"]}'); end if;
  if t.direction is null or t.counts_as_mobility is null or t.counts_for_s1 is null or t.requires_mobility_review is null
     or t.is_active is null then perform realisasi._invalid('activity_type'); end if;
  if exists (select 1 from realisasi.activity_types where name = t.name and id is distinct from p_id) then perform realisasi._invalid('name'); end if;
  if p_id is null then
    insert into realisasi.activity_types (name, direction, counts_as_mobility, counts_for_s1, requires_mobility_review, is_active, sort_order)
    values (t.name, t.direction, t.counts_as_mobility, t.counts_for_s1, t.requires_mobility_review, t.is_active, t.sort_order)
    returning id into v_id;
  else
    update realisasi.activity_types set name = t.name, direction = t.direction, counts_as_mobility = t.counts_as_mobility,
           counts_for_s1 = t.counts_for_s1, requires_mobility_review = t.requires_mobility_review, is_active = t.is_active,
           sort_order = t.sort_order where id = p_id;
    v_id := p_id;
  end if;
  return v_id;
end $$;

create function realisasi.upsert_holiday(p_day date, p_name text) returns void
language plpgsql security definer set search_path = realisasi, public, extensions, pg_temp as $$
declare v_uid uuid := realisasi._require_admin();
begin
  if p_day is null or nullif(btrim(p_name), '') is null then
    perform realisasi._raise('VALIDATION_REQUIRED', 'Kolom wajib belum diisi: day, name.', '{"fields":["day","name"]}');
  end if;
  insert into realisasi.holidays (day, name) values (p_day, btrim(p_name)) on conflict (day) do update set name = excluded.name;
end $$;

create function realisasi.delete_holiday(p_day date) returns void
language plpgsql security definer set search_path = realisasi, public, extensions, pg_temp as $$
declare v_uid uuid := realisasi._require_admin();
begin
  delete from realisasi.holidays where day = p_day;
  if not found then perform realisasi._not_found(); end if;
end $$;

create function realisasi.mark_notifications_read(p_ids bigint[] default null) returns int
language plpgsql security definer set search_path = realisasi, public, extensions, pg_temp as $$
declare v_uid uuid := realisasi._require_uid(); n int;
begin
  update realisasi.notifications set read_at = realisasi.now_ts()
   where recipient_id = v_uid and read_at is null and (p_ids is null or id = any(p_ids));
  get diagnostics n = row_count;
  return n;
end $$;

create function realisasi.log_export(p_kind text, p_filters jsonb, p_row_count int, p_contains_personal boolean) returns bigint
language plpgsql security definer set search_path = realisasi, public, extensions, pg_temp as $$
declare v_uid uuid := realisasi._require_uid(); v_id bigint;
begin
  if nullif(btrim(p_kind), '') is null then perform realisasi._invalid('kind'); end if;
  insert into realisasi.export_log (actor_id, export_kind, filters, row_count, contains_personal_data, created_at)
  values (v_uid, p_kind, p_filters, p_row_count, coalesce(p_contains_personal, false), realisasi.now_ts())
  returning id into v_id;
  return v_id;
end $$;
