-- SIM Realisasi Supabase install, PART 3 OF 5 (commit 56e49d9).
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
    return realisasi.can_view_participants(v_act);
  end if;
  return false;
end $$;

create function realisasi.storage_put(p_path text, p_mime text, p_data bytea) returns void
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_uid(); v_bucket text := split_part(p_path, '/', 1);
        v_act uuid := realisasi._path_activity(p_path); v_seg3 text := split_part(p_path, '/', 3);
        v_draft uuid; v_ver int; v_ok boolean := false;
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
      v_draft := realisasi._draft_pset(v_act);
      select version into v_ver from realisasi.participant_set_versions where id = v_draft;
      v_ok := realisasi._can_edit_participants(v_act) and v_ver is not null and v_seg3 = 'v' || v_ver;
    end if;
  end if;
  if not v_ok then perform realisasi._raise('FILE_FORBIDDEN', 'Anda tidak memiliki akses ke berkas ini.'); end if;

  -- Blobs are immutable once referenced (H5; R-30/R-31/R-64). An unreferenced upload may be retried by its uploader.
  if exists (select 1 from realisasi.file_blobs b where b.path = p_path) then
    if (exists (select 1 from realisasi.activity_files f where f.storage_path = p_path)
        or exists (select 1 from realisasi.participant_students ps where ps.transcript_path = p_path)) or (select b.created_by from realisasi.file_blobs b where b.path = p_path) is distinct from v_uid then
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
    perform realisasi._log(p_activity, 'update', 'partnership', p_action, null, p_detail);
  elsif a.partnership_status = 'revision_requested' and a.status <> 'draft' then
    perform realisasi._log(p_activity, 'revision', 'partnership', p_action, null, p_detail);
  end if;
end $$;

create function realisasi._check_file_write(p_activity uuid) returns realisasi.activities
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare a realisasi.activities;
begin
  a := realisasi._get_activity(p_activity);
  if not realisasi._can_write_files(p_activity) then
    if a.status = 'verified' and realisasi._is_unit_editor(p_activity) then
      perform realisasi._raise('R29_EDIT_FORBIDDEN', 'Hanya tim IO terkait yang dapat mengubah kegiatan terverifikasi.');
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
  if p_storage_path is null or p_storage_path not like 'realisasi-files/' || p_activity::text || '/' || p_kind::text || '/%' then
    perform realisasi._invalid('storage_path');
  end if;
  select * into b from realisasi.file_blobs where path = p_storage_path;
  if not found then perform realisasi._raise('FILE_NOT_FOUND', 'Berkas tidak ditemukan.'); end if;
  -- type and size always come from the stored blob; the caller's p_mime/p_size_bytes are ignored (M8, R-13)
  if p_kind in ('ia','ir') and (b.mime <> 'application/pdf' or substring(b.data from 1 for 5) <> '\x255044462d'::bytea) then
    perform realisasi._raise('R13_FILE_TYPE', 'Format berkas tidak diizinkan (PDF).');
  end if;
  if p_kind = 'evidence' and b.mime not in ('application/pdf','image/jpeg','image/png') then
    perform realisasi._raise('R13_FILE_TYPE', 'Format berkas tidak diizinkan (PDF, JPG, PNG).');
  end if;
  if p_kind in ('ia','ir') then
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

-- >>> supabase/migrations/0010_rpc_duplicates_known.sql
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

-- >>> supabase/migrations/0011_rpc_admin.sql
-- 0011_rpc_admin: settings, calendar, Jenis, holidays (io_admin) + notifications / export log.

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
        -- M9: time travel only where the deployment enables it (demo); clearing it is always allowed
        if not realisasi.demo_time_travel_enabled() then perform realisasi._settings_invalid(k); end if;
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

create function realisasi.upsert_activity_type(p_id int, p_data jsonb) returns int
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
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
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_admin();
begin
  if p_day is null or nullif(btrim(p_name), '') is null then
    perform realisasi._raise('VALIDATION_REQUIRED', 'Kolom wajib belum diisi: day, name.', '{"fields":["day","name"]}');
  end if;
  insert into realisasi.holidays (day, name) values (p_day, btrim(p_name)) on conflict (day) do update set name = excluded.name;
end $$;

create function realisasi.delete_holiday(p_day date) returns void
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_admin();
begin
  delete from realisasi.holidays where day = p_day;
  if not found then perform realisasi._not_found(); end if;
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
