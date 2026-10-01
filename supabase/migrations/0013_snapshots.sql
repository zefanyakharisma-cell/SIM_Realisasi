-- 0013_snapshots: freeze / refreeze (R-55..R-59), late additions and post-freeze changes.

-- previous live snapshot P of a snapshot (or of a moment): greatest frozen_at < p_before, excluding p_self
create function realisasi._prev_snapshot(p_before timestamptz, p_self uuid) returns realisasi.kpi_snapshots
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select * from realisasi.kpi_snapshots
   where superseded_by is null and id is distinct from p_self and frozen_at < p_before
   order by frozen_at desc limit 1
$$;

create function realisasi._snapshot_window(p_ay int, p_kind realisasi.snapshot_kind,
                                           out window_start date, out window_end date, out cutoff_date date)
language plpgsql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
declare ay realisasi.academic_years; s realisasi.semesters;
begin
  select * into ay from realisasi.academic_years where id = p_ay;
  if not found then perform realisasi._not_found(); end if;
  select * into s from realisasi.semesters where academic_year_id = p_ay
     and term = case when p_kind = 'ganjil_ytd' then 'ganjil' else 'genap' end::realisasi.semester_term;
  if not found then perform realisasi._raise('R55_NO_SEMESTER', 'Kalender semester untuk periode ini belum diatur.'); end if;
  window_start := ay.start_date;
  window_end := case when p_kind = 'ganjil_ytd' then s.end_date else ay.end_date end;
  cutoff_date := s.cutoff_date;
end $$;

create function realisasi._freeze(p_ay int, p_kind realisasi.snapshot_kind, p_as_of timestamptz, p_actor uuid,
                                  p_reason text, p_old uuid) returns uuid
language plpgsql security definer set search_path = realisasi, public, extensions, pg_temp as $$
declare w record; v_id uuid := gen_random_uuid(); v_vals jsonb; p realisasi.kpi_snapshots; v_label text;
begin
  select * into w from realisasi._snapshot_window(p_ay, p_kind);
  if p_old is not null then
    update realisasi.kpi_snapshots set superseded_by = v_id where id = p_old;   -- deferred FK
  elsif exists (select 1 from realisasi.kpi_snapshots where academic_year_id = p_ay and kind = p_kind and superseded_by is null) then
    perform realisasi._raise('R55_ALREADY_FROZEN', 'Snapshot untuk periode ini sudah dibekukan. Gunakan "Bekukan ulang".');
  end if;

  v_vals := realisasi.compute_kpis(w.window_start, w.window_end, w.cutoff_date, p_ay, p_as_of, null);
  insert into realisasi.kpi_snapshots (id, academic_year_id, kind, window_start, window_end, cutoff_date, values,
                                       settings_used, frozen_at, frozen_by, refreeze_reason)
  values (v_id, p_ay, p_kind, w.window_start, w.window_end, w.cutoff_date, v_vals,
          realisasi.settings_json(), p_as_of, p_actor, p_reason);

  p := realisasi._prev_snapshot(p_as_of, v_id);
  insert into realisasi.kpi_snapshot_items (snapshot_id, kpi_code, bucket, ref_type, ref_id, is_late_addition)
  select distinct on (i.kpi_code, i.bucket, i.ref_type, i.ref_id) v_id, i.kpi_code, i.bucket, i.ref_type, i.ref_id,
         case
           when p.id is null then false
           when i.activity_id is not null then exists (
             select 1 from realisasi.activities a where a.id = i.activity_id
                and a.verified_at > p.frozen_at and a.start_date between p.window_start and p.window_end)
           when i.kpi_code = '1.19.24' and i.bucket = 'numerator' then
             not exists (select 1 from realisasi.kpi_snapshot_items pi where pi.snapshot_id = p.id and pi.kpi_code = '1.19.24'
                            and pi.bucket = 'numerator' and pi.ref_id = i.ref_id)
             and exists (select 1 from realisasi.activity_documents ad join realisasi.activities a on a.id = ad.activity_id
                          where ad.chain_id = i.ref_id::int and a.status = 'verified' and a.verified_at <= p_as_of
                            and a.start_date between w.window_start and w.cutoff_date
                            and a.verified_at > p.frozen_at and a.start_date between p.window_start and p.window_end)
           else false end
    from realisasi.kpi_items(w.window_start, w.window_end, w.cutoff_date, p_ay, p_as_of, null) i
   order by i.kpi_code, i.bucket, i.ref_type, i.ref_id;

  select realisasi._snapshot_label(p_kind, label) into v_label from realisasi.academic_years where id = p_ay;
  perform realisasi._notify_admins('snapshot_frozen', 'Snapshot dibekukan: ' || v_label,
    'Snapshot KPI ' || v_label || ' telah dibekukan.', '/realisasi/laporan?report=arsip&snapshot=' || v_id);
  perform realisasi._notify_viewers('snapshot_frozen', 'Snapshot dibekukan: ' || v_label,
    'Snapshot KPI ' || v_label || ' telah dibekukan.', '/realisasi/laporan?report=arsip&snapshot=' || v_id);
  return v_id;
end $$;

create function realisasi.freeze_snapshot(p_ay int, p_kind realisasi.snapshot_kind, p_as_of timestamptz default null,
                                          p_actor uuid default null) returns uuid
language plpgsql security definer set search_path = realisasi, public, extensions, pg_temp as $$
begin
  if auth.uid() is not null then perform realisasi._require_admin(); end if;
  if p_kind is null then perform realisasi._invalid('kind'); end if;
  return realisasi._freeze(p_ay, p_kind, coalesce(p_as_of, realisasi.now_ts()), coalesce(p_actor, auth.uid()), null, null);
end $$;

create function realisasi.refreeze_snapshot(p_snapshot uuid, p_reason text) returns uuid
language plpgsql security definer set search_path = realisasi, public, extensions, pg_temp as $$
declare v_uid uuid := realisasi._require_admin(); s realisasi.kpi_snapshots;
begin
  if nullif(btrim(p_reason), '') is null then perform realisasi._raise('R58_REASON_REQUIRED', 'Alasan pembekuan ulang wajib diisi.'); end if;
  select * into s from realisasi.kpi_snapshots where id = p_snapshot for update;
  if not found then perform realisasi._not_found(); end if;
  if s.superseded_by is not null then perform realisasi._raise('R58_NOT_LIVE', 'Snapshot ini sudah digantikan.'); end if;
  return realisasi._freeze(s.academic_year_id, s.kind, realisasi.now_ts(), v_uid, btrim(p_reason), s.id);
end $$;

-- Late additions (internal; no permission check) -------------------------------
create function realisasi._snapshot_late_additions(p_snapshot uuid) returns jsonb
language plpgsql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
declare s realisasi.kpi_snapshots; p realisasi.kpi_snapshots; v_plabel text;
begin
  select * into s from realisasi.kpi_snapshots where id = p_snapshot;
  if not found then return '[]'::jsonb; end if;
  p := realisasi._prev_snapshot(s.frozen_at, s.id);
  if p.id is null then return '[]'::jsonb; end if;
  select realisasi._snapshot_label(p.kind, label) into v_plabel from realisasi.academic_years where id = p.academic_year_id;

  return coalesce((select jsonb_agg(jsonb_build_object(
      'activity_id', a.id, 'code', a.code, 'name', a.name,
      'unit_names', coalesce((select jsonb_agg(u.name order by au.is_submitter desc, u.name) from realisasi.activity_units au
                               join public.units u on u.id = au.unit_id where au.activity_id = a.id), '[]'::jsonb),
      'start_date', a.start_date, 'verified_at', a.verified_at,
      'previous_snapshot_id', p.id, 'previous_snapshot_label', v_plabel,
      'counted_in_this_snapshot', x.counted, 'kpi_codes', to_jsonb(x.codes)) order by a.start_date, a.code)
    from (
      select act_id, bool_or(counted) as counted, array_remove(array_agg(distinct code order by code), null) as codes
        from (
          -- (a) items of this snapshot marked late
          select case when i.ref_type = 'participant' then split_part(i.ref_id, ':', 1)::uuid else i.ref_id::uuid end as act_id,
                 true as counted, i.kpi_code as code
            from realisasi.kpi_snapshot_items i
           where i.snapshot_id = s.id and i.is_late_addition and i.ref_type in ('activity','participant')
          union all
          select a.id, true, '1.19.24'
            from realisasi.kpi_snapshot_items i
            join realisasi.activity_documents ad on ad.chain_id = i.ref_id::int
            join realisasi.activities a on a.id = ad.activity_id
           where i.snapshot_id = s.id and i.is_late_addition and i.kpi_code = '1.19.24' and i.bucket = 'numerator'
             and a.status = 'verified' and a.verified_at <= s.frozen_at and a.start_date between s.window_start and s.cutoff_date
             and a.verified_at > p.frozen_at and a.start_date between p.window_start and p.window_end
          union all
          -- (b) late for P's window but outside this snapshot's window
          select a.id, false, null
            from realisasi.activities a
           where a.status = 'verified' and a.verified_at > p.frozen_at and a.verified_at <= s.frozen_at
             and a.start_date between p.window_start and p.window_end
             and a.start_date not between s.window_start and s.window_end) q
       group by act_id) x
    join realisasi.activities a on a.id = x.act_id), '[]'::jsonb);
end $$;

create function realisasi._snapshot_post_freeze_changes(p_snapshot uuid) returns jsonb
language plpgsql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
declare s realisasi.kpi_snapshots; p realisasi.kpi_snapshots;
begin
  select * into s from realisasi.kpi_snapshots where id = p_snapshot;
  if not found then return '[]'::jsonb; end if;
  p := realisasi._prev_snapshot(s.frozen_at, s.id);
  return coalesce((select jsonb_agg(jsonb_build_object(
      'log_id', l.id, 'activity_id', a.id, 'code', a.code, 'name', a.name, 'kind', l.kind, 'track', l.track,
      'action', l.action, 'actor_name', pr.display_name, 'note', l.note, 'diff', l.diff, 'created_at', l.created_at)
      order by l.created_at, l.id)
    from realisasi.activity_log l
    join realisasi.activities a on a.id = l.activity_id
    left join public.profiles pr on pr.id = l.actor_id
   where l.in_frozen_period and l.created_at <= s.frozen_at
     and (p.id is null or l.created_at > p.frozen_at)), '[]'::jsonb);
end $$;

create function realisasi._require_report_reader() returns void
language plpgsql security definer set search_path = realisasi, public, extensions, pg_temp as $$
begin
  perform realisasi._require_uid();
  if realisasi.my_role() not in ('io_staff','io_admin','viewer') then perform realisasi._forbidden(); end if;
end $$;

create function realisasi.snapshot_late_additions(p_snapshot uuid) returns jsonb
language plpgsql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
begin
  perform realisasi._require_report_reader();
  if not exists (select 1 from realisasi.kpi_snapshots where id = p_snapshot) then perform realisasi._not_found(); end if;
  return realisasi._snapshot_late_additions(p_snapshot);
end $$;

create function realisasi.snapshot_post_freeze_changes(p_snapshot uuid) returns jsonb
language plpgsql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
begin
  perform realisasi._require_report_reader();
  if not exists (select 1 from realisasi.kpi_snapshots where id = p_snapshot) then perform realisasi._not_found(); end if;
  return realisasi._snapshot_post_freeze_changes(p_snapshot);
end $$;
