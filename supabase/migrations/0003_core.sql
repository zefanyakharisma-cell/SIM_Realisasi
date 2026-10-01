-- 0003_core: time, settings, errors, business days, chains, labels, role helpers, logging, notifications.

-- Time --------------------------------------------------------------------
create function realisasi.today() returns date
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select coalesce(
    (select (s.value #>> '{}')::date from realisasi.settings s
      where s.key = 'demo_today' and jsonb_typeof(s.value) = 'string'),
    (now() at time zone 'Asia/Jakarta')::date)
$$;

create function realisasi.now_ts() returns timestamptz
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select coalesce(
    (select ((s.value #>> '{}')::date + (now() at time zone 'Asia/Jakarta')::time) at time zone 'Asia/Jakarta'
       from realisasi.settings s where s.key = 'demo_today' and jsonb_typeof(s.value) = 'string'),
    now())
$$;

-- Settings ----------------------------------------------------------------
create function realisasi.setting_int(p_key text) returns int
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select (value #>> '{}')::numeric::int from realisasi.settings where key = p_key
$$;

create function realisasi.setting_num(p_key text) returns numeric
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select (value #>> '{}')::numeric from realisasi.settings where key = p_key
$$;

create function realisasi.settings_json() returns jsonb
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select coalesce(jsonb_object_agg(key, value order by key), '{}'::jsonb)
    from realisasi.settings where key <> 'demo_today'
$$;

-- Errors ------------------------------------------------------------------
create function realisasi._raise(p_code text, p_message text, p_detail jsonb default null) returns void
language plpgsql security definer set search_path = realisasi, public, extensions, pg_temp as $$
begin
  raise exception using errcode = 'P0001', message = p_code || ': ' || p_message,
                        detail = coalesce(p_detail::text, '');
end $$;

create function realisasi._require_uid() returns uuid
language plpgsql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
declare v uuid := auth.uid();
begin
  if v is null or not exists (select 1 from public.profiles where id = v) then
    perform realisasi._raise('AUTH_REQUIRED', 'Sesi tidak valid. Silakan masuk kembali.');
  end if;
  return v;
end $$;

create function realisasi._forbidden() returns void
language sql security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select realisasi._raise('AUTH_FORBIDDEN', 'Anda tidak memiliki akses untuk tindakan ini.')
$$;

create function realisasi._not_found() returns void
language sql security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select realisasi._raise('NOT_FOUND', 'Data tidak ditemukan.')
$$;

create function realisasi._state_invalid() returns void
language sql security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select realisasi._raise('STATE_INVALID', 'Tindakan tidak dapat dilakukan pada status kegiatan saat ini.')
$$;

-- Business days / SLA -----------------------------------------------------
create function realisasi.business_days_between(p_from date, p_to date) returns int
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select case when p_from is null or p_to is null or p_to <= p_from then 0 else
    (select count(*)::int
       from generate_series(p_from + 1, p_to, interval '1 day') g(d)
      where extract(isodow from g.d) < 6
        and not exists (select 1 from realisasi.holidays h where h.day = g.d::date)) end
$$;

create function realisasi._business_days_ago(p_n int) returns date
language plpgsql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
declare v_today date := realisasi.today(); v_d date := realisasi.today();
begin
  while realisasi.business_days_between(v_d, v_today) < p_n loop
    v_d := v_d - 1;
  end loop;
  return v_d;
end $$;

create function realisasi.sla_days(p_since timestamptz) returns int
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select case when p_since is null then null
    else realisasi.business_days_between((p_since at time zone 'Asia/Jakarta')::date, realisasi.today()) end
$$;

create function realisasi.sla_level(p_days int) returns text
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select case when p_days is null then null
              when p_days > realisasi.setting_int('sla_red_days') then 'red'
              when p_days > realisasi.setting_int('sla_yellow_days') then 'yellow'
              else 'ok' end
$$;

-- Renewal chains (Schema §5.1) -------------------------------------------
create function realisasi.chain_root(p_doc int) returns int
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  with recursive up as (
    select id, predecessor_id, 0 as depth from public.documents where id = p_doc
    union all
    select d.id, d.predecessor_id, up.depth + 1 from public.documents d join up on d.id = up.predecessor_id
    where up.depth < 100
  )
  select id from up where predecessor_id is null limit 1
$$;

create function realisasi.chain_current(p_doc int) returns int
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  with recursive down as (
    select id, 0 as depth from public.documents where id = p_doc
    union all
    select d.id, down.depth + 1 from public.documents d join down on d.predecessor_id = down.id
    where down.depth < 100
  )
  select id from down order by depth desc, id desc limit 1
$$;

-- Labels ------------------------------------------------------------------
create function realisasi.semester_label(p_semester_id int) returns text
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select initcap(s.term::text) || ' ' || ay.label
    from realisasi.semesters s join realisasi.academic_years ay on ay.id = s.academic_year_id
   where s.id = p_semester_id
$$;

create function realisasi._snapshot_label(p_kind realisasi.snapshot_kind, p_ay_label text) returns text
language sql immutable set search_path = realisasi, public, extensions, pg_temp as $$
  select case p_kind when 'ganjil_ytd' then 'Ganjil ' || p_ay_label || ' (YTD)'
                     else 'Genap ' || p_ay_label || ' (Setahun)' end
$$;

create function realisasi._fmt_date(p_d date) returns text
language sql immutable set search_path = realisasi, public, extensions, pg_temp as $$
  select to_char(p_d, 'DD') || ' ' ||
         (array['Jan','Feb','Mar','Apr','Mei','Jun','Jul','Agu','Sep','Okt','Nov','Des'])[extract(month from p_d)::int]
         || ' ' || to_char(p_d, 'YYYY')
$$;

create function realisasi._profile_name(p_id uuid) returns text
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select display_name from public.profiles where id = p_id
$$;

-- Role helpers ------------------------------------------------------------
create function realisasi.my_role() returns text
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select app_role from public.profiles where id = auth.uid()
$$;

create function realisasi.my_unit() returns int
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select unit_id from public.profiles where id = auth.uid()
$$;

create function realisasi.in_team(p_team realisasi.team) returns boolean
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select coalesce(realisasi.my_role() = 'io_admin', false)
      or exists (select 1 from realisasi.team_members tm
                  join public.profiles p on p.id = tm.account_id and p.app_role in ('io_staff','io_admin')
                 where tm.account_id = auth.uid() and tm.team = p_team)
$$;

create function realisasi.is_io() returns boolean
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select coalesce(realisasi.my_role() in ('io_staff','io_admin'), false)
$$;

create function realisasi.can_view_activity(p_activity uuid) returns boolean
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select case realisasi.my_role()
    when 'io_admin' then true
    when 'io_staff' then true
    when 'viewer' then exists (select 1 from realisasi.activities a where a.id = p_activity and a.status = 'verified')
    when 'submitter' then exists (select 1 from realisasi.activity_units au
                                   where au.activity_id = p_activity and au.unit_id = realisasi.my_unit())
    else false end
$$;

create function realisasi.can_view_participants(p_activity uuid) returns boolean
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select case
    when realisasi.my_role() = 'io_admin' then true
    when realisasi.my_role() = 'io_staff' then realisasi.in_team('mobility')
    when realisasi.my_role() = 'submitter' then exists (select 1 from realisasi.activity_units au
                                   where au.activity_id = p_activity and au.unit_id = realisasi.my_unit())
    else false end
$$;

create function realisasi._is_unit_editor(p_activity uuid) returns boolean
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select coalesce(realisasi.my_role() = 'io_admin', false)
      or (coalesce(realisasi.my_role() = 'submitter', false)
          and exists (select 1 from realisasi.activities a
                       where a.id = p_activity and a.submitter_unit_id = realisasi.my_unit()))
$$;

create function realisasi.in_frozen_period(p_activity uuid) returns boolean
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select exists (select 1 from realisasi.activities a
                   join realisasi.kpi_snapshots s on s.superseded_by is null
                    and a.start_date between s.window_start and s.window_end
                  where a.id = p_activity)
$$;

create function realisasi.is_late_addition(p_activity uuid) returns boolean
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select exists (select 1 from realisasi.activities a
                   join realisasi.kpi_snapshots s on s.superseded_by is null
                    and a.start_date between s.window_start and s.window_end
                  where a.id = p_activity and a.status = 'verified' and a.verified_at > s.frozen_at)
$$;

-- Permission predicates shared by RPCs and activity_detail.permissions (internal)
-- participant-edit permission (CONTRACTS §3.2 ensure_participant_draft)
create function realisasi._can_edit_participants(p_activity uuid, p_include_io boolean default true) returns boolean
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select exists (select 1 from realisasi.activities a where a.id = p_activity and (
           (realisasi._is_unit_editor(a.id)
             and (a.status = 'draft' or a.mobility_status = 'revision_requested'
                  or (a.partnership_status = 'revision_requested' and a.mobility_status = 'not_required')))
        or (p_include_io and a.status = 'verified' and realisasi.in_team('mobility'))))
$$;

-- file write permission (CONTRACTS §3.3)
create function realisasi._can_write_files(p_activity uuid) returns boolean
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select exists (select 1 from realisasi.activities a where a.id = p_activity and (
           (realisasi._is_unit_editor(a.id) and (a.status = 'draft' or a.partnership_status = 'revision_requested'))
        or (a.status = 'verified' and realisasi.in_team('partnership'))))
$$;

-- View helpers (definer, counts only; granted so security_invoker views can call them)
create function realisasi.activity_linked_count(p_activity uuid) returns int
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select count(*)::int from realisasi.activities o
    join realisasi.activities a on a.id = p_activity and o.event_group_id = a.event_group_id and o.id <> a.id
$$;

create function realisasi.activity_participant_total(p_activity uuid) returns int
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select coalesce((select (select count(*) from realisasi.participant_students s where s.set_version_id = v.id)
                        + (select count(*) from realisasi.participant_staff st where st.set_version_id = v.id)
                     from realisasi.participant_set_versions v
                    where v.activity_id = p_activity and v.status <> 'draft'
                    order by v.version desc limit 1), 0)::int
$$;

-- Logging -----------------------------------------------------------------
create function realisasi._log(p_activity uuid, p_kind realisasi.log_kind, p_track realisasi.team, p_action text,
                               p_note text default null, p_diff jsonb default null) returns bigint
language plpgsql security definer set search_path = realisasi, public, extensions, pg_temp as $$
declare v_id bigint;
begin
  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (p_activity, p_kind, p_track, p_action, auth.uid(), p_note, p_diff,
          case when p_kind = 'update' then realisasi.in_frozen_period(p_activity) else false end,
          realisasi.now_ts())
  returning id into v_id;
  return v_id;
end $$;

-- Notifications -------------------------------------------------------------
create function realisasi._notify(p_recipient uuid, p_kind text, p_title text, p_body text, p_link text) returns void
language plpgsql security definer set search_path = realisasi, public, extensions, pg_temp as $$
declare v_email text;
begin
  select email into v_email from public.profiles where id = p_recipient;
  if v_email is null then return; end if;
  insert into realisasi.notifications (recipient_id, kind, title, body, link, created_at)
  values (p_recipient, p_kind, p_title, p_body, p_link, realisasi.now_ts());
  insert into realisasi.email_outbox (to_email, subject, body, created_at)
  values (v_email, p_title, coalesce(p_body, '') || E'\n\n' || coalesce(p_link, ''), realisasi.now_ts());
end $$;

create function realisasi._notify_many(p_recipients uuid[], p_kind text, p_title text, p_body text, p_link text) returns int
language plpgsql security definer set search_path = realisasi, public, extensions, pg_temp as $$
declare r uuid; n int := 0;
begin
  for r in select distinct x from unnest(p_recipients) x where x is not null order by 1 loop
    perform realisasi._notify(r, p_kind, p_title, p_body, p_link);
    n := n + 1;
  end loop;
  return n;
end $$;

create function realisasi._team_ids(p_team realisasi.team) returns uuid[]
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select coalesce(array_agg(distinct tm.account_id), '{}') from realisasi.team_members tm where tm.team = p_team
$$;

create function realisasi._admin_ids() returns uuid[]
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select coalesce(array_agg(id order by id), '{}') from public.profiles where app_role = 'io_admin'
$$;

create function realisasi._notify_team(p_team realisasi.team, p_kind text, p_title text, p_body text, p_link text) returns void
language sql security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select realisasi._notify_many(realisasi._team_ids(p_team), p_kind, p_title, p_body, p_link);
  select null::void
$$;

create function realisasi._notify_admins(p_kind text, p_title text, p_body text, p_link text) returns void
language sql security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select realisasi._notify_many(realisasi._admin_ids(), p_kind, p_title, p_body, p_link);
  select null::void
$$;

create function realisasi._notify_unit(p_unit_id int, p_kind text, p_title text, p_body text, p_link text) returns void
language sql security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select realisasi._notify_many((select coalesce(array_agg(id), '{}') from public.profiles
                                  where app_role = 'submitter' and unit_id = p_unit_id),
                                p_kind, p_title, p_body, p_link);
  select null::void
$$;

create function realisasi._notify_viewers(p_kind text, p_title text, p_body text, p_link text) returns void
language sql security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select realisasi._notify_many((select coalesce(array_agg(id), '{}') from public.profiles where app_role = 'viewer'),
                                p_kind, p_title, p_body, p_link);
  select null::void
$$;
