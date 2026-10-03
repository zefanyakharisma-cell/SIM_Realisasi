-- 0014_reads: read RPCs returning the JSON shapes of CONTRACTS §4.

-- Period context ---------------------------------------------------------------------
create function realisasi._resolve_ay(p_ay_id int) returns int
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce(
    (select id from realisasi.academic_years where id = p_ay_id),
    case when p_ay_id is null then
      coalesce((select id from realisasi.academic_years where realisasi.today() between start_date and end_date limit 1),
               (select id from realisasi.academic_years where start_date <= realisasi.today() order by start_date desc limit 1),
               (select id from realisasi.academic_years order by start_date limit 1)) end)
$$;

create type realisasi.period_ctx as (ay_id int, ay_label text, period text, kind realisasi.snapshot_kind, label text,
  window_start date, window_end date, cutoff date, frozen boolean, snapshot_id uuid,
  frozen_at timestamptz, frozen_by_name text, grace_months int);

-- Revisi V.1 cut-offs: ganjil = Ganjil only; genap = Genap only; full = whole academic year (cumulative);
-- ytd = academic-year start -> today. Ganjil and full read their frozen snapshot when one exists. Genap has no
-- snapshot of its own: once the full-year snapshot is frozen it is computed as of that freeze (frozen, snapshot_id
-- null), so it never drifts afterwards. YTD is always live.
create function realisasi._period_ctx(p_ay_id int, p_period text, p_snapshot uuid default null) returns realisasi.period_ctx
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare ay realisasi.academic_years; s realisasi.kpi_snapshots; w record; r realisasi.period_ctx; g realisasi.semesters;
begin
  if p_snapshot is not null then
    select * into s from realisasi.kpi_snapshots where id = p_snapshot;
    if not found then perform realisasi._not_found(); end if;
    select * into ay from realisasi.academic_years where id = s.academic_year_id;
    r.period := case when s.kind = 'ganjil_ytd' then 'ganjil' else 'full' end;
  else
    if p_period is null or p_period not in ('ganjil','genap','full','ytd') then perform realisasi._invalid('period'); end if;
    select * into ay from realisasi.academic_years where id = realisasi._resolve_ay(p_ay_id);
    if not found then perform realisasi._not_found(); end if;
    r.period := p_period;
    -- YTD exists only for the active academic year; any other year falls back to Setahun (kumulatif)
    if r.period = 'ytd' and ay.id is distinct from realisasi._resolve_ay(null) then r.period := 'full'; end if;
  end if;
  r.ay_id := ay.id; r.ay_label := ay.label; r.frozen := false;
  r.grace_months := coalesce(realisasi.setting_int('grace_period_months'), 6);
  if r.period = 'ytd' then
    r.kind := null; r.label := 'YTD ' || ay.label;
    r.window_start := ay.start_date; r.window_end := least(ay.end_date, realisasi.today()); r.cutoff := r.window_end;
    return r;
  end if;
  if r.period = 'genap' then
    select * into g from realisasi.semesters where academic_year_id = ay.id and term = 'genap';
    if not found then perform realisasi._raise('R55_NO_SEMESTER', 'Kalender semester untuk periode ini belum diatur.'); end if;
    r.kind := null; r.label := 'Genap ' || ay.label;
    r.window_start := g.start_date; r.window_end := least(g.end_date, realisasi.today());
    r.cutoff := least(g.cutoff_date, realisasi.today());
    select * into s from realisasi.kpi_snapshots where academic_year_id = ay.id and kind = 'genap_full_year'
       and superseded_by is null;
    if s.id is not null then
      r.frozen := true; r.frozen_at := s.frozen_at;
      r.frozen_by_name := coalesce(realisasi._profile_name(s.frozen_by), 'Job terjadwal');
      r.window_end := g.end_date; r.cutoff := s.cutoff_date;
      r.grace_months := coalesce((s.settings_used ->> 'grace_period_months')::int, r.grace_months);
    end if;
    return r;
  end if;
  r.kind := case when r.period = 'ganjil' then 'ganjil_ytd' else 'genap_full_year' end;
  r.label := realisasi._snapshot_label(r.kind, ay.label);
  if s.id is null then
    select * into s from realisasi.kpi_snapshots where academic_year_id = ay.id and kpi_snapshots.kind = r.kind
       and superseded_by is null;
  end if;
  if s.id is not null then
    r.frozen := true; r.snapshot_id := s.id; r.frozen_at := s.frozen_at;
    r.frozen_by_name := coalesce(realisasi._profile_name(s.frozen_by), 'Job terjadwal');
    r.window_start := s.window_start; r.window_end := s.window_end; r.cutoff := s.cutoff_date;
    r.grace_months := coalesce((s.settings_used ->> 'grace_period_months')::int, r.grace_months);
  else
    select * into w from realisasi._snapshot_window(ay.id, r.kind);
    r.window_start := w.window_start;
    r.window_end := least(w.window_end, realisasi.today());
    r.cutoff := least(w.cutoff_date, realisasi.today());
  end if;
  return r;
end $$;

create function realisasi._period_json(c realisasi.period_ctx) returns jsonb
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select jsonb_build_object('ay_id', c.ay_id, 'ay_label', c.ay_label, 'period', c.period, 'kind', c.kind, 'label', c.label,
    'window_start', c.window_start, 'window_end', c.window_end, 'cutoff', c.cutoff, 'frozen', c.frozen,
    'snapshot_id', c.snapshot_id, 'frozen_at', c.frozen_at, 'frozen_by_name', c.frozen_by_name, 'today', realisasi.today(),
    'current_ay_id', realisasi._resolve_ay(null),
    'academic_years', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'label', label) order by start_date)
                                  from realisasi.academic_years), '[]'::jsonb))
$$;

create function realisasi.period_info(p_ay_id int, p_period text) returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare c realisasi.period_ctx;
begin
  perform realisasi._require_uid();
  c := realisasi._period_ctx(p_ay_id, p_period);
  return realisasi._period_json(c);
end $$;

-- KPI values for a context (frozen -> snapshot, else live) ------------------------
create function realisasi._ctx_values(c realisasi.period_ctx, p_unit_id int) returns jsonb
language plpgsql volatile security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v jsonb; e jsonb;
begin
  if c.frozen and c.snapshot_id is null then        -- genap after the full-year freeze: as of that freeze
    return realisasi.compute_kpis(c.window_start, c.window_end, c.cutoff, c.ay_id, c.frozen_at, p_unit_id);
  elsif c.frozen then
    select values into v from realisasi.kpi_snapshots where id = c.snapshot_id;
    if p_unit_id is null then return v; end if;
    select x into e from jsonb_array_elements(v -> 'by_unit') x where (x ->> 'unit_id')::int = p_unit_id;
    if e is null then
      e := realisasi._kpi_values('[]'::jsonb, c.window_start, c.window_end, c.ay_id, p_unit_id);
    end if;
    return jsonb_build_object('params', (v -> 'params') || jsonb_build_object('unit_id', p_unit_id))
           || (e - 'unit_id' - 'unit_name');
  end if;
  return realisasi.compute_kpis(c.window_start, c.window_end, c.cutoff, c.ay_id, null, p_unit_id);
end $$;

create function realisasi._scope_json(p_unit_id int) returns jsonb
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select jsonb_build_object('level', case when p_unit_id is null then 'university' else 'unit' end,
                            'unit_id', p_unit_id, 'unit_name', (select name from kerjasama.units where id = p_unit_id))
$$;

create function realisasi._forced_unit(p_unit_id int) returns int
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select case when realisasi.my_role() = 'submitter' then realisasi.my_unit() else p_unit_id end
$$;

-- "Perlu diproses" (Revisi V.1, replaces SLA): what the mobility team still has to handle. null for other roles.
create function realisasi._work_queue() returns jsonb
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select case when realisasi.in_team('mobility') then jsonb_build_object(
    'mobility_pending', (select count(*) from realisasi.activities where mobility_status = 'pending' and status <> 'draft'),
    'conflicts_open', (select count(*) from realisasi.participant_conflicts where status = 'open'),
    'waiting_unit_revision', (select count(*) from realisasi.activities where status = 'revision_requested'),
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name', a.name,
                         'unit_name', u.name, 'submitted_at', a.mobility_since,
                         'open_conflicts', realisasi.activity_open_conflicts(a.id)) order by a.mobility_since, a.code)
                        from (select * from realisasi.activities where mobility_status = 'pending' and status <> 'draft'
                               order by mobility_since, code limit 5) a
                        left join kerjasama.units u on u.id = a.submitter_unit_id), '[]'::jsonb)) end
$$;

create function realisasi.dashboard(p_ay_id int default null, p_period text default 'ytd', p_unit_id int default null) returns jsonb
language plpgsql volatile security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare c realisasi.period_ctx; pc realisasi.period_ctx; v_unit int; v_vals jsonb; v_prev jsonb := null; v_prev_ay realisasi.academic_years;
        v_pvals jsonb; v_late int; v_drafts jsonb := '[]'::jsonb; v_today date := realisasi.today();
begin
  perform realisasi._require_uid();
  v_unit := realisasi._forced_unit(p_unit_id);
  c := realisasi._period_ctx(p_ay_id, coalesce(p_period, 'ytd'));
  v_vals := realisasi._ctx_values(c, v_unit);

  select ay.* into v_prev_ay from realisasi.academic_years ay
    join realisasi.academic_years cur on cur.id = c.ay_id
   where ay.start_date < cur.start_date order by ay.start_date desc limit 1;
  if v_prev_ay.id is not null then
    if c.period = 'ytd' then
      v_pvals := realisasi.compute_kpis(v_prev_ay.start_date, least(v_prev_ay.end_date, (v_today - interval '1 year')::date),
                                        least(v_prev_ay.end_date, (v_today - interval '1 year')::date), v_prev_ay.id, null, v_unit);
    else
      begin
        pc := realisasi._period_ctx(v_prev_ay.id, c.period);
        v_pvals := realisasi._ctx_values(pc, v_unit);
      exception when others then v_pvals := null;
      end;
    end if;
    if v_pvals is not null then
      v_prev := jsonb_build_object('ay_label', v_prev_ay.label,
        'kpi_1_1', jsonb_build_object('total', v_pvals #> '{kpi_1_1,total}', 'inbound', v_pvals #> '{kpi_1_1,inbound}',
                                      'outbound', v_pvals #> '{kpi_1_1,outbound}'),
        'kpi_1_19_s1', jsonb_build_object('international', v_pvals #> '{kpi_1_19_s1,international}'),
        'kpi_1_19_24', jsonb_build_object('pct', v_pvals #> '{kpi_1_19_24,all,pct}'));
    end if;
  end if;

  if c.snapshot_id is not null then
    select count(*) into v_late from jsonb_array_elements(realisasi._snapshot_late_additions(c.snapshot_id)) x
     where v_unit is null or exists (select 1 from realisasi.activity_units au
                                      where au.activity_id = (x ->> 'activity_id')::uuid and au.unit_id = v_unit);
  else
    select count(*) into v_late from realisasi.activities a
     where a.status = 'verified' and a.start_date between c.window_start and c.window_end
       and (v_unit is null or exists (select 1 from realisasi.activity_units au where au.activity_id = a.id and au.unit_id = v_unit))
       and realisasi.is_late_addition(a.id);
  end if;

  if v_unit is not null then
    select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name', a.name, 'end_date', a.end_date,
             'reporting_deadline', a.reporting_deadline, 'days_left', a.reporting_deadline - v_today)
             order by a.reporting_deadline, a.code), '[]'::jsonb)
      into v_drafts
      from realisasi.activities a
     where a.status = 'draft' and a.submitter_unit_id = v_unit and a.reporting_deadline <= v_today + 14;
  end if;

  return jsonb_build_object('period', realisasi._period_json(c), 'scope', realisasi._scope_json(v_unit),
    'values', v_vals, 'previous', v_prev, 'late_additions', v_late, 'drafts_near_deadline', v_drafts,
    'work_queue', realisasi._work_queue());
end $$;

-- Drill-down -------------------------------------------------------------------------
create function realisasi._drill_items(c realisasi.period_ctx, p_unit_id int)
returns table(kpi_code text, bucket text, ref_type text, ref_id text, activity_id uuid, is_late boolean)
language plpgsql volatile security definer set search_path = realisasi, extensions, public, pg_temp as $$
begin
  if c.frozen and c.snapshot_id is null then          -- genap after the full-year freeze
    return query
      select i.kpi_code, i.bucket, i.ref_type, i.ref_id, i.activity_id,
             coalesce(i.activity_id is not null and realisasi.is_late_addition(i.activity_id), false)
        from realisasi._kpi_items(c.window_start, c.window_end, c.cutoff, c.ay_id, c.frozen_at, p_unit_id, c.grace_months) i;
  elsif c.frozen and p_unit_id is null then
    return query
      select i.kpi_code, i.bucket, i.ref_type, i.ref_id,
             case when i.ref_type = 'activity' then i.ref_id::uuid
                  when i.ref_type = 'participant' then split_part(i.ref_id, ':', 1)::uuid end,
             i.is_late_addition
        from realisasi.kpi_snapshot_items i where i.snapshot_id = c.snapshot_id;
  elsif c.frozen then
    return query
      select i.kpi_code, i.bucket, i.ref_type, i.ref_id, i.activity_id,
             coalesce(i.activity_id is not null and realisasi.is_late_addition(i.activity_id), false)
        from realisasi._kpi_items(c.window_start, c.window_end, c.cutoff, c.ay_id, c.frozen_at, p_unit_id, c.grace_months) i
       where i.activity_id is null
          or i.activity_id::text in (select b.ref_id from realisasi.kpi_snapshot_items b
                                      where b.snapshot_id = c.snapshot_id and b.kpi_code = 'base');
  else
    return query
      select i.kpi_code, i.bucket, i.ref_type, i.ref_id, i.activity_id,
             coalesce(i.activity_id is not null and realisasi.is_late_addition(i.activity_id), false)
        from realisasi._kpi_items(c.window_start, c.window_end, c.cutoff, c.ay_id, null, p_unit_id, c.grace_months) i;
  end if;
end $$;

create function realisasi._activity_kpi_row(p_activity uuid, p_bucket text, p_students int, p_late boolean) returns jsonb
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select jsonb_build_object('row_type', 'activity', 'activity_id', a.id, 'code', a.code, 'name', a.name,
    'agenda_name', g.name, 'direction', a.direction, 'mobility_category', r.mobility_category,
    'unit_names', coalesce((select jsonb_agg(u.name order by au.is_submitter desc, u.name) from realisasi.activity_units au
                             join kerjasama.units u on u.id = au.unit_id where au.activity_id = a.id), '[]'::jsonb),
    'partner_names', coalesce((select jsonb_agg(distinct ps.partner_name) from realisasi.activity_partner_snapshot ps where ps.activity_id = a.id), '[]'::jsonb),
    'country_codes', coalesce((select jsonb_agg(distinct ps.country_code) from realisasi.activity_partner_snapshot ps where ps.activity_id = a.id), '[]'::jsonb),
    'start_date', a.start_date, 'semester_label', realisasi.semester_label(a.semester_id),
    'bucket', p_bucket, 'students', p_students, 'is_late_addition', coalesce(p_late, false))
  from realisasi.activities a
  left join kerjasama.agendas g on g.id = a.agenda_id
  left join realisasi.agenda_rules r on r.agenda_id = a.agenda_id
 where a.id = p_activity
$$;

create function realisasi.kpi_drilldown(p_ay_id int, p_period text, p_kpi text, p_bucket text default null,
                                        p_unit_id int default null, p_snapshot_id uuid default null) returns jsonb
language plpgsql volatile security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare c realisasi.period_ctx; v_unit int; v_rows jsonb; v_io boolean := realisasi.is_io();
begin
  perform realisasi._require_uid();
  if p_kpi is null or p_kpi not in ('1.1','1.19.S1','1.19.24','base') then perform realisasi._invalid('kpi'); end if;
  v_unit := realisasi._forced_unit(p_unit_id);
  c := realisasi._period_ctx(p_ay_id, coalesce(p_period, 'ytd'), p_snapshot_id);
  if to_regclass('pg_temp._dd_items') is null then
    create temp table _dd_items (kpi_code text, bucket text, ref_type text, ref_id text, activity_id uuid, is_late boolean) on commit drop;
  end if;
  truncate _dd_items;
  insert into _dd_items select * from realisasi._drill_items(c, v_unit);

  if p_kpi = '1.1' then
    select coalesce(jsonb_agg(r order by r ->> 'start_date', r ->> 'code', r ->> 'bucket'), '[]'::jsonb) into v_rows from (
      select realisasi._activity_kpi_row(activity_id, bucket, count(*)::int, bool_or(is_late)) r
        from _dd_items where kpi_code = '1.1' and (p_bucket is null or bucket = p_bucket)
       group by activity_id, bucket) q;
  elsif p_kpi in ('1.19.S1','base') then
    select coalesce(jsonb_agg(r order by r ->> 'start_date', r ->> 'code'), '[]'::jsonb) into v_rows from (
      select realisasi._activity_kpi_row(activity_id, bucket, null, is_late) r
        from _dd_items where kpi_code = p_kpi and (p_bucket is null or bucket = p_bucket)) q;
  else
    select coalesce(jsonb_agg(r order by r ->> 'chain_start', (r ->> 'chain_id')::int), '[]'::jsonb) into v_rows from (
      select jsonb_build_object('row_type', 'chain', 'chain_id', ch.chain_id, 'current_document_id', ch.current_document_id,
               'current_doc_number', ch.current_doc_number, 'doc_numbers', to_jsonb(ch.doc_numbers), 'kind', ch.kind,
               'title', ch.title, 'partner_names', to_jsonb(ch.partner_names), 'country_codes', to_jsonb(ch.country_codes),
               'is_international', ch.is_international, 'chain_start', ch.chain_start, 'chain_end', ch.chain_end,
               'auto_renewed', ch.auto_renewed, 'bucket', x.b,
               'grace_until', case when x.b = 'grace_excluded' then (ch.chain_start + make_interval(months => c.grace_months))::date end,
               'activities', case when x.b = 'realized' then coalesce((
                    select jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name', a.name, 'start_date', a.start_date,
                                     'original_doc_number', d.doc_number) order by a.start_date, a.code)
                      from realisasi.activity_documents ad join realisasi.activities a on a.id = ad.activity_id
                      join kerjasama.documents d on d.id = ad.original_document_id
                     where ad.chain_id = ch.chain_id and a.status = 'verified'
                       and a.verified_at <= coalesce(c.frozen_at, realisasi.now_ts())
                       and a.start_date between c.window_start and c.cutoff
                       and (v_unit is null or exists (select 1 from realisasi.activity_units au where au.activity_id = a.id and au.unit_id = v_unit))),
                    '[]'::jsonb) else '[]'::jsonb end,
               'is_late_addition', x.late) r
        from (select ref_id::int chain_id,
                     case when bool_or(bucket = 'grace_excluded') then 'grace_excluded'
                          when bool_or(bucket = 'numerator') then 'realized' else 'not_realized' end b,
                     bool_or(is_late) late
                from _dd_items where kpi_code = '1.19.24' group by ref_id) x
        join realisasi.v_chains ch on ch.chain_id = x.chain_id
       where p_bucket is null
          or (p_bucket = 'numerator' and x.b = 'realized')
          or (p_bucket = 'denominator' and x.b in ('realized','not_realized'))
          or (p_bucket in ('realized','not_realized','grace_excluded') and x.b = p_bucket)) q;
  end if;

  return jsonb_build_object('period', realisasi._period_json(c), 'scope', realisasi._scope_json(v_unit),
                            'kpi', p_kpi, 'bucket', p_bucket, 'rows', v_rows);
end $$;

create function realisasi.kpi_participant_rows(p_ay_id int, p_period text, p_unit_id int default null,
                                               p_snapshot_id uuid default null) returns jsonb
language plpgsql volatile security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare c realisasi.period_ctx; v_unit int;
begin
  perform realisasi._require_uid();
  if realisasi.my_role() = 'submitter' then
    v_unit := realisasi.my_unit();
  elsif realisasi.in_team('mobility') then
    v_unit := p_unit_id;
  else
    perform realisasi._forbidden();
  end if;
  c := realisasi._period_ctx(p_ay_id, coalesce(p_period, 'ytd'), p_snapshot_id);
  return coalesce((select jsonb_agg(jsonb_build_object(
      'activity_id', a.id, 'code', a.code, 'name', a.name, 'direction', a.direction,
      'section', s.section, 'nrp', s.nrp, 'full_name', s.full_name, 'faculty_name', s.faculty_name, 'prodi_name', s.prodi_name,
      'home_institution', s.home_institution, 'home_country_code', s.home_country_code,
      'start_date', a.start_date, 'semester_label', realisasi.semester_label(a.semester_id))
      order by a.start_date, a.code, s.section, s.nrp)
    from realisasi._drill_items(c, v_unit) i
    join realisasi.activities a on a.id = i.activity_id
    -- M2: the version that counted at the snapshot's as-of (frozen) or the current approved one (live)
    join realisasi.participant_students s on s.set_version_id = realisasi._pset_as_of(a.id, c.frozen_at)
                                         and s.nrp = split_part(i.ref_id, ':', 2)
   where i.kpi_code = '1.1'), '[]'::jsonb);
end $$;

-- Activity detail ------------------------------------------------------------------
create function realisasi._pset_counts(p_version uuid) returns jsonb
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select jsonb_build_object('version', v.version, 'status', v.status,
    'internal_students', (select count(*) from realisasi.participant_students s where s.set_version_id = v.id and s.section = 'internal'),
    'inbound_students', (select count(*) from realisasi.participant_students s where s.set_version_id = v.id and s.section = 'inbound'),
    'staff', (select count(*) from realisasi.participant_staff s where s.set_version_id = v.id))
  from realisasi.participant_set_versions v where v.id = p_version
$$;

create function realisasi._counts_version(p_activity uuid) returns uuid
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce((select id from realisasi.participant_set_versions where activity_id = p_activity and status = 'approved'),
                  (select id from realisasi.participant_set_versions where activity_id = p_activity and status <> 'draft'
                    order by version desc limit 1))
$$;

create function realisasi.participant_counts(p_activity uuid) returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
begin
  perform realisasi._require_uid();
  if not exists (select 1 from realisasi.activities where id = p_activity) or not realisasi.can_view_activity(p_activity) then
    perform realisasi._not_found();
  end if;
  return realisasi._pset_counts(realisasi._counts_version(p_activity));
end $$;

create function realisasi._sees_draft_versions(p_activity uuid) returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select realisasi._is_unit_editor(p_activity) or realisasi.in_team('mobility')
$$;

create function realisasi.activity_detail(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare a realisasi.activities; v_role text; v_editor boolean; v_perm jsonb; v_mob boolean;
        v_m_team boolean; v_rev jsonb; v_cat realisasi.mobility_category; v_s1 boolean;
begin
  perform realisasi._require_uid();
  select * into a from realisasi.activities where id = p_id;
  if not found or not realisasi.can_view_activity(p_id) then perform realisasi._not_found(); end if;
  select mobility_category, counts_for_s1 into v_cat, v_s1 from realisasi.agenda_rules where agenda_id = a.agenda_id;
  v_mob := v_cat is not null;
  v_role := realisasi.my_role(); v_editor := realisasi._is_unit_editor(p_id);
  v_m_team := realisasi.in_team('mobility');

  v_perm := jsonb_build_object(
    'can_edit_draft', v_editor and a.status = 'draft',
    'can_delete_draft', a.status = 'draft' and realisasi._can_delete_draft(p_id),
    'can_edit_detail', v_editor and (a.status = 'draft' or a.mobility_status = 'revision_requested'),
    'can_edit_files', v_editor and (a.status = 'draft' or a.mobility_status = 'revision_requested'),
    'can_edit_participants', realisasi._can_edit_participants(p_id, false),
    'can_submit', v_editor and (a.status = 'draft' or a.mobility_status = 'revision_requested'),
    'can_mobility_verify', v_m_team and a.mobility_status = 'pending' and a.status <> 'draft',
    'can_edit_verified_detail', a.status = 'verified' and v_role = 'io_admin',
    'can_edit_verified_participants', a.status = 'verified' and v_m_team and v_mob,
    'can_view_participants', realisasi.can_view_participants(p_id),
    'can_view_log', v_role <> 'viewer');

  v_rev := jsonb_build_object(
    'mobility', case when a.mobility_status = 'revision_requested' then (
        select jsonb_build_object('note', l.note, 'requested_by_name', realisasi._profile_name(l.actor_id), 'requested_at', l.created_at)
          from realisasi.activity_log l where l.activity_id = p_id and l.track = 'mobility' and l.action = 'request_revision'
         order by l.created_at desc, l.id desc limit 1) end);

  return jsonb_build_object(
    'id', a.id, 'code', a.code, 'name', a.name,
    'agenda', jsonb_build_object('id', a.agenda_id, 'name', (select name from kerjasama.agendas where id = a.agenda_id),
                                 'mobility_category', v_cat, 'is_mobility', v_mob, 'counts_for_s1', coalesce(v_s1, true)),
    'direction', a.direction,
    'start_date', a.start_date, 'end_date', a.end_date, 'duration_days', a.end_date - a.start_date + 1,
    'academic_year', (select jsonb_build_object('id', id, 'label', label) from realisasi.academic_years where id = a.academic_year_id),
    'semester', (select jsonb_build_object('id', id, 'term', term, 'label', realisasi.semester_label(id)) from realisasi.semesters where id = a.semester_id),
    'mode', a.mode, 'venue', a.venue, 'country_code', a.country_code,
    'country_name', (select name from kerjasama.countries where code = a.country_code),
    'sks_recognized', a.sks_recognized, 'description', a.description,
    'submitter_unit', (select jsonb_build_object('id', id, 'name', name) from kerjasama.units where id = a.submitter_unit_id),
    'units', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'name', u.name, 'is_submitter', au.is_submitter)
                                        order by au.is_submitter desc, u.name)
                         from realisasi.activity_units au join kerjasama.units u on u.id = au.unit_id where au.activity_id = p_id), '[]'::jsonb),
    'status', a.status, 'mobility_status', a.mobility_status, 'mobility_since', a.mobility_since,
    'submitted_at', a.submitted_at, 'verified_at', a.verified_at,
    'reporting_deadline', a.reporting_deadline, 'is_late', a.is_late,
    'documents', coalesce((select jsonb_agg(jsonb_build_object(
        'original_document_id', od.id, 'original_doc_number', od.doc_number,
        'current_document_id', cd.id, 'current_doc_number', cd.doc_number, 'kind', od.kind, 'title', od.title,
        'chain_id', ad.chain_id, 'start_date', od.start_date, 'end_date', od.end_date, 'is_archived', od.status = 'archived',
        'out_of_scope_warning', ad.out_of_scope_warning,
        'partners', coalesce((select jsonb_agg(jsonb_build_object('partner_id', p.id, 'name', p.name, 'country_code', p.country_code,
                                'country_name', co.name) order by dp.is_lead desc, p.name)
                               from kerjasama.document_partners dp join kerjasama.partners p on p.id = dp.partner_id
                               left join kerjasama.countries co on co.code = p.country_code where dp.document_id = od.id), '[]'::jsonb))
        order by od.doc_number)
      from realisasi.activity_documents ad join kerjasama.documents od on od.id = ad.original_document_id
      left join kerjasama.documents cd on cd.id = realisasi.chain_current(ad.original_document_id)
     where ad.activity_id = p_id), '[]'::jsonb),
    'partners', coalesce((select jsonb_agg(jsonb_build_object('document_id', ps.document_id, 'partner_id', ps.partner_id,
                            'partner_name', ps.partner_name, 'country_code', ps.country_code, 'country_name', co.name) order by ps.id)
                           from realisasi.activity_partner_snapshot ps left join kerjasama.countries co on co.code = ps.country_code
                          where ps.activity_id = p_id), '[]'::jsonb),
    'is_international', exists (select 1 from realisasi.activity_partner_snapshot ps where ps.activity_id = p_id and ps.country_code <> 'ID'),
    'sdg_ids', coalesce((select jsonb_agg(sdg_id order by sdg_id) from realisasi.activity_sdgs where activity_id = p_id), '[]'::jsonb),
    'external_persons', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'full_name', e.full_name, 'institution', e.institution,
                                    'country_code', e.country_code, 'role', e.role, 'notes', e.notes) order by e.id)
                                   from realisasi.activity_external_persons e where e.activity_id = p_id), '[]'::jsonb),
    -- the mobility bundle is personal data (participant readers only)
    'files', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'kind', f.kind, 'version', f.version, 'storage_path', f.storage_path,
                         'url', f.url, 'filename', f.filename, 'size_bytes', f.size_bytes, 'mime', f.mime, 'is_current', f.is_current,
                         'uploaded_by_name', realisasi._profile_name(f.uploaded_by), 'uploaded_at', f.uploaded_at,
                         'href', coalesce(case when f.storage_path is not null then realisasi._file_href(f.storage_path) end, f.url))
                         order by f.kind, f.version desc, f.id desc)
                        from realisasi.activity_files f where f.activity_id = p_id
                         and (f.kind <> 'mobility_bundle' or realisasi.can_view_participants(p_id))), '[]'::jsonb),
    'participants', jsonb_build_object(
        'can_view_rows', realisasi.can_view_participants(p_id),
        'counts', realisasi._pset_counts(realisasi._counts_version(p_id)),
        'versions', coalesce((select jsonb_agg(realisasi._pset_counts(v.id) - 'version' - 'status' || jsonb_build_object(
                         'id', v.id, 'version', v.version, 'status', v.status, 'submitted_at', v.submitted_at,
                         'submitted_by_name', realisasi._profile_name(v.submitted_by), 'reviewed_at', v.reviewed_at,
                         'reviewed_by_name', realisasi._profile_name(v.reviewed_by), 'review_note', v.review_note) order by v.version)
                       from realisasi.participant_set_versions v
                      where v.activity_id = p_id and (v.status <> 'draft' or realisasi._sees_draft_versions(p_id))), '[]'::jsonb)),
    'revision', v_rev,
    'log', case when v_role = 'viewer' then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object(
              'id', l.id, 'kind', l.kind, 'track', l.track, 'action', l.action, 'actor_name', realisasi._profile_name(l.actor_id),
              'note', l.note,
              'diff', case when realisasi.can_view_participants(p_id) then l.diff else realisasi._mask_log_diff(l.diff) end,   -- M6
              'in_frozen_period', l.in_frozen_period, 'created_at', l.created_at)
              order by l.created_at desc, l.id desc) from realisasi.activity_log l where l.activity_id = p_id), '[]'::jsonb) end,
    'conflicts', case when v_m_team then realisasi.conflict_list(p_id, null) else '[]'::jsonb end,
    'flags', jsonb_build_object('late', a.is_late,
              'out_of_scope', exists (select 1 from realisasi.activity_documents where activity_id = p_id and out_of_scope_warning),
              'conflicts_open', case when v_m_team then realisasi.activity_open_conflicts(p_id) else 0 end,
              'late_addition', realisasi.is_late_addition(p_id)),
    'checklist', case when (v_perm ->> 'can_submit')::boolean then realisasi._checklist(p_id) end,
    'permissions', v_perm);
end $$;

create function realisasi.participant_version(p_activity uuid, p_version int default null) returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v realisasi.participant_set_versions; v_drafts boolean;
begin
  perform realisasi._require_uid();
  if not exists (select 1 from realisasi.activities where id = p_activity) or not realisasi.can_view_participants(p_activity) then
    perform realisasi._forbidden();
  end if;
  v_drafts := realisasi._sees_draft_versions(p_activity);
  select * into v from realisasi.participant_set_versions
   where activity_id = p_activity and (p_version is null or version = p_version) and (status <> 'draft' or v_drafts)
   order by version desc limit 1;
  if not found then
    if p_version is not null then perform realisasi._not_found(); end if;
    return null;
  end if;
  return jsonb_build_object('id', v.id, 'activity_id', v.activity_id, 'version', v.version, 'status', v.status,
    'submitted_at', v.submitted_at, 'submitted_by_name', realisasi._profile_name(v.submitted_by),
    'reviewed_at', v.reviewed_at, 'reviewed_by_name', realisasi._profile_name(v.reviewed_by), 'review_note', v.review_note,
    'students', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'section', s.section, 'nrp', s.nrp, 'full_name', s.full_name,
                  'faculty_name', s.faculty_name, 'prodi_name', s.prodi_name, 'home_institution', s.home_institution,
                  'home_student_number', s.home_student_number, 'home_country_code', s.home_country_code,
                  'registry_status', coalesce(b.status, 'inactive'))
                  order by s.section, s.id)
                 from realisasi.participant_students s left join mock_baak.students b on b.nrp = s.nrp
                where s.set_version_id = v.id), '[]'::jsonb),
    'staff', coalesce((select jsonb_agg(jsonb_build_object('id', st.id, 'employee_id', st.employee_id, 'full_name', st.full_name,
                  'unit_name', st.unit_name, 'registry_status', coalesce(e.status, 'inactive')) order by st.id)
                 from realisasi.participant_staff st left join mock_hr.employees e on e.employee_id = st.employee_id
                where st.set_version_id = v.id), '[]'::jsonb));
end $$;

create function realisasi.nav_counts() returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_uid();
begin
  return jsonb_build_object(
    'mobility_queue', case when realisasi.in_team('mobility') then
        (select count(*) from realisasi.activities where mobility_status = 'pending' and status <> 'draft') else 0 end,
    'conflicts_open', case when realisasi.in_team('mobility') then
        (select count(*) from realisasi.participant_conflicts where status = 'open') else 0 end,
    'revision_inbox', case when realisasi.my_role() = 'submitter' then
        (select count(*) from realisasi.activities where status = 'revision_requested' and submitter_unit_id = realisasi.my_unit()) else 0 end,
    'unread_notifications', (select count(*) from realisasi.notifications where recipient_id = v_uid and read_at is null));
end $$;

-- Agreements -----------------------------------------------------------------------
create function realisasi.agreement_realization(p_document_id int) returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare d kerjasama.documents; v_chain int; ch record; ay realisasi.academic_years; v_io boolean; v_grace int;
        v_acts uuid[]; v_in_grace boolean;
begin
  perform realisasi._require_uid();
  select * into d from kerjasama.documents where id = p_document_id;
  if not found then perform realisasi._not_found(); end if;
  v_io := realisasi.is_io();
  v_chain := realisasi.chain_root(d.id);
  select * into ch from realisasi.v_chains where chain_id = v_chain;
  select * into ay from realisasi.academic_years where id = realisasi._resolve_ay(null);
  v_grace := coalesce(realisasi.setting_int('grace_period_months'), 6);
  select coalesce(array_agg(distinct a.id), '{}') into v_acts
    from realisasi.activity_documents ad join realisasi.activities a on a.id = ad.activity_id
   where ad.chain_id = v_chain and (case when v_io then a.status <> 'draft' else a.status = 'verified' end);
  v_in_grace := ch.chain_id is not null and not ch.auto_renewed
                and ch.chain_start > (realisasi.today() - make_interval(months => v_grace))::date;

  return jsonb_build_object(
    'document', jsonb_build_object('id', d.id, 'doc_number', d.doc_number, 'title', d.title, 'kind', d.kind, 'status', d.status,
                                   'start_date', d.start_date, 'end_date', d.end_date, 'auto_renewed', d.auto_renewed),
    'chain', jsonb_build_object('chain_id', v_chain, 'chain_start', ch.chain_start, 'chain_end', ch.chain_end,
               'auto_renewed', coalesce(ch.auto_renewed, d.auto_renewed), 'is_international', coalesce(ch.is_international, false),
               'documents', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'doc_number', x.doc_number, 'kind', x.kind,
                               'status', x.status, 'start_date', x.start_date, 'end_date', x.end_date, 'predecessor_id', x.predecessor_id)
                               order by x.start_date nulls last, x.id)
                              from kerjasama.documents x join realisasi._chain_map() m on m.doc_id = x.id and m.root_id = v_chain), '[]'::jsonb)),
    'current_ay', case when ay.id is not null then jsonb_build_object('id', ay.id, 'label', ay.label) end,
    'summary', jsonb_build_object(
        'total_activities', cardinality(v_acts),
        'activities_this_ay', (select count(*) from realisasi.activities a where a.id = any(v_acts)
                                and a.start_date between ay.start_date and ay.end_date),
        'students_inbound', (select count(distinct (s.nrp, a.id)) from realisasi.activities a
                               join realisasi.agenda_rules t on t.agenda_id = a.agenda_id and t.mobility_category is not null
                               join realisasi.participant_set_versions v on v.activity_id = a.id and v.status = 'approved'
                               join realisasi.participant_students s on s.set_version_id = v.id and s.section = 'inbound'
                              where a.id = any(v_acts) and a.status = 'verified' and a.direction = 'inbound'),
        'students_outbound', (select count(distinct (s.nrp, a.id)) from realisasi.activities a
                               join realisasi.agenda_rules t on t.agenda_id = a.agenda_id and t.mobility_category is not null
                               join realisasi.participant_set_versions v on v.activity_id = a.id and v.status = 'approved'
                               join realisasi.participant_students s on s.set_version_id = v.id and s.section = 'internal'
                              where a.id = any(v_acts) and a.status = 'verified' and a.direction = 'outbound'),
        'last_activity_date', (select max(a.start_date) from realisasi.activities a where a.id = any(v_acts) and a.status = 'verified')),
    'grace', jsonb_build_object('in_grace', v_in_grace,
               'grace_until', case when v_in_grace then (ch.chain_start + make_interval(months => v_grace))::date end),
    'activities', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name', a.name, 'agenda_name', g.name,
                     'start_date', a.start_date, 'end_date', a.end_date, 'status', a.status,
                     'unit_names', coalesce((select jsonb_agg(u.name order by au.is_submitter desc, u.name) from realisasi.activity_units au
                                              join kerjasama.units u on u.id = au.unit_id where au.activity_id = a.id), '[]'::jsonb),
                     'original_doc_number', od.doc_number,
                     'current_doc_number', (select doc_number from kerjasama.documents where id = realisasi.chain_current(od.id)))
                     order by a.start_date, a.code)
                    from realisasi.activities a left join kerjasama.agendas g on g.id = a.agenda_id
                    join realisasi.activity_documents ad on ad.activity_id = a.id and ad.chain_id = v_chain
                    join kerjasama.documents od on od.id = ad.original_document_id
                   where a.id = any(v_acts) and (v_io or realisasi.can_view_activity(a.id))), '[]'::jsonb));   -- M7: list only visible ones
end $$;

create function realisasi.agreement_flags(p_ay_id int default null) returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare ay realisasi.academic_years; v_cut date; v_grace int := coalesce(realisasi.setting_int('grace_period_months'), 6);
begin
  perform realisasi._require_uid();
  select * into ay from realisasi.academic_years where id = realisasi._resolve_ay(p_ay_id);
  if not found then perform realisasi._not_found(); end if;
  v_cut := least(ay.end_date, realisasi.today());
  return coalesce((select jsonb_agg(jsonb_build_object('document_id', d.id, 'chain_id', x.chain_id,
      'flag', case when ch.chain_id is null or d.status in ('in_process','rejected')
                     or not (ch.chain_start <= v_cut and ((ch.auto_renewed and ch.terminated_at is null) or ch.chain_end >= ay.start_date)) then 'inactive'
                   when not ch.auto_renewed and ch.chain_start > (v_cut - make_interval(months => v_grace))::date then 'grace'
                   when x.n_win > 0 then 'realized' else 'not_realized' end,
      'grace_until', case when ch.chain_id is not null and not ch.auto_renewed
                           and ch.chain_start > (v_cut - make_interval(months => v_grace))::date
                          then (ch.chain_start + make_interval(months => v_grace))::date end,
      'activities_this_ay', x.n_ay, 'last_activity_date', x.last_date) order by d.id)
    -- H6: chain roots and per-chain activity stats computed once (set-based), not per document
    from kerjasama.documents d
    left join realisasi._chain_map() r on r.doc_id = d.id
    left join (
      select ad.chain_id,
             count(distinct a.id) filter (where a.start_date between ay.start_date and v_cut) as n_win,
             count(distinct a.id) filter (where a.start_date between ay.start_date and ay.end_date) as n_ay,
             max(a.start_date) as last_date
        from realisasi.activity_documents ad join realisasi.activities a on a.id = ad.activity_id and a.status = 'verified'
       group by ad.chain_id) st on st.chain_id = r.root_id
    cross join lateral (select r.root_id as chain_id, coalesce(st.n_win, 0) as n_win, coalesce(st.n_ay, 0) as n_ay, st.last_date) x
    left join realisasi.v_chains ch on ch.chain_id = x.chain_id), '[]'::jsonb);
end $$;

-- Snapshot archive -----------------------------------------------------------------
create function realisasi._snapshot_row(p_snapshot uuid, p_unit_id int) returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare s realisasi.kpi_snapshots; ay realisasi.academic_years; v jsonb; e jsonb;
begin
  select * into s from realisasi.kpi_snapshots where id = p_snapshot;
  select * into ay from realisasi.academic_years where id = s.academic_year_id;
  v := s.values;
  if p_unit_id is not null then
    select x into e from jsonb_array_elements(v -> 'by_unit') x where (x ->> 'unit_id')::int = p_unit_id;
    v := coalesce(e, '{}'::jsonb);
  end if;
  return jsonb_build_object('id', s.id, 'ay_id', ay.id, 'ay_label', ay.label, 'kind', s.kind,
    'label', realisasi._snapshot_label(s.kind, ay.label),
    'window_start', s.window_start, 'window_end', s.window_end, 'cutoff_date', s.cutoff_date,
    'frozen_at', s.frozen_at, 'frozen_by_name', coalesce(realisasi._profile_name(s.frozen_by), 'Job terjadwal'),
    'is_live', s.superseded_by is null, 'superseded_by', s.superseded_by, 'refreeze_reason', s.refreeze_reason,
    'summary', jsonb_build_object('kpi_1_1_total', coalesce((v #>> '{kpi_1_1,total}')::int, 0),
                                  'kpi_1_19_s1_international', coalesce((v #>> '{kpi_1_19_s1,international}')::int, 0),
                                  'kpi_1_19_24_pct', v #> '{kpi_1_19_24,all,pct}'),
    'late_additions', jsonb_array_length(realisasi._snapshot_late_additions(s.id)),
    'post_freeze_changes', jsonb_array_length(realisasi._snapshot_post_freeze_changes(s.id)));
end $$;

create function realisasi.snapshot_list(p_ay_id int default null) returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_unit int;
begin
  perform realisasi._require_uid();
  v_unit := case when realisasi.my_role() = 'submitter' then realisasi.my_unit() end;
  return coalesce((select jsonb_agg(realisasi._snapshot_row(s.id, v_unit) order by s.frozen_at desc, s.id)
                     from realisasi.kpi_snapshots s where p_ay_id is null or s.academic_year_id = p_ay_id), '[]'::jsonb);
end $$;

create function realisasi.snapshot_detail(p_snapshot uuid) returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare s realisasi.kpi_snapshots;
begin
  perform realisasi._require_report_reader();
  select * into s from realisasi.kpi_snapshots where id = p_snapshot;
  if not found then perform realisasi._not_found(); end if;
  return jsonb_build_object('snapshot', realisasi._snapshot_row(s.id, null), 'values', s.values, 'settings_used', s.settings_used,
    'late_additions', realisasi._snapshot_late_additions(s.id), 'post_freeze_changes', realisasi._snapshot_post_freeze_changes(s.id));
end $$;

-- International Awards (Revisi V.1) -----------------------------------------------------------------------------
-- Four leaderboards per PROGRAM STUDI for a period context (Fakultas, Program and UP units are never ranked), built on
-- the same verified items as KPI 1.1 at university level (so students are counted once and the conflict decisions of
-- rule 2.1 apply). Student boards credit each student to their OWN prodi (participant prodi_name matched to a
-- kerjasama.units prodi); a student without a matching prodi (e.g. inbound exchange "Program Pertukaran") goes to the
-- submitting unit when that unit is a prodi (the host), else is not counted. Boards: inbound, outbound domestic
-- (activity country Indonesia) and outbound international by mobility category, plus international initiatives
-- (activities with a foreign partner or held abroad, per submitting prodi). "Kegiatan Internasional (<14 hari)" =
-- students of a mobility kegiatan lasting under 14 days whose category is none of JD/DD, Student Exchange,
-- Short/Summer, so every student is in one column only. total = sum of the columns. A unit scope (or a submitter)
-- keeps that prodi, or the prodis of that faculty.
-- prodi name as BAAK and SIMKS spell it, without the "Prodi" / "Program Studi" prefix (internal)
create function realisasi._prodi_norm(p_name text) returns text
language sql immutable set search_path = realisasi, extensions, public, pg_temp as $$
  select lower(regexp_replace(btrim(p_name), '^(prodi|program studi)\s+', '', 'i'))
$$;

create function realisasi.international_awards(p_ay_id int default null, p_period text default 'ytd', p_unit_id int default null)
returns jsonb
language plpgsql volatile security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare c realisasi.period_ctx; v_unit int;
begin
  perform realisasi._require_uid();
  v_unit := realisasi._forced_unit(p_unit_id);
  c := realisasi._period_ctx(p_ay_id, coalesce(p_period, 'ytd'));
  if to_regclass('pg_temp._aw_items') is null then
    create temp table _aw_items (su int, kpi_code text, bucket text, ref_type text, ref_id text, activity_id uuid, is_intl boolean) on commit drop;
    create temp table _aw_prodi (id int primary key, name text, norm text, in_scope boolean) on commit drop;
  end if;
  truncate _aw_items, _aw_prodi;
  insert into _aw_items
  select * from realisasi._kpi_items_scoped(c.window_start, c.window_end, c.cutoff, c.frozen_at, 'university', null, c.grace_months) i
   where i.kpi_code in ('1.1','base');
  -- the rankable units: Program Studi only; a unit scope keeps that prodi or the prodis of that faculty
  insert into _aw_prodi
  select u.id, u.name, realisasi._prodi_norm(u.name), v_unit is null or u.id = v_unit or u.parent_id = v_unit
    from kerjasama.units u where u.kind = 'prodi';

  return jsonb_build_object('period', realisasi._period_json(c), 'scope', realisasi._scope_json(v_unit),
    'inbound', realisasi._awards_students('inbound', null),
    'outbound_domestic', realisasi._awards_students('outbound', false),
    'outbound_international', realisasi._awards_students('outbound', true),
    'initiatives', coalesce((select jsonb_agg(to_jsonb(x) order by x.total desc, x.unit_name) from (
        select a.submitter_unit_id as unit_id, u.name as unit_name,
               count(*) filter (where a.direction = 'inbound' and r.mobility_category is not null)::int as inbound,
               count(*) filter (where a.direction = 'outbound' and r.mobility_category is not null)::int as outbound,
               count(*) filter (where r.mobility_category is null)::int as activities,
               count(*)::int as total
          from _aw_items i
          join realisasi.activities a on a.id = i.activity_id
          join _aw_prodi u on u.id = a.submitter_unit_id and u.in_scope
          left join realisasi.agenda_rules r on r.agenda_id = a.agenda_id
         where i.kpi_code = 'base'
           and (coalesce(a.country_code <> 'ID', false)
                or exists (select 1 from realisasi.activity_partner_snapshot ps where ps.activity_id = a.id and ps.country_code <> 'ID'))
         group by a.submitter_unit_id, u.name) x), '[]'::jsonb));
end $$;

-- one student leaderboard from _aw_items / _aw_prodi (internal; p_intl null = any country), grouped by the student's
-- own prodi (participant prodi_name), else the submitting unit when that is a prodi (the host of inbound students)
create function realisasi._awards_students(p_direction text, p_intl boolean) returns jsonb
language plpgsql volatile security definer set search_path = realisasi, extensions, public, pg_temp as $$
begin
  return (select coalesce(jsonb_agg(to_jsonb(x) order by x.total desc, x.unit_name), '[]'::jsonb) from (
    select unit_id, unit_name, jd_dd, student_exchange, short_summer, short_international,
           jd_dd + student_exchange + short_summer + short_international as total
      from (
        select u.id as unit_id, u.name as unit_name,
               count(*) filter (where r.mobility_category = 'jd_dd')::int as jd_dd,
               count(*) filter (where r.mobility_category = 'student_exchange')::int as student_exchange,
               count(*) filter (where r.mobility_category = 'short_summer')::int as short_summer,
               count(*) filter (where r.mobility_category = 'other_mobility' and a.end_date - a.start_date + 1 < 14)::int
                 as short_international
          from _aw_items i
          join realisasi.activities a on a.id = i.activity_id
          join realisasi.agenda_rules r on r.agenda_id = a.agenda_id
          left join lateral (select s.prodi_name from realisasi.participant_students s
                              where s.set_version_id = realisasi._counts_version(a.id) and s.nrp = split_part(i.ref_id, ':', 2)
                              order by s.id limit 1) st on true
          join _aw_prodi u on u.id = coalesce((select p.id from _aw_prodi p where p.norm = realisasi._prodi_norm(st.prodi_name)
                                                order by p.id limit 1),
                                               (select p.id from _aw_prodi p where p.id = a.submitter_unit_id))
         where i.kpi_code = '1.1' and i.bucket = p_direction and u.in_scope
           and (p_intl is null
                or p_intl = coalesce(a.country_code <> 'ID',
                                     exists (select 1 from realisasi.activity_partner_snapshot ps
                                              where ps.activity_id = a.id and ps.country_code <> 'ID')))
         group by u.id, u.name) y
     where jd_dd + student_exchange + short_summer + short_international > 0) x);
end $$;
