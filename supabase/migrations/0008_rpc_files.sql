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
