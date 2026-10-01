-- 0003_core: time, settings, errors, business days, chains, labels, role helpers, logging, notifications.

-- Time --------------------------------------------------------------------
-- demo_today (time travel) only applies when the deployment flag demo_time_travel is enabled (M9).
-- The flag lives in realisasi.deployment_flags, which no RPC writes; the demo seed enables it, production leaves it absent/false.
create function realisasi.demo_time_travel_enabled() returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce((select f.enabled from realisasi.deployment_flags f where f.key = 'demo_time_travel'), false)
$$;

create function realisasi._demo_today() returns date
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select (s.value #>> '{}')::date from realisasi.settings s
   where s.key = 'demo_today' and jsonb_typeof(s.value) = 'string' and realisasi.demo_time_travel_enabled()
$$;

create function realisasi.today() returns date
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce(realisasi._demo_today(), (now() at time zone 'Asia/Jakarta')::date)
$$;

create function realisasi.now_ts() returns timestamptz
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce((select (d + (now() at time zone 'Asia/Jakarta')::time) at time zone 'Asia/Jakarta'
                     from realisasi._demo_today() d where d is not null), now())
$$;

-- System caller = no JWT subject AND not running as the API roles (pg_cron, seeds, psql as owner).
-- An `authenticated` connection whose claims are empty is NOT the system (M4).
create function realisasi._is_system_caller() returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select auth.uid() is null
     and coalesce(nullif(current_setting('role', true), ''), 'none') not in ('authenticated', 'anon')
$$;

-- Settings ----------------------------------------------------------------
create function realisasi.setting_int(p_key text) returns int
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select (value #>> '{}')::numeric::int from realisasi.settings where key = p_key
$$;

create function realisasi.setting_num(p_key text) returns numeric
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select (value #>> '{}')::numeric from realisasi.settings where key = p_key
$$;

create function realisasi.settings_json() returns jsonb
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce(jsonb_object_agg(key, value order by key), '{}'::jsonb)
    from realisasi.settings where key <> 'demo_today'
$$;

-- Errors ------------------------------------------------------------------
create function realisasi._raise(p_code text, p_message text, p_detail jsonb default null) returns void
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
begin
  raise exception using errcode = 'P0001', message = p_code || ': ' || p_message,
                        detail = coalesce(p_detail::text, '');
end $$;

create function realisasi._require_uid() returns uuid
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v uuid := auth.uid();
begin
  if v is null or not exists (select 1 from public.profiles where id = v) then
    perform realisasi._raise('AUTH_REQUIRED', 'Sesi tidak valid. Silakan masuk kembali.');
  end if;
  return v;
end $$;

create function realisasi._forbidden() returns void
language sql security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select realisasi._raise('AUTH_FORBIDDEN', 'Anda tidak memiliki akses untuk tindakan ini.')
$$;

create function realisasi._not_found() returns void
language sql security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select realisasi._raise('NOT_FOUND', 'Data tidak ditemukan.')
$$;

create function realisasi._state_invalid() returns void
language sql security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select realisasi._raise('STATE_INVALID', 'Tindakan tidak dapat dilakukan pada status kegiatan saat ini.')
$$;

-- Business days / SLA -----------------------------------------------------
-- closed form: weekdays in (p_from, p_to] minus weekday holidays (no per-day series; M10)
create function realisasi.business_days_between(p_from date, p_to date) returns int
language sql stable parallel safe security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select case when p_from is null or p_to is null or p_to <= p_from then 0 else (
    select (5 * (n / 7)
            + (select count(*) from generate_series(1, n % 7) k where extract(isodow from p_from + 7 * (n / 7) + k) < 6)
            - (select count(*) from realisasi.holidays h where h.day > p_from and h.day <= p_to and extract(isodow from h.day) < 6))::int
      from (select p_to - p_from as n) x) end
$$;

create function realisasi._business_days_ago(p_n int) returns date
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_today date := realisasi.today(); v_d date := realisasi.today();
begin
  while realisasi.business_days_between(v_d, v_today) < p_n loop
    v_d := v_d - 1;
  end loop;
  return v_d;
end $$;

create function realisasi.sla_days(p_since timestamptz) returns int
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select case when p_since is null then null
    else realisasi.business_days_between((p_since at time zone 'Asia/Jakarta')::date, realisasi.today()) end
$$;

create function realisasi.sla_level(p_days int) returns text
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select case when p_days is null then null
              when p_days > realisasi.setting_int('sla_red_days') then 'red'
              when p_days > realisasi.setting_int('sla_yellow_days') then 'yellow'
              else 'ok' end
$$;

-- Renewal chains (Schema §5.1) -------------------------------------------
create function realisasi.chain_root(p_doc int) returns int
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  with recursive up as (
    select id, predecessor_id, 0 as depth from public.documents where id = p_doc
    union all
    select d.id, d.predecessor_id, up.depth + 1 from public.documents d join up on d.id = up.predecessor_id
    where up.depth < 100
  )
  select id from up where predecessor_id is null limit 1
$$;

create function realisasi.chain_current(p_doc int) returns int
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  with recursive down as (
    select id, 0 as depth from public.documents where id = p_doc
    union all
    select d.id, down.depth + 1 from public.documents d join down on d.predecessor_id = down.id
    where down.depth < 100
  )
  select id from down order by depth desc, id desc limit 1
$$;

-- every document with its chain root and depth, in one recursive pass (H6; chain_root() per document is O(docs x depth))
create function realisasi._chain_map() returns table(doc_id int, root_id int, depth int)
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  with recursive m as (
    select d.id as doc_id, d.id as root_id, 0 as depth from public.documents d where d.predecessor_id is null
    union all
    select d.id, m.root_id, m.depth + 1 from public.documents d join m on d.predecessor_id = m.doc_id where m.depth < 100
  )
  select doc_id, root_id, depth from m
$$;

-- Labels ------------------------------------------------------------------
create function realisasi.semester_label(p_semester_id int) returns text
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select initcap(s.term::text) || ' ' || ay.label
    from realisasi.semesters s join realisasi.academic_years ay on ay.id = s.academic_year_id
   where s.id = p_semester_id
$$;

create function realisasi._snapshot_label(p_kind realisasi.snapshot_kind, p_ay_label text) returns text
language sql immutable set search_path = realisasi, extensions, public, pg_temp as $$
  select case p_kind when 'ganjil_ytd' then 'Ganjil ' || p_ay_label || ' (YTD)'
                     else 'Genap ' || p_ay_label || ' (Setahun)' end
$$;

create function realisasi._fmt_date(p_d date) returns text
language sql immutable set search_path = realisasi, extensions, public, pg_temp as $$
  select to_char(p_d, 'DD') || ' ' ||
         (array['Jan','Feb','Mar','Apr','Mei','Jun','Jul','Agu','Sep','Okt','Nov','Des'])[extract(month from p_d)::int]
         || ' ' || to_char(p_d, 'YYYY')
$$;

create function realisasi._profile_name(p_id uuid) returns text
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select display_name from public.profiles where id = p_id
$$;

-- Role helpers ------------------------------------------------------------
create function realisasi.my_role() returns text
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select app_role from public.profiles where id = auth.uid()
$$;

create function realisasi.my_unit() returns int
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select unit_id from public.profiles where id = auth.uid()
$$;

create function realisasi.in_team(p_team realisasi.team) returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce(realisasi.my_role() = 'io_admin', false)
      or exists (select 1 from realisasi.team_members tm
                  join public.profiles p on p.id = tm.account_id and p.app_role in ('io_staff','io_admin')
                 where tm.account_id = auth.uid() and tm.team = p_team)
$$;

create function realisasi.is_io() returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce(realisasi.my_role() in ('io_staff','io_admin'), false)
$$;

create function realisasi.can_view_activity(p_activity uuid) returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select case realisasi.my_role()
    when 'io_admin' then true
    when 'io_staff' then true
    when 'viewer' then exists (select 1 from realisasi.activities a where a.id = p_activity and a.status = 'verified')
    when 'submitter' then exists (select 1 from realisasi.activity_units au
                                   where au.activity_id = p_activity and au.unit_id = realisasi.my_unit())
    else false end
$$;

create function realisasi.can_view_participants(p_activity uuid) returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select case
    when realisasi.my_role() = 'io_admin' then true
    when realisasi.my_role() = 'io_staff' then realisasi.in_team('mobility')
    when realisasi.my_role() = 'submitter' then exists (select 1 from realisasi.activity_units au
                                   where au.activity_id = p_activity and au.unit_id = realisasi.my_unit())
    else false end
$$;

-- Set-returning helpers for RLS policies: evaluated once per statement as hashed subplans (M10)
-- activities of the caller's unit (submitter only; own + co-unit)
create function realisasi.my_activity_ids() returns setof uuid
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select au.activity_id from realisasi.activity_units au
   where au.unit_id = (select realisasi.my_unit()) and (select realisasi.my_role()) = 'submitter'
$$;

-- activities visible to a non-IO caller (viewer: verified; submitter: own + co-unit). IO is handled by is_io() in the policy.
create function realisasi.visible_activity_ids() returns setof uuid
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select a.id from realisasi.activities a where (select realisasi.my_role()) = 'viewer' and a.status = 'verified'
  union all
  select realisasi.my_activity_ids()
$$;

-- participant set versions whose rows a submitter may read
create function realisasi.my_pset_ids() returns setof uuid
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select v.id from realisasi.participant_set_versions v where v.activity_id in (select realisasi.my_activity_ids())
$$;

-- caller may read participant identifiers of every activity they can see (io_admin, mobility team, submitters for own/co-unit)
create function realisasi.sees_participant_identifiers() returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce(realisasi.my_role() in ('io_admin','submitter'), false) or realisasi.in_team('mobility')
$$;

-- participant identifiers in log diffs replaced by counts (M6: Partnership/viewers see counts only)
create function realisasi._mask_log_diff(p jsonb) returns jsonb
language sql immutable set search_path = realisasi, extensions, public, pg_temp as $$
  select case when p is null or jsonb_typeof(p) <> 'object' then p else
    (p - 'students' - 'staff' - 'row_notes')
    || case when jsonb_typeof(p -> 'students') = 'object' then jsonb_build_object('students', jsonb_build_object(
           'added', coalesce(jsonb_array_length(nullif(p -> 'students' -> 'added', 'null')), 0),
           'removed', coalesce(jsonb_array_length(nullif(p -> 'students' -> 'removed', 'null')), 0))) else '{}'::jsonb end
    || case when jsonb_typeof(p -> 'staff') = 'object' then jsonb_build_object('staff', jsonb_build_object(
           'added', coalesce(jsonb_array_length(nullif(p -> 'staff' -> 'added', 'null')), 0),
           'removed', coalesce(jsonb_array_length(nullif(p -> 'staff' -> 'removed', 'null')), 0))) else '{}'::jsonb end
    || case when jsonb_typeof(p -> 'row_notes') = 'array' then jsonb_build_object('row_notes', jsonb_array_length(p -> 'row_notes')) else '{}'::jsonb end
  end
$$;

-- participant set version that counted for an activity at p_as_of (M2): the latest approved/superseded version
-- reviewed (approved) by then; falls back to the current approved version. p_as_of null = current approved.
create function realisasi._pset_as_of(p_activity uuid, p_as_of timestamptz) returns uuid
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce(
    (select v.id from realisasi.participant_set_versions v
      where p_as_of is not null and v.activity_id = p_activity and v.status in ('approved','superseded')
        and v.reviewed_at is not null and v.reviewed_at <= p_as_of
      order by v.version desc limit 1),
    (select v.id from realisasi.participant_set_versions v where v.activity_id = p_activity and v.status = 'approved'))
$$;

create function realisasi._is_unit_editor(p_activity uuid) returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce(realisasi.my_role() = 'io_admin', false)
      or (coalesce(realisasi.my_role() = 'submitter', false)
          and exists (select 1 from realisasi.activities a
                       where a.id = p_activity and a.submitter_unit_id = realisasi.my_unit()))
$$;

create function realisasi.in_frozen_period(p_activity uuid) returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select exists (select 1 from realisasi.activities a
                   join realisasi.kpi_snapshots s on s.superseded_by is null
                    and a.start_date between s.window_start and s.window_end
                  where a.id = p_activity)
$$;

create function realisasi.is_late_addition(p_activity uuid) returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select exists (select 1 from realisasi.activities a
                   join realisasi.kpi_snapshots s on s.superseded_by is null
                    and a.start_date between s.window_start and s.window_end
                  where a.id = p_activity and a.status = 'verified' and a.verified_at > s.frozen_at)
$$;

-- Permission predicates shared by RPCs and activity_detail.permissions (internal)
-- participant-edit permission (CONTRACTS §3.2 ensure_participant_draft)
create function realisasi._can_edit_participants(p_activity uuid, p_include_io boolean default true) returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select exists (select 1 from realisasi.activities a where a.id = p_activity and (
           (realisasi._is_unit_editor(a.id) and a.status <> 'rejected'
             and (a.status = 'draft' or a.mobility_status = 'revision_requested' or a.partnership_status = 'revision_requested'))
        or (p_include_io and a.status = 'verified' and realisasi.in_team('mobility'))))
$$;

-- file write permission (CONTRACTS §3.3)
create function realisasi._can_write_files(p_activity uuid) returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select exists (select 1 from realisasi.activities a where a.id = p_activity and (
           (realisasi._is_unit_editor(a.id) and (a.status = 'draft' or a.partnership_status = 'revision_requested'))
        or (a.status = 'verified' and realisasi.in_team('partnership'))))
$$;

-- View helpers (definer, counts only; granted so security_invoker views can call them)
create function realisasi.activity_linked_count(p_activity uuid) returns int
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select count(*)::int from realisasi.activities o
    join realisasi.activities a on a.id = p_activity and o.event_group_id = a.event_group_id and o.id <> a.id
$$;

create function realisasi.activity_participant_total(p_activity uuid) returns int
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce((select (select count(*) from realisasi.participant_students s where s.set_version_id = v.id)
                        + (select count(*) from realisasi.participant_staff st where st.set_version_id = v.id)
                     from realisasi.participant_set_versions v
                    where v.activity_id = p_activity and v.status <> 'draft'
                    order by v.version desc limit 1), 0)::int
$$;

-- Logging -----------------------------------------------------------------
create function realisasi._log(p_activity uuid, p_kind realisasi.log_kind, p_track realisasi.team, p_action text,
                               p_note text default null, p_diff jsonb default null) returns bigint
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
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
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
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
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare r uuid; n int := 0;
begin
  for r in select distinct x from unnest(p_recipients) x where x is not null order by 1 loop
    perform realisasi._notify(r, p_kind, p_title, p_body, p_link);
    n := n + 1;
  end loop;
  return n;
end $$;

create function realisasi._team_ids(p_team realisasi.team) returns uuid[]
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce(array_agg(distinct tm.account_id), '{}') from realisasi.team_members tm where tm.team = p_team
$$;

create function realisasi._admin_ids() returns uuid[]
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce(array_agg(id order by id), '{}') from public.profiles where app_role = 'io_admin'
$$;

create function realisasi._notify_team(p_team realisasi.team, p_kind text, p_title text, p_body text, p_link text) returns void
language sql security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select realisasi._notify_many(realisasi._team_ids(p_team), p_kind, p_title, p_body, p_link);
  select null::void
$$;

-- team notification minus the members of another team already notified for the same event (requirements-review L-4)
create function realisasi._notify_team_except(p_team realisasi.team, p_except realisasi.team, p_kind text, p_title text, p_body text, p_link text) returns void
language sql security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select realisasi._notify_many(array(select unnest(realisasi._team_ids(p_team)) except select unnest(realisasi._team_ids(p_except))),
                                p_kind, p_title, p_body, p_link);
  select null::void
$$;

create function realisasi._notify_admins(p_kind text, p_title text, p_body text, p_link text) returns void
language sql security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select realisasi._notify_many(realisasi._admin_ids(), p_kind, p_title, p_body, p_link);
  select null::void
$$;

create function realisasi._notify_unit(p_unit_id int, p_kind text, p_title text, p_body text, p_link text) returns void
language sql security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select realisasi._notify_many((select coalesce(array_agg(id), '{}') from public.profiles
                                  where app_role = 'submitter' and unit_id = p_unit_id),
                                p_kind, p_title, p_body, p_link);
  select null::void
$$;

create function realisasi._notify_viewers(p_kind text, p_title text, p_body text, p_link text) returns void
language sql security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select realisasi._notify_many((select coalesce(array_agg(id), '{}') from public.profiles where app_role = 'viewer'),
                                p_kind, p_title, p_body, p_link);
  select null::void
$$;
