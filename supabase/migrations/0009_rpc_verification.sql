-- 0009_rpc_verification: Partnership / Mobility tracks and post-verification edits (R-23..R-31).

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

-- Partnership -----------------------------------------------------------------
create function realisasi.partnership_approve(p_activity uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare a realisasi.activities;
begin
  a := realisasi._require_team(p_activity, 'partnership');
  if a.status in ('draft','rejected') then perform realisasi._state_invalid(); end if;
  if a.partnership_status <> 'pending' then perform realisasi._track_not_pending(); end if;
  update realisasi.activities set partnership_status = 'approved' where id = p_activity;
  perform realisasi._log(p_activity, 'verification', 'partnership', 'approve', nullif(btrim(p_note), ''));
  return realisasi._after_track_change(p_activity, false);
end $$;

create function realisasi.partnership_request_revision(p_activity uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare a realisasi.activities;
begin
  a := realisasi._require_team(p_activity, 'partnership');
  if a.status in ('draft','rejected') then perform realisasi._state_invalid(); end if;
  if a.partnership_status <> 'pending' then perform realisasi._track_not_pending(); end if;
  if nullif(btrim(p_note), '') is null then perform realisasi._raise('R27_NOTE_REQUIRED', 'Catatan revisi wajib diisi.'); end if;
  update realisasi.activities set partnership_status = 'revision_requested' where id = p_activity;
  perform realisasi._log(p_activity, 'verification', 'partnership', 'request_revision', btrim(p_note));
  perform realisasi._notify_activity_unit(p_activity, 'revision_requested', 'Perlu revisi: ', btrim(p_note), '/realisasi/kegiatan/{id}/revisi');
  return realisasi._status_result(p_activity);
end $$;

create function realisasi.partnership_reject(p_activity uuid, p_reason text, p_note text) returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare a realisasi.activities; v_known jsonb;
begin
  a := realisasi._require_team(p_activity, 'partnership');
  if a.status in ('draft','rejected') then perform realisasi._state_invalid(); end if;
  if a.partnership_status <> 'pending' then perform realisasi._track_not_pending(); end if;
  if p_reason is null or p_reason not in ('duplicate','not_partnership','wrong_agreement','other') then
    perform realisasi._raise('R26_REASON_REQUIRED', 'Pilih alasan penolakan.');
  end if;
  if nullif(btrim(p_note), '') is null then perform realisasi._raise('R26_NOTE_REQUIRED', 'Catatan penolakan wajib diisi.'); end if;
  update realisasi.activities set partnership_status = 'rejected', rejection_reason = p_reason where id = p_activity;
  perform realisasi._log(p_activity, 'verification', 'partnership', 'reject', btrim(p_note), jsonb_build_object('reason', p_reason));
  -- a rejected activity no longer represents any known activity (H3, R-50): revert its matches
  with u as (update realisasi.known_activities set status = 'unmatched', matched_activity_id = null
              where matched_activity_id = p_activity returning id)
  select jsonb_agg(id order by id) into v_known from u;
  if v_known is not null then
    perform realisasi._log(p_activity, 'verification', 'partnership', 'unmatch_known', null, jsonb_build_object('known_activity_ids', v_known));
  end if;
  perform realisasi._notify_activity_unit(p_activity, 'activity_rejected', 'Kegiatan ditolak: ', btrim(p_note), '/realisasi/kegiatan/{id}');
  return realisasi._status_result(p_activity);
end $$;

-- Mobility --------------------------------------------------------------------
create function realisasi.mobility_approve(p_activity uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare a realisasi.activities; v_uid uuid := auth.uid(); v_ver uuid;
begin
  a := realisasi._require_team(p_activity, 'mobility');
  if a.status in ('draft','rejected') then perform realisasi._state_invalid(); end if;
  if a.mobility_status <> 'pending' then perform realisasi._track_not_pending(); end if;
  select id into v_ver from realisasi.participant_set_versions
   where activity_id = p_activity and status = 'pending' order by version desc limit 1;
  if v_ver is null then perform realisasi._state_invalid(); end if;
  update realisasi.participant_set_versions
     set status = 'approved', reviewed_by = v_uid, reviewed_at = realisasi.now_ts(), review_note = nullif(btrim(p_note), '')
   where id = v_ver;
  update realisasi.activities set mobility_status = 'approved' where id = p_activity;
  perform realisasi._log(p_activity, 'verification', 'mobility', 'approve', nullif(btrim(p_note), ''),
                         jsonb_build_object('version', (select version from realisasi.participant_set_versions where id = v_ver)));
  return realisasi._after_track_change(p_activity, a.status = 'verified');
end $$;

create function realisasi.mobility_request_revision(p_activity uuid, p_note text, p_row_notes jsonb default '[]') returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare a realisasi.activities; v_uid uuid := auth.uid(); v_ver uuid; r jsonb;
begin
  a := realisasi._require_team(p_activity, 'mobility');
  if a.status in ('draft','rejected') then perform realisasi._state_invalid(); end if;
  if a.mobility_status <> 'pending' then perform realisasi._track_not_pending(); end if;
  if nullif(btrim(p_note), '') is null then perform realisasi._raise('R27_NOTE_REQUIRED', 'Catatan revisi wajib diisi.'); end if;
  if p_row_notes is not null and jsonb_typeof(p_row_notes) <> 'array' then perform realisasi._invalid('row_notes'); end if;
  select id into v_ver from realisasi.participant_set_versions
   where activity_id = p_activity and status = 'pending' order by version desc limit 1;
  if v_ver is null then perform realisasi._state_invalid(); end if;
  for r in select * from jsonb_array_elements(coalesce(p_row_notes, '[]'::jsonb)) loop
    if r ->> 'kind' = 'student' then
      update realisasi.participant_students set row_note = nullif(btrim(r ->> 'note'), '')
       where set_version_id = v_ver and nrp = upper(r ->> 'id');
    elsif r ->> 'kind' = 'staff' then
      update realisasi.participant_staff set row_note = nullif(btrim(r ->> 'note'), '')
       where set_version_id = v_ver and employee_id = upper(r ->> 'id');
    else
      perform realisasi._invalid('row_notes');
    end if;
  end loop;
  update realisasi.participant_set_versions
     set status = 'revision_requested', reviewed_by = v_uid, reviewed_at = realisasi.now_ts(), review_note = btrim(p_note)
   where id = v_ver;
  update realisasi.activities set mobility_status = 'revision_requested' where id = p_activity;
  perform realisasi._log(p_activity, 'verification', 'mobility', 'request_revision', btrim(p_note),
                         case when jsonb_array_length(coalesce(p_row_notes, '[]'::jsonb)) > 0 then jsonb_build_object('row_notes', p_row_notes) end);
  perform realisasi._notify_activity_unit(p_activity, 'revision_requested', 'Perlu revisi: ', btrim(p_note), '/realisasi/kegiatan/{id}/revisi');
  return realisasi._status_result(p_activity);
end $$;

-- Post-verification edits (R-29..R-31) ------------------------------------------
-- R-11/R-12 for a participant set version against a Jenis (raises; used when Jenis changes after verification, M1,
-- and by commit_participant_edit)
create function realisasi._check_pset_for_type(p_version uuid, p_type int) returns void
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare t realisasi.activity_types;
begin
  select * into t from realisasi.activity_types where id = p_type;
  if t.requires_mobility_review and coalesce(realisasi._pset_rows(p_version), 0) = 0 then
    perform realisasi._raise('R11_PARTICIPANTS_REQUIRED', 'Jenis kegiatan ini wajib memiliki data peserta.');
  end if;
  if t.direction = 'outbound' and not exists (select 1 from realisasi.participant_students where set_version_id = p_version and section = 'internal') then
    perform realisasi._raise('R12_OUTBOUND_STUDENT_REQUIRED', 'Kegiatan outbound wajib memiliki minimal satu mahasiswa PETRA.');
  end if;
  if t.direction = 'inbound' and not exists (select 1 from realisasi.participant_students where set_version_id = p_version and section = 'inbound') then
    perform realisasi._raise('R12_INBOUND_STUDENT_REQUIRED', 'Kegiatan inbound wajib memiliki minimal satu mahasiswa inbound.');
  end if;
end $$;

create function realisasi.edit_verified_activity(p_id uuid, p_data jsonb, p_note text) returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare a realisasi.activities; v_res jsonb; v_end date; v_frozen_before boolean; v_frozen boolean := false; v_log bigint;
begin
  a := realisasi._require_team(p_id, 'partnership');
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
  -- M1: a Jenis change must still satisfy R-11/R-12 with the approved participant set
  if (v_res -> 'diff') ? 'type_id' then
    perform realisasi._check_pset_for_type(
      (select id from realisasi.participant_set_versions where activity_id = p_id and status = 'approved'),
      (select type_id from realisasi.activities where id = p_id));
  end if;
  -- L3: name/date/agreement edits can create new duplicate candidates
  if (v_res -> 'diff') ?| array['name','start_date','end_date','document_ids'] then
    perform realisasi._scan_duplicates(p_id);
  end if;
  if (v_res -> 'diff') <> '{}'::jsonb then
    v_log := realisasi._log(p_id, 'update', 'partnership', 'edit', nullif(btrim(p_note), ''), v_res -> 'diff');
    update realisasi.activity_log set in_frozen_period = in_frozen_period or v_frozen_before where id = v_log
      returning in_frozen_period into v_frozen;
  end if;
  return jsonb_build_object('diff', v_res -> 'diff', 'in_frozen_period', v_frozen);
end $$;

create function realisasi.commit_participant_edit(p_activity uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare a realisasi.activities; t realisasi.activity_types; v_uid uuid := auth.uid(); v_draft uuid; v_prev uuid;
        v_list text; v_diff jsonb; v_log bigint; v_frozen boolean; v_ver int;
begin
  a := realisasi._require_team(p_activity, 'mobility');
  if a.status <> 'verified' then perform realisasi._state_invalid(); end if;
  v_draft := realisasi._draft_pset(p_activity);
  if v_draft is null then perform realisasi._state_invalid(); end if;
  select * into t from realisasi.activity_types where id = a.type_id;

  select string_agg(nrp, ', ' order by id) into v_list from realisasi.participant_students ps
   where set_version_id = v_draft and not exists (select 1 from mock_baak.students s where s.nrp = ps.nrp);
  if v_list is not null then perform realisasi._raise('R16_NRP_NOT_FOUND', format('NRP tidak ditemukan di data BAAK: %s.', v_list)); end if;
  select string_agg(nrp, ', ' order by id) into v_list from realisasi.participant_students ps
   where set_version_id = v_draft and section = 'inbound'
     and (home_institution is null or transcript_path is null or not exists (select 1 from realisasi.file_blobs b where b.path = ps.transcript_path));
  if v_list is not null then
    perform realisasi._raise('R17_INBOUND_DATA_REQUIRED', format('Mahasiswa inbound %s wajib memiliki institusi asal dan transkrip (PDF).', v_list));
  end if;
  select string_agg(employee_id, ', ' order by id) into v_list from realisasi.participant_staff st
   where set_version_id = v_draft and not exists (select 1 from mock_hr.employees e where e.employee_id = st.employee_id);
  if v_list is not null then perform realisasi._raise('R19_EMPLOYEE_NOT_FOUND', format('ID pegawai tidak ditemukan di data SDM: %s.', v_list)); end if;
  perform realisasi._check_pset_for_type(v_draft, a.type_id);    -- R-11 (L9) and R-12

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
  select in_frozen_period into v_frozen from realisasi.activity_log where id = v_log;
  return jsonb_build_object('version', v_ver, 'diff', v_diff, 'in_frozen_period', v_frozen);
end $$;
