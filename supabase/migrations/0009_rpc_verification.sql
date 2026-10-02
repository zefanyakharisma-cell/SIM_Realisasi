-- 0009_rpc_verification: Mobility track (the only verification since Revisi V.1) and post-verification edits.

create function realisasi._notify_activity_unit(p_activity uuid, p_kind text, p_title_prefix text, p_body text, p_link text) returns void
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare a realisasi.activities;
begin
  select * into a from realisasi.activities where id = p_activity;
  perform realisasi._notify_unit(a.submitter_unit_id, p_kind, p_title_prefix || a.code, p_body,
                                 replace(p_link, '{id}', a.id::text));
end $$;

create function realisasi._require_team(p_activity uuid, p_team realisasi.team) returns realisasi.activities
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare a realisasi.activities;
begin
  perform realisasi._require_uid();
  a := realisasi._get_activity(p_activity);
  if not realisasi.in_team(p_team) then
    if a.status = 'verified' and realisasi._is_unit_editor(p_activity) then
      perform realisasi._raise('R29_EDIT_FORBIDDEN', 'Hanya tim IO terkait yang dapat mengubah kegiatan terverifikasi.');
    end if;
    perform realisasi._forbidden();
  end if;
  return a;
end $$;

create function realisasi._track_not_pending() returns void
language sql security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select realisasi._raise('TRACK_NOT_PENDING', 'Jalur verifikasi ini tidak sedang menunggu verifikasi.')
$$;

create function realisasi._after_track_change(p_activity uuid, p_was_verified boolean) returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare a realisasi.activities;
begin
  select * into a from realisasi.activities where id = p_activity;
  if a.status = 'verified' and not p_was_verified then
    perform realisasi._notify_unit(a.submitter_unit_id, 'activity_verified', 'Kegiatan terverifikasi: ' || a.code,
      'Kegiatan "' || a.name || '" telah terverifikasi.', '/realisasi/kegiatan/' || a.id);
  end if;
  return realisasi._status_result(p_activity);
end $$;

-- Mobility --------------------------------------------------------------------
create function realisasi.mobility_approve(p_activity uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare a realisasi.activities; v_uid uuid := auth.uid(); v_ver uuid;
begin
  a := realisasi._require_team(p_activity, 'mobility');
  if a.status = 'draft' then perform realisasi._state_invalid(); end if;
  if a.mobility_status <> 'pending' then perform realisasi._track_not_pending(); end if;
  select id into v_ver from realisasi.participant_set_versions
   where activity_id = p_activity and status = 'pending' order by version desc limit 1;
  if v_ver is null then perform realisasi._state_invalid(); end if;
  -- Revisi V.1 rule 2.1: a student claimed by another unit must be assigned first
  if realisasi.activity_open_conflicts(p_activity) > 0 then
    perform realisasi._raise('CONFLICT_OPEN',
      'Masih ada mahasiswa yang juga diklaim unit lain. Pilih kegiatan yang diakui di bagian Duplikat Mahasiswa terlebih dahulu.');
  end if;
  update realisasi.participant_set_versions
     set status = 'approved', reviewed_by = v_uid, reviewed_at = realisasi.now_ts(), review_note = nullif(btrim(p_note), '')
   where id = v_ver;
  update realisasi.activities set mobility_status = 'approved' where id = p_activity;
  perform realisasi._log(p_activity, 'verification', 'mobility', 'approve', nullif(btrim(p_note), ''),
                         jsonb_build_object('version', (select version from realisasi.participant_set_versions where id = v_ver)));
  return realisasi._after_track_change(p_activity, a.status = 'verified');
end $$;

-- Revisi V.1: one revision note for the whole submission (no per-row notes)
create function realisasi.mobility_request_revision(p_activity uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare a realisasi.activities; v_uid uuid := auth.uid(); v_ver uuid;
begin
  a := realisasi._require_team(p_activity, 'mobility');
  if a.status = 'draft' then perform realisasi._state_invalid(); end if;
  if a.mobility_status <> 'pending' then perform realisasi._track_not_pending(); end if;
  if nullif(btrim(p_note), '') is null then perform realisasi._raise('R27_NOTE_REQUIRED', 'Catatan revisi wajib diisi.'); end if;
  select id into v_ver from realisasi.participant_set_versions
   where activity_id = p_activity and status = 'pending' order by version desc limit 1;
  if v_ver is null then perform realisasi._state_invalid(); end if;
  update realisasi.participant_set_versions
     set status = 'revision_requested', reviewed_by = v_uid, reviewed_at = realisasi.now_ts(), review_note = btrim(p_note)
   where id = v_ver;
  update realisasi.activities set mobility_status = 'revision_requested' where id = p_activity;
  perform realisasi._log(p_activity, 'verification', 'mobility', 'request_revision', btrim(p_note));
  perform realisasi._notify_activity_unit(p_activity, 'revision_requested', 'Perlu revisi: ', btrim(p_note), '/realisasi/kegiatan/{id}/revisi');
  return realisasi._status_result(p_activity);
end $$;

-- Post-verification edits (R-29..R-31) ------------------------------------------
-- R-11/R-12 for a participant set version against an activity's Jenis + direction (raises; used when Jenis or
-- direction changes after verification, M1, and by commit_participant_edit)
create function realisasi._check_pset_for_activity(p_version uuid, p_activity uuid) returns void
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare a realisasi.activities;
begin
  select * into a from realisasi.activities where id = p_activity;
  if not realisasi.agenda_is_mobility(a.agenda_id) then return; end if;
  if coalesce(realisasi._pset_rows(p_version), 0) = 0 then
    perform realisasi._raise('R11_PARTICIPANTS_REQUIRED', 'Kegiatan mobilitas wajib memiliki data peserta.');
  end if;
  if a.direction = 'outbound' and not exists (select 1 from realisasi.participant_students where set_version_id = p_version and section = 'internal') then
    perform realisasi._raise('R12_OUTBOUND_STUDENT_REQUIRED', 'Kegiatan outbound wajib memiliki minimal satu mahasiswa PETRA.');
  end if;
  if a.direction = 'inbound' and not exists (select 1 from realisasi.participant_students where set_version_id = p_version and section = 'inbound') then
    perform realisasi._raise('R12_INBOUND_STUDENT_REQUIRED', 'Kegiatan inbound wajib memiliki minimal satu mahasiswa inbound.');
  end if;
end $$;

create function realisasi.edit_verified_activity(p_id uuid, p_data jsonb, p_note text) returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare a realisasi.activities; v_res jsonb; v_end date; v_frozen_before boolean; v_frozen boolean := false; v_log bigint;
begin
  -- Revisi V.1: only IO Admin edits the Detail of a verified activity
  perform realisasi._require_uid();
  a := realisasi._get_activity(p_id);
  if realisasi.my_role() is distinct from 'io_admin' then
    if realisasi._is_unit_editor(p_id) or realisasi.is_io() then
      perform realisasi._raise('R29_EDIT_FORBIDDEN', 'Hanya Admin IO yang dapat mengubah kegiatan terverifikasi.');
    end if;
    perform realisasi._forbidden();
  end if;
  if a.status <> 'verified' then perform realisasi._state_invalid(); end if;
  if p_data is null or jsonb_typeof(p_data) <> 'object' then perform realisasi._invalid('payload'); end if;
  if p_data ? 'submitter_unit_id' and (p_data ->> 'submitter_unit_id') is distinct from a.submitter_unit_id::text then
    perform realisasi._invalid('submitter_unit_id');
  end if;
  begin v_end := coalesce((p_data ->> 'end_date')::date, a.end_date); exception when others then perform realisasi._invalid('end_date'); end;
  if v_end > realisasi.today() then
    perform realisasi._raise('R08_END_AFTER_TODAY', 'Kegiatan belum selesai. Tanggal selesai harus hari ini atau sebelumnya.');
  end if;
  v_frozen_before := realisasi.in_frozen_period(p_id);
  v_res := realisasi._apply_activity_payload(p_id, p_data - 'submitter_unit_id', 'verified');
  if (select academic_year_id from realisasi.activities where id = p_id) is null then
    perform realisasi._raise('R09_NO_ACADEMIC_YEAR', 'Tanggal mulai berada di luar tahun akademik yang terdaftar. Hubungi Admin IO.');
  end if;
  -- M1: a Jenis/direction change must still satisfy R-11/R-12 with the approved participant set
  if (v_res -> 'diff') ?| array['agenda_id','direction'] then
    perform realisasi._check_pset_for_activity(
      (select id from realisasi.participant_set_versions where activity_id = p_id and status = 'approved'), p_id);
  end if;
  -- dates/direction decide which students overlap with other units
  if (v_res -> 'diff') ?| array['start_date','end_date','direction','agenda_id'] then
    perform realisasi._scan_conflicts(p_id);
  end if;
  if (v_res -> 'diff') <> '{}'::jsonb then
    v_log := realisasi._log(p_id, 'update', null, 'edit', nullif(btrim(p_note), ''), v_res -> 'diff');
    update realisasi.activity_log set in_frozen_period = in_frozen_period or v_frozen_before where id = v_log
      returning in_frozen_period into v_frozen;
  end if;
  return jsonb_build_object('diff', v_res -> 'diff', 'in_frozen_period', v_frozen);
end $$;

create function realisasi.commit_participant_edit(p_activity uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare a realisasi.activities; v_uid uuid := auth.uid(); v_draft uuid; v_prev uuid;
        v_list text; v_diff jsonb; v_log bigint; v_frozen boolean; v_ver int;
begin
  a := realisasi._require_team(p_activity, 'mobility');
  if a.status <> 'verified' then perform realisasi._state_invalid(); end if;
  v_draft := realisasi._draft_pset(p_activity);
  if v_draft is null then perform realisasi._state_invalid(); end if;

  select string_agg(nrp, ', ' order by id) into v_list from realisasi.participant_students ps
   where set_version_id = v_draft and not exists (select 1 from mock_baak.students s where s.nrp = ps.nrp);
  if v_list is not null then perform realisasi._raise('R16_NRP_NOT_FOUND', format('NRP tidak ditemukan di data BAAK: %s.', v_list)); end if;
  select string_agg(nrp, ', ' order by id) into v_list from realisasi.participant_students ps
   where set_version_id = v_draft and section = 'inbound'
     and home_institution is null;
  if v_list is not null then
    perform realisasi._raise('R17_INBOUND_DATA_REQUIRED', format('Mahasiswa inbound %s wajib memiliki institusi asal.', v_list));
  end if;
  select string_agg(employee_id, ', ' order by id) into v_list from realisasi.participant_staff st
   where set_version_id = v_draft and not exists (select 1 from mock_hr.employees e where e.employee_id = st.employee_id);
  if v_list is not null then perform realisasi._raise('R19_EMPLOYEE_NOT_FOUND', format('ID pegawai tidak ditemukan di data SDM: %s.', v_list)); end if;
  perform realisasi._check_pset_for_activity(v_draft, p_activity);    -- R-11 (L9) and R-12

  select id into v_prev from realisasi.participant_set_versions where activity_id = p_activity and status = 'approved';
  v_diff := jsonb_build_object(
    'students', jsonb_build_object(
      'added', coalesce((select jsonb_agg(nrp order by nrp) from realisasi.participant_students n where n.set_version_id = v_draft
                          and not exists (select 1 from realisasi.participant_students o where o.set_version_id = v_prev and o.nrp = n.nrp)), '[]'),
      'removed', coalesce((select jsonb_agg(nrp order by nrp) from realisasi.participant_students o where o.set_version_id = v_prev
                          and not exists (select 1 from realisasi.participant_students n where n.set_version_id = v_draft and n.nrp = o.nrp)), '[]')),
    'staff', jsonb_build_object(
      'added', coalesce((select jsonb_agg(employee_id order by employee_id) from realisasi.participant_staff n where n.set_version_id = v_draft
                          and not exists (select 1 from realisasi.participant_staff o where o.set_version_id = v_prev and o.employee_id = n.employee_id)), '[]'),
      'removed', coalesce((select jsonb_agg(employee_id order by employee_id) from realisasi.participant_staff o where o.set_version_id = v_prev
                          and not exists (select 1 from realisasi.participant_staff n where n.set_version_id = v_draft and n.employee_id = o.employee_id)), '[]')));

  update realisasi.participant_set_versions
     set status = 'approved', submitted_by = v_uid, submitted_at = realisasi.now_ts(),
         reviewed_by = v_uid, reviewed_at = realisasi.now_ts(), review_note = nullif(btrim(p_note), '')
   where id = v_draft
  returning version into v_ver;
  if a.mobility_status <> 'approved' then
    update realisasi.activities set mobility_status = 'approved' where id = p_activity;
  end if;
  v_log := realisasi._log(p_activity, 'update', 'mobility', 'edit', nullif(btrim(p_note), ''), v_diff);
  perform realisasi._scan_conflicts(p_activity);
  select in_frozen_period into v_frozen from realisasi.activity_log where id = v_log;
  return jsonb_build_object('version', v_ver, 'diff', v_diff, 'in_frozen_period', v_frozen);
end $$;
