-- LIVE PATCH for simks-partnership (2026-10-27), same text as the migrations of this commit:
--   0003_core.sql      _mask_log_diff also masks the NRP of resolve_conflict log diffs
--   0006_rls.sql       activity_log_select hides those rows from viewers outside sees_participant_identifiers()
--   0007_rpc_submission.sql  LATE_NOTICE follows the first submission (a resubmitted revision is not newly late)
--   0011_rpc_admin.sql update_settings caps the integer settings (120 months / 3650 days)
--   0014_reads.sql     dashboard: drafts near deadline for submitters only
-- Only for an install made before this commit; a fresh install/reset already has it. One transaction.
begin;

create or replace function realisasi._mask_log_diff(p jsonb) returns jsonb
language sql immutable set search_path = realisasi, extensions, public, pg_temp as $$
  select case when p is null or jsonb_typeof(p) <> 'object' then p else
    (p - 'students' - 'staff' - 'row_notes' - 'nrp')
    || case when jsonb_typeof(p -> 'students') = 'object' then jsonb_build_object('students', jsonb_build_object(
           'added', coalesce(jsonb_array_length(nullif(p -> 'students' -> 'added', 'null')), 0),
           'removed', coalesce(jsonb_array_length(nullif(p -> 'students' -> 'removed', 'null')), 0))) else '{}'::jsonb end
    || case when jsonb_typeof(p -> 'staff') = 'object' then jsonb_build_object('staff', jsonb_build_object(
           'added', coalesce(jsonb_array_length(nullif(p -> 'staff' -> 'added', 'null')), 0),
           'removed', coalesce(jsonb_array_length(nullif(p -> 'staff' -> 'removed', 'null')), 0))) else '{}'::jsonb end
    || case when jsonb_typeof(p -> 'row_notes') = 'array' then jsonb_build_object('row_notes', jsonb_array_length(p -> 'row_notes')) else '{}'::jsonb end
  end
$$;

create or replace function realisasi._checklist(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare
  a realisasi.activities;
  v_out jsonb := '[]'::jsonb; v_missing text[] := '{}'; v_bad text; v_list text;
  v_pset uuid; v_rows int; v_mob boolean; v_stu boolean; v_fac boolean; v_ext int; v_draft uuid; v_has boolean;
begin
  select * into a from realisasi.activities where id = p_id;
  if not found then return '[]'::jsonb; end if;
  v_mob := realisasi.agenda_is_mobility(a.agenda_id);
  v_stu := realisasi.agenda_program(a.agenda_id) = 'student_mobility';
  v_fac := realisasi.agenda_program(a.agenda_id) = 'faculty_mobility';
  v_ext := (select count(*) from realisasi.activity_external_persons where activity_id = p_id)::int;
  v_pset := realisasi._relevant_pset(p_id);
  v_draft := realisasi._draft_pset(p_id);
  v_rows := coalesce(realisasi._pset_rows(v_pset), 0);

  -- R07_REQUIRED_FIELD
  if nullif(btrim(a.name), '') is null then v_missing := v_missing || 'name'::text; end if;
  if nullif(btrim(a.description), '') is null then v_missing := v_missing || 'description'::text; end if;
  if nullif(btrim(a.venue), '') is null then v_missing := v_missing || 'venue'::text; end if;
  if a.mode <> 'online' and a.country_code is null then v_missing := v_missing || 'country_code'::text; end if;
  v_out := v_out || jsonb_build_object('code', 'R07_REQUIRED_FIELD', 'ok', cardinality(v_missing) = 0,
    'message', case when cardinality(v_missing) = 0 then 'Data wajib sudah lengkap.'
                    else 'Data wajib belum lengkap: ' || array_to_string(v_missing, ', ') || '.' end,
    'fields', to_jsonb(v_missing));

  -- R07_AGREEMENT_REQUIRED (Revisi V.1: exactly one kerja sama)
  v_has := exists (select 1 from realisasi.activity_documents where activity_id = p_id);
  v_out := v_out || jsonb_build_object('code', 'R07_AGREEMENT_REQUIRED', 'ok', v_has,
    'message', case when v_has then 'Kerja sama sudah dipilih.' else 'Pilih kerja sama yang direalisasikan.' end);

  -- R04_AGREEMENT_NOT_VALID
  select string_agg(d.doc_number, ', ' order by d.doc_number) into v_bad
    from realisasi.activity_documents ad join kerjasama.documents d on d.id = ad.original_document_id
   where ad.activity_id = p_id
     and not exists (select 1 from realisasi.documents_valid_between(a.start_date, a.end_date) v where v.document_id = d.id);
  v_out := v_out || jsonb_build_object('code', 'R04_AGREEMENT_NOT_VALID', 'ok', v_bad is null,
    'message', case when v_bad is null then 'Kerja sama berlaku pada tanggal kegiatan.'
                    else format('Kerja sama %s tidak berlaku pada tanggal kegiatan.', v_bad) end);

  -- R08
  v_out := v_out || jsonb_build_object('code', 'R08_END_AFTER_TODAY', 'ok', a.end_date <= realisasi.today(),
    'message', case when a.end_date <= realisasi.today() then 'Kegiatan sudah selesai.'
                    else 'Kegiatan belum selesai. Tanggal selesai harus hari ini atau sebelumnya.' end);
  -- R09
  v_out := v_out || jsonb_build_object('code', 'R09_NO_ACADEMIC_YEAR', 'ok', a.academic_year_id is not null,
    'message', case when a.academic_year_id is not null then 'Tahun akademik terdaftar.'
                    else 'Tanggal mulai berada di luar tahun akademik yang terdaftar. Hubungi Admin IO.' end);
  -- R07 IA / IR
  v_has := exists (select 1 from realisasi.activity_files where activity_id = p_id and kind = 'ia' and is_current);
  v_out := v_out || jsonb_build_object('code', 'R07_IA_REQUIRED', 'ok', v_has,
    'message', case when v_has then 'Implementation Arrangement (PDF) sudah diunggah.' else 'Implementation Arrangement (PDF) wajib diunggah.' end);
  v_has := exists (select 1 from realisasi.activity_files where activity_id = p_id and kind = 'ir' and is_current);
  v_out := v_out || jsonb_build_object('code', 'R07_IR_REQUIRED', 'ok', v_has,
    'message', case when v_has then 'Implementation Report (PDF) sudah diunggah.' else 'Implementation Report (PDF) wajib diunggah.' end);
  -- R13 mobility bundle (Revisi V.1 item 8): transkrip + poster + dokumentasi in one PDF
  v_has := exists (select 1 from realisasi.activity_files where activity_id = p_id and kind = 'mobility_bundle' and is_current);
  v_out := v_out || jsonb_build_object('code', 'R13_MOBILITY_BUNDLE_REQUIRED', 'ok', not v_stu or v_has,
    'message', case when not v_stu then 'Tidak diperlukan untuk jenis kegiatan ini.'
                    when v_has then 'Berkas mobilitas (transkrip, poster, dokumentasi) sudah diunggah.'
                    else 'Kegiatan mobilitas wajib mengunggah Transkrip Mahasiswa, Poster Kegiatan, dan Dokumentasi Kegiatan dalam satu file PDF.' end);

  -- R11 (Faculty Mobility inbound: the external persons are the participants)
  v_out := v_out || jsonb_build_object('code', 'R11_PARTICIPANTS_REQUIRED',
    'ok', not (v_mob and v_rows = 0) or (v_fac and a.direction = 'inbound' and v_ext > 0),
    'message', case when not v_mob then 'Tidak diperlukan untuk jenis kegiatan ini.'
                    when v_rows > 0 or (v_fac and a.direction = 'inbound' and v_ext > 0) then 'Data peserta sesuai ketentuan jenis kegiatan.'
                    else 'Kegiatan mobilitas wajib memiliki data peserta.' end);
  -- R12 (by the kegiatan's Inbound/Outbound choice)
  v_has := exists (select 1 from realisasi.participant_students where set_version_id = v_pset and section = 'internal');
  v_out := v_out || jsonb_build_object('code', 'R12_OUTBOUND_STUDENT_REQUIRED',
    'ok', not v_stu or a.direction <> 'outbound' or v_has,
    'message', case when not v_stu or a.direction <> 'outbound' then 'Tidak diperlukan untuk kegiatan ini.'
                    when v_has then 'Mahasiswa PETRA sudah tercantum.'
                    else 'Kegiatan outbound wajib memiliki minimal satu mahasiswa PETRA.' end);
  v_has := exists (select 1 from realisasi.participant_students where set_version_id = v_pset and section = 'inbound');
  v_out := v_out || jsonb_build_object('code', 'R12_INBOUND_STUDENT_REQUIRED',
    'ok', not v_stu or a.direction <> 'inbound' or v_has,
    'message', case when not v_stu or a.direction <> 'inbound' then 'Tidak diperlukan untuk kegiatan ini.'
                    when v_has then 'Mahasiswa inbound sudah tercantum.'
                    else 'Kegiatan inbound wajib memiliki minimal satu mahasiswa inbound.' end);
  -- R12 Faculty Mobility: outbound -> PETRA staff, inbound -> external person (tamu luar negeri)
  v_has := exists (select 1 from realisasi.participant_staff where set_version_id = v_pset);
  v_out := v_out || jsonb_build_object('code', 'R12_OUTBOUND_STAFF_REQUIRED',
    'ok', not v_fac or a.direction <> 'outbound' or v_has,
    'message', case when not v_fac or a.direction <> 'outbound' then 'Tidak diperlukan untuk kegiatan ini.'
                    when v_has then 'Staf PETRA sudah tercantum.'
                    else 'Kegiatan Faculty Mobility outbound wajib memiliki minimal satu dosen/staf PETRA.' end);
  v_out := v_out || jsonb_build_object('code', 'R12_INBOUND_GUEST_REQUIRED',
    'ok', not v_fac or a.direction <> 'inbound' or v_ext > 0,
    'message', case when not v_fac or a.direction <> 'inbound' then 'Tidak diperlukan untuk kegiatan ini.'
                    when v_ext > 0 then 'Tamu eksternal sudah tercantum.'
                    else 'Kegiatan Faculty Mobility inbound wajib memiliki minimal satu tamu eksternal.' end);
  -- R16
  select string_agg(ps.nrp, ', ' order by ps.id) into v_list from realisasi.participant_students ps
   where ps.set_version_id = v_pset and not exists (select 1 from mock_baak.students s where s.nrp = ps.nrp);
  v_out := v_out || jsonb_build_object('code', 'R16_NRP_NOT_FOUND', 'ok', v_list is null,
    'message', case when v_list is null then 'Semua NRP ditemukan di data BAAK.' else format('NRP tidak ditemukan di data BAAK: %s.', v_list) end);
  -- R17
  select string_agg(ps.nrp, ', ' order by ps.id) into v_list from realisasi.participant_students ps
   where ps.set_version_id = v_pset and ps.section = 'inbound' and ps.home_institution is null;
  v_out := v_out || jsonb_build_object('code', 'R17_INBOUND_DATA_REQUIRED', 'ok', v_list is null,
    'message', case when v_list is null then 'Data mahasiswa inbound lengkap.'
                    else format('Mahasiswa inbound %s wajib memiliki institusi asal.', v_list) end);
  -- R19
  select string_agg(st.employee_id, ', ' order by st.id) into v_list from realisasi.participant_staff st
   where st.set_version_id = v_pset and not exists (select 1 from mock_hr.employees e where e.employee_id = st.employee_id);
  v_out := v_out || jsonb_build_object('code', 'R19_EMPLOYEE_NOT_FOUND', 'ok', v_list is null,
    'message', case when v_list is null then 'Semua ID pegawai ditemukan di data SDM.' else format('ID pegawai tidak ditemukan di data SDM: %s.', v_list) end);
  -- R21
  v_out := v_out || jsonb_build_object('code', 'R21_NEW_VERSION_REQUIRED',
    'ok', not (v_mob and a.mobility_status = 'revision_requested' and v_draft is null
               and exists (select 1 from realisasi.participant_set_versions where activity_id = p_id and status = 'revision_requested')),
    'message', case when not v_mob or a.mobility_status <> 'revision_requested'
                         or not exists (select 1 from realisasi.participant_set_versions
                                         where activity_id = p_id and status = 'revision_requested') then 'Tidak diperlukan.'
                    when v_draft is not null then 'Versi peserta baru sudah dibuat.'
                    else 'Perbarui data peserta (versi baru) sebelum mengajukan ulang.' end);

  -- is_late is derived from the FIRST submitted_at (submit_activity keeps it on resubmission): a revision sent back
  -- after the deadline is not late when the first submission was on time
  if a.submitted_at is null and realisasi.today() > a.reporting_deadline then
    v_out := v_out || jsonb_build_object('code', 'LATE_NOTICE', 'ok', true, 'late', true,
      'message', format('Batas pelaporan %s telah lewat — kegiatan akan ditandai Terlambat.', realisasi._fmt_date(a.reporting_deadline)));
  elsif a.submitted_at is not null and a.is_late then
    v_out := v_out || jsonb_build_object('code', 'LATE_NOTICE', 'ok', true, 'late', true,
      'message', format('Kegiatan sudah ditandai Terlambat (batas pelaporan %s).', realisasi._fmt_date(a.reporting_deadline)));
  end if;
  return v_out;
end $$;

create or replace function realisasi.update_settings(p_values jsonb) returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_admin(); k text; v jsonb;
  c_int text[] := array['grace_period_months','reporting_deadline_days','revision_reminder_days',
                        'deadline_reminder_before_days'];
begin
  if p_values is null or jsonb_typeof(p_values) <> 'object' then perform realisasi._settings_invalid('payload'); end if;
  for k, v in select * from jsonb_each(p_values) loop
    if k = any(c_int) then
      -- capped so setting_int() and the date arithmetic in the KPI reads / nightly jobs stay in range
      if jsonb_typeof(v) <> 'number' or (v #>> '{}')::numeric < 0 or (v #>> '{}')::numeric <> trunc((v #>> '{}')::numeric)
         or (v #>> '{}')::numeric > (case k when 'grace_period_months' then 120 else 3650 end) then
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

create or replace function realisasi.dashboard(p_ay_id int default null, p_period text default 'ytd', p_unit_id int default null) returns jsonb
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

  -- drafts are the submitter's own work (RLS hides them from IO / viewers): only a submitter sees this list
  if v_unit is not null and realisasi.my_role() = 'submitter' then
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

alter policy activity_log_select on realisasi.activity_log
  using (((select realisasi.is_io()) or activity_id in (select realisasi.my_activity_ids()))
         and (not (coalesce(diff ? 'students', false) or coalesce(diff ? 'staff', false) or coalesce(diff ? 'row_notes', false)
                   or coalesce(diff ? 'nrp', false))
              or (select realisasi.sees_participant_identifiers())));

commit;
