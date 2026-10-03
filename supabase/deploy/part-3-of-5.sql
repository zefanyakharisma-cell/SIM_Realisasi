-- SIM Realisasi Supabase install, PART 3 OF 5 (commit b8a514a).
-- Run parts 1..5 in order in Supabase Dashboard -> SQL Editor. If any part fails, start again from part 1.
begin;

-- >>> supabase/migrations/0008_rpc_files.sql
-- 0008_rpc_files: storage emulation (file_blobs) + activity file registry.

create function realisasi._path_activity(p_path text) returns uuid
language plpgsql immutable set search_path = realisasi, extensions, public, pg_temp as $$
begin
  return split_part(p_path, '/', 2)::uuid;
exception when others then
  return null;
end $$;

create function realisasi.can_read_file(p_path text) returns boolean
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_act uuid := realisasi._path_activity(p_path); v_bucket text := split_part(p_path, '/', 1);
begin
  if auth.uid() is null or v_act is null then return false; end if;
  if v_bucket = 'realisasi-files' then
    return realisasi.can_view_activity(v_act)
       and exists (select 1 from realisasi.activity_files f where f.activity_id = v_act and f.storage_path = p_path);
  elsif v_bucket = 'realisasi-transcripts' then
    -- the mobility bundle (transcripts, poster, documentation; Revisi V.1) is personal data
    return realisasi.can_view_participants(v_act)
       and exists (select 1 from realisasi.activity_files f where f.activity_id = v_act and f.storage_path = p_path);
  end if;
  return false;
end $$;

create function realisasi.storage_put(p_path text, p_mime text, p_data bytea) returns void
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_uid(); v_bucket text := split_part(p_path, '/', 1);
        v_act uuid := realisasi._path_activity(p_path); v_seg3 text := split_part(p_path, '/', 3);
        v_ok boolean := false;
begin
  if v_bucket not in ('realisasi-files','realisasi-transcripts') or v_act is null or split_part(p_path, '/', 4) = ''
     or p_path like '%..%' then
    perform realisasi._invalid('path');
  end if;
  if p_data is null then perform realisasi._invalid('data'); end if;
  if length(p_data) > 10485760 then perform realisasi._raise('R13_FILE_TOO_LARGE', 'Ukuran berkas melebihi 10 MB.'); end if;
  if v_bucket = 'realisasi-transcripts' and p_mime is distinct from 'application/pdf' then
    perform realisasi._raise('R13_FILE_TYPE', 'Format berkas tidak diizinkan (PDF).');
  end if;
  if v_bucket = 'realisasi-files' and p_mime not in ('application/pdf','image/jpeg','image/png') then
    perform realisasi._raise('R13_FILE_TYPE', 'Format berkas tidak diizinkan (PDF, JPG, PNG).');
  end if;
  if p_mime = 'application/pdf' and substring(p_data from 1 for 5) <> '\x255044462d'::bytea then
    perform realisasi._raise('R13_FILE_TYPE', 'Format berkas tidak diizinkan (PDF).');
  end if;

  if exists (select 1 from realisasi.activities where id = v_act) then
    if v_bucket = 'realisasi-files' then
      v_ok := v_seg3 in ('ia','ir','evidence') and realisasi._can_write_files(v_act);
    else
      v_ok := v_seg3 = 'mobility_bundle' and realisasi._can_write_files(v_act);
    end if;
  end if;
  if not v_ok then perform realisasi._raise('FILE_FORBIDDEN', 'Anda tidak memiliki akses ke berkas ini.'); end if;

  -- Blobs are immutable once referenced (H5; R-30/R-31/R-64). An unreferenced upload may be retried by its uploader.
  if exists (select 1 from realisasi.file_blobs b where b.path = p_path) then
    if exists (select 1 from realisasi.activity_files f where f.storage_path = p_path)
       or (select b.created_by from realisasi.file_blobs b where b.path = p_path) is distinct from v_uid then
      perform realisasi._raise('FILE_FORBIDDEN', 'Anda tidak memiliki akses ke berkas ini.');
    end if;
    update realisasi.file_blobs set data = p_data, mime = p_mime, size_bytes = length(p_data), created_at = realisasi.now_ts()
     where path = p_path;
  else
    insert into realisasi.file_blobs (path, bucket, data, mime, size_bytes, created_by, created_at)
    values (p_path, v_bucket, p_data, p_mime, length(p_data), v_uid, realisasi.now_ts());
  end if;
end $$;

create function realisasi.storage_get(p_path text) returns table(data bytea, mime text, size_bytes int)
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
begin
  perform realisasi._require_uid();
  if not realisasi.can_read_file(p_path) then
    perform realisasi._raise('FILE_FORBIDDEN', 'Anda tidak memiliki akses ke berkas ini.');
  end if;
  return query select b.data, b.mime, b.size_bytes from realisasi.file_blobs b where b.path = p_path;
  if not found then perform realisasi._raise('FILE_NOT_FOUND', 'Berkas tidak ditemukan.'); end if;
end $$;

create function realisasi._file_href(p_path text) returns text
language sql immutable set search_path = realisasi, extensions, public, pg_temp as $$
  select '/api/files/' || p_path
$$;

-- log a file change according to the activity state (internal)
create function realisasi._log_file(p_activity uuid, p_action text, p_detail jsonb) returns void
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare a realisasi.activities;
begin
  select * into a from realisasi.activities where id = p_activity;
  if a.status = 'verified' then
    perform realisasi._log(p_activity, 'update', null, p_action, null, p_detail);
  elsif a.mobility_status = 'revision_requested' and a.status <> 'draft' then
    perform realisasi._log(p_activity, 'revision', 'mobility', p_action, null, p_detail);
  end if;
end $$;

create function realisasi._check_file_write(p_activity uuid) returns realisasi.activities
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare a realisasi.activities;
begin
  a := realisasi._get_activity(p_activity);
  if not realisasi._can_write_files(p_activity) then
    if a.status = 'verified' and realisasi._is_unit_editor(p_activity) then
      perform realisasi._raise('R29_EDIT_FORBIDDEN', 'Hanya Admin IO yang dapat mengubah berkas kegiatan terverifikasi.');
    end if;
    if realisasi._is_unit_editor(p_activity) then perform realisasi._state_invalid(); end if;
    perform realisasi._forbidden();
  end if;
  return a;
end $$;

create function realisasi.register_activity_file(p_activity uuid, p_kind realisasi.file_kind, p_storage_path text,
                                                 p_filename text, p_size_bytes int, p_mime text) returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_uid(); a realisasi.activities; v_ver int; v_id bigint; b realisasi.file_blobs;
begin
  a := realisasi._check_file_write(p_activity);
  if p_kind is null then perform realisasi._invalid('kind'); end if;
  if p_storage_path is null or p_storage_path not like
       (case when p_kind = 'mobility_bundle' then 'realisasi-transcripts/' else 'realisasi-files/' end
        || p_activity::text || '/' || p_kind::text || '/%') then
    perform realisasi._invalid('storage_path');
  end if;
  select * into b from realisasi.file_blobs where path = p_storage_path;
  if not found then perform realisasi._raise('FILE_NOT_FOUND', 'Berkas tidak ditemukan.'); end if;
  -- type and size always come from the stored blob; the caller's p_mime/p_size_bytes are ignored (M8, R-13)
  if p_kind in ('ia','ir','mobility_bundle') and (b.mime <> 'application/pdf' or substring(b.data from 1 for 5) <> '\x255044462d'::bytea) then
    perform realisasi._raise('R13_FILE_TYPE', 'Format berkas tidak diizinkan (PDF).');
  end if;
  if p_kind = 'evidence' and b.mime not in ('application/pdf','image/jpeg','image/png') then
    perform realisasi._raise('R13_FILE_TYPE', 'Format berkas tidak diizinkan (PDF, JPG, PNG).');
  end if;
  if p_kind in ('ia','ir','mobility_bundle') then
    select coalesce(max(version), 0) + 1 into v_ver from realisasi.activity_files where activity_id = p_activity and kind = p_kind;
    update realisasi.activity_files set is_current = false where activity_id = p_activity and kind = p_kind and is_current;
  else
    v_ver := 1;
  end if;
  insert into realisasi.activity_files (activity_id, kind, version, storage_path, filename, size_bytes, mime, is_current, uploaded_by, uploaded_at)
  values (p_activity, p_kind, v_ver, p_storage_path, coalesce(nullif(btrim(p_filename), ''), split_part(p_storage_path, '/', 4)),
          b.size_bytes, b.mime, true, v_uid, realisasi.now_ts())
  returning id into v_id;
  perform realisasi._log_file(p_activity, 'file_upload', jsonb_build_object('kind', p_kind, 'filename', p_filename, 'version', v_ver));
  return jsonb_build_object('id', v_id, 'kind', p_kind, 'version', v_ver, 'storage_path', p_storage_path,
                            'href', realisasi._file_href(p_storage_path));
end $$;

create function realisasi.add_evidence_link(p_activity uuid, p_url text, p_label text) returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_uid(); a realisasi.activities; v_id bigint;
begin
  a := realisasi._check_file_write(p_activity);
  if p_url is null or not (p_url ~* '^https?://\S+$') then perform realisasi._invalid('url'); end if;
  insert into realisasi.activity_files (activity_id, kind, version, url, filename, is_current, uploaded_by, uploaded_at)
  values (p_activity, 'evidence', 1, p_url, coalesce(nullif(btrim(p_label), ''), p_url), true, v_uid, realisasi.now_ts())
  returning id into v_id;
  perform realisasi._log_file(p_activity, 'file_upload', jsonb_build_object('kind', 'evidence', 'filename', coalesce(p_label, p_url), 'version', 1));
  return jsonb_build_object('id', v_id, 'kind', 'evidence', 'version', 1, 'storage_path', null, 'href', p_url);
end $$;

create function realisasi.remove_activity_file(p_file_id bigint) returns void
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_uid(); f realisasi.activity_files;
begin
  select * into f from realisasi.activity_files where id = p_file_id;
  if not found or not realisasi.can_view_activity(f.activity_id) then perform realisasi._not_found(); end if;
  perform realisasi._check_file_write(f.activity_id);
  if f.kind <> 'evidence' or not f.is_current then perform realisasi._state_invalid(); end if;
  update realisasi.activity_files set is_current = false where id = p_file_id;
  perform realisasi._log_file(f.activity_id, 'file_remove', jsonb_build_object('kind', f.kind, 'filename', f.filename, 'version', f.version));
end $$;

-- >>> supabase/migrations/0009_rpc_verification.sql
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

-- >>> supabase/migrations/0010_rpc_conflicts.sql
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

-- >>> supabase/migrations/0011_rpc_admin.sql
-- 0011_rpc_admin: settings, calendar, Jenis Kegiatan rules (io_admin) + notifications / export log.

create function realisasi._require_admin() returns uuid
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v uuid := realisasi._require_uid();
begin
  if realisasi.my_role() is distinct from 'io_admin' then perform realisasi._forbidden(); end if;
  return v;
end $$;

create function realisasi._settings_invalid(p_key text) returns void
language sql security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select realisasi._raise('SETTINGS_INVALID', format('Pengaturan %s tidak valid.', p_key), jsonb_build_object('key', p_key))
$$;

create function realisasi.update_settings(p_values jsonb) returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_admin(); k text; v jsonb;
  c_int text[] := array['grace_period_months','reporting_deadline_days','revision_reminder_days',
                        'deadline_reminder_before_days'];
begin
  if p_values is null or jsonb_typeof(p_values) <> 'object' then perform realisasi._settings_invalid('payload'); end if;
  for k, v in select * from jsonb_each(p_values) loop
    if k = any(c_int) then
      if jsonb_typeof(v) <> 'number' or (v #>> '{}')::numeric < 0 or (v #>> '{}')::numeric <> trunc((v #>> '{}')::numeric) then
        perform realisasi._settings_invalid(k);
      end if;
    elsif k = 'demo_today' then
      if jsonb_typeof(v) not in ('null','string') then perform realisasi._settings_invalid(k); end if;
      if jsonb_typeof(v) = 'string' then
        -- M9: time travel only where the deployment enables it (demo); clearing it is always allowed
        if not realisasi.demo_time_travel_enabled() then perform realisasi._settings_invalid(k); end if;
        begin perform (v #>> '{}')::date; exception when others then perform realisasi._settings_invalid(k); end;
        if (v #>> '{}') !~ '^\d{4}-\d{2}-\d{2}$' then perform realisasi._settings_invalid(k); end if;
      end if;
    else
      perform realisasi._settings_invalid(k);
    end if;
  end loop;
  insert into realisasi.settings (key, value, updated_by)
  select key, value, v_uid from jsonb_each(p_values)
  on conflict (key) do update set value = excluded.value, updated_by = excluded.updated_by;
  -- L8: drafts follow a changed reporting window (submitted activities keep the deadline they were judged against)
  if p_values ? 'reporting_deadline_days' then
    update realisasi.activities set reporting_deadline = end_date + (p_values ->> 'reporting_deadline_days')::int
     where status = 'draft' and reporting_deadline is distinct from end_date + (p_values ->> 'reporting_deadline_days')::int;
  end if;
  return (select jsonb_object_agg(key, value order by key) from realisasi.settings);
end $$;

-- re-derive academic year / semester of every activity after calendar changes
create function realisasi._rederive_periods() returns int
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
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
language sql security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select realisasi._raise('CAL_INVALID_RANGE', 'Rentang tanggal kalender tidak valid atau tumpang tindih.')
$$;

create function realisasi.upsert_academic_year(p_id int, p_label text, p_start date, p_end date) returns int
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
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
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
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

-- Jenis Kegiatan rules (Revisi V.1): the agenda list itself belongs to SIM Kerjasama; Realisasi only decides whether
-- an agenda is a mobility kegiatan (and its International Awards category) and whether it counts for KPI 1.19.S1.
-- p_data: {mobility_category: 'jd_dd'|'student_exchange'|'short_summer'|'other_mobility'|null, counts_for_s1: bool}
create function realisasi.set_agenda_rule(p_agenda_id int, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_admin(); r realisasi.agenda_rules;
begin
  if p_data is null or jsonb_typeof(p_data) <> 'object' then perform realisasi._invalid('payload'); end if;
  if not exists (select 1 from kerjasama.agendas where id = p_agenda_id) then perform realisasi._not_found(); end if;
  select * into r from realisasi.agenda_rules where agenda_id = p_agenda_id;
  if not found then r.agenda_id := p_agenda_id; r.counts_for_s1 := true; end if;
  begin
    if p_data ? 'mobility_category' then
      r.mobility_category := realisasi._jtext(p_data, 'mobility_category')::realisasi.mobility_category;
    end if;
    if p_data ? 'counts_for_s1' then r.counts_for_s1 := (p_data ->> 'counts_for_s1')::boolean; end if;
  exception when others then
    perform realisasi._invalid('agenda_rule');
  end;
  if r.counts_for_s1 is null then perform realisasi._invalid('counts_for_s1'); end if;
  insert into realisasi.agenda_rules (agenda_id, mobility_category, counts_for_s1, updated_by, updated_at)
  values (p_agenda_id, r.mobility_category, r.counts_for_s1, v_uid, realisasi.now_ts())
  on conflict (agenda_id) do update set mobility_category = excluded.mobility_category,
     counts_for_s1 = excluded.counts_for_s1, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  return jsonb_build_object('agenda_id', p_agenda_id, 'mobility_category', r.mobility_category, 'counts_for_s1', r.counts_for_s1);
end $$;

create function realisasi.mark_notifications_read(p_ids bigint[] default null) returns int
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_uid(); n int;
begin
  update realisasi.notifications set read_at = realisasi.now_ts()
   where recipient_id = v_uid and read_at is null and (p_ids is null or id = any(p_ids));
  get diagnostics n = row_count;
  return n;
end $$;

create function realisasi.log_export(p_kind text, p_filters jsonb, p_row_count int, p_contains_personal boolean) returns bigint
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_uid(); v_id bigint;
begin
  if nullif(btrim(p_kind), '') is null then perform realisasi._invalid('kind'); end if;
  insert into realisasi.export_log (actor_id, export_kind, filters, row_count, contains_personal_data, created_at)
  values (v_uid, p_kind, p_filters, p_row_count, coalesce(p_contains_personal, false), realisasi.now_ts())
  returning id into v_id;
  return v_id;
end $$;

commit;
select 'part 3 of 5 OK - now run part 4' as status;
