-- 0010_rpc_conflicts: student conflicts in Verifikasi Mobilitas (Revisi V.1, rules 2.1/2.2).
-- A conflict = one NRP claimed by activities of two different units with overlapping dates (_scan_conflicts, 0007).
-- The mobility team looks at both activities' mobility bundles (PDF) and picks the activity that keeps the student.
-- KPI 1.1 then counts the student only on the kept activity; while open, on neither.

create function realisasi._require_mobility() returns uuid
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v uuid := realisasi._require_uid();
begin
  if not realisasi.in_team('mobility') then perform realisasi._forbidden(); end if;
  return v;
end $$;

-- one side of a conflict as jsonb (internal)
create function realisasi._conflict_side(p_activity uuid) returns jsonb
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select jsonb_build_object(
    'id', a.id, 'code', a.code, 'name', a.name, 'status', a.status, 'mobility_status', a.mobility_status,
    'start_date', a.start_date, 'end_date', a.end_date, 'direction', a.direction,
    'unit_id', a.submitter_unit_id, 'unit_name', u.name, 'agenda_name', g.name,
    'bundle', (select jsonb_build_object('filename', f.filename, 'href', realisasi._file_href(f.storage_path))
                 from realisasi.activity_files f
                where f.activity_id = a.id and f.kind = 'mobility_bundle' and f.is_current
                order by f.version desc limit 1))
    from realisasi.activities a
    left join kerjasama.units u on u.id = a.submitter_unit_id
    left join kerjasama.agendas g on g.id = a.agenda_id
   where a.id = p_activity
$$;

-- Conflicts for the mobility queue (all, or those of one activity). p_status: 'open' | 'resolved' | null (both).
create function realisasi.conflict_list(p_activity uuid default null, p_status text default 'open') returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
begin
  perform realisasi._require_mobility();
  if p_status is not null and p_status not in ('open','resolved') then perform realisasi._invalid('status'); end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', c.id, 'nrp', c.nrp, 'status', c.status,
             'student_name', coalesce(st.full_name, c.nrp), 'prodi_name', st.prodi_name,
             'kept_activity_id', c.kept_activity_id, 'note', c.note,
             'resolved_by_name', realisasi._profile_name(c.resolved_by), 'resolved_at', c.resolved_at,
             'created_at', c.created_at,
             'a', realisasi._conflict_side(c.activity_a), 'b', realisasi._conflict_side(c.activity_b))
           order by c.status, c.created_at, c.nrp, c.id)
      from realisasi.participant_conflicts c
      left join mock_baak.students st on st.nrp = c.nrp
     where (p_status is null or c.status::text = p_status)
       and (p_activity is null or p_activity in (c.activity_a, c.activity_b))), '[]'::jsonb);
end $$;

-- Mobility picks the activity whose unit keeps the student (may also change an earlier decision).
create function realisasi.resolve_conflict(p_id bigint, p_kept_activity uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_mobility(); c realisasi.participant_conflicts; v_lost uuid; v_log bigint; x uuid;
        k realisasi.activities; l realisasi.activities;
begin
  select * into c from realisasi.participant_conflicts where id = p_id for update;
  if not found then perform realisasi._not_found(); end if;
  if p_kept_activity is null or p_kept_activity not in (c.activity_a, c.activity_b) then
    perform realisasi._invalid('kept_activity_id');
  end if;
  v_lost := case when p_kept_activity = c.activity_a then c.activity_b else c.activity_a end;
  update realisasi.participant_conflicts
     set status = 'resolved', kept_activity_id = p_kept_activity, note = nullif(btrim(p_note), ''),
         resolved_by = v_uid, resolved_at = realisasi.now_ts()
   where id = p_id;
  select * into k from realisasi.activities where id = p_kept_activity;
  select * into l from realisasi.activities where id = v_lost;
  foreach x in array array[p_kept_activity, v_lost] loop
    v_log := realisasi._log(x, 'verification', 'mobility', 'resolve_conflict', nullif(btrim(p_note), ''),
                            jsonb_build_object('nrp', c.nrp, 'kept', k.code, 'not_counted', l.code));
    -- the decision changes KPI counts of verified activities: a post-freeze change when frozen (R-31)
    update realisasi.activity_log set in_frozen_period = true
     where id = v_log and exists (select 1 from realisasi.activities z where z.id = x and z.status = 'verified')
       and realisasi.in_frozen_period(x);
  end loop;
  perform realisasi._notify_unit(l.submitter_unit_id, 'conflict_resolved', 'Mahasiswa dihitung di unit lain: ' || l.code,
    format('Mahasiswa %s juga diklaim kegiatan %s (%s). Tim Mobilitas menetapkan mahasiswa ini dihitung pada kegiatan tersebut.',
           c.nrp, k.code, k.name), '/realisasi/kegiatan/' || l.id);
  return jsonb_build_object('id', p_id, 'kept_activity_id', p_kept_activity, 'not_counted_activity_id', v_lost,
                            'open_remaining', (select count(*) from realisasi.participant_conflicts o where o.status = 'open'
                                                 and (o.activity_a in (p_kept_activity, v_lost) or o.activity_b in (p_kept_activity, v_lost))));
end $$;
