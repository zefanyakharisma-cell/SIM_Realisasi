-- 0015_jobs: daily jobs (CONTRACTS §5.1). "Once" semantics via job_marks.

create function realisasi._mark_once(p_key text) returns boolean
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
begin
  insert into realisasi.job_marks (key, created_at) values (p_key, realisasi.now_ts()) on conflict (key) do nothing;
  return found;
end $$;

create function realisasi.run_daily_jobs() returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare
  v_today date := realisasi.today();
  v_rem int := 0; v_dl int := 0; v_frozen jsonb := '[]'::jsonb;
  r record; v_days int; v_since timestamptz; v_tag text; v_kind text;
  v_n int; v_id uuid; v_epoch bigint;
begin
  -- system caller (pg_cron/psql) or io_admin; an `authenticated` session with empty claims is refused (M4)
  if not realisasi._is_system_caller() then perform realisasi._require_admin(); end if;

  -- L8: SIM Kerjasama may re-parent documents; refresh the stored chain id of agreement links
  update realisasi.activity_documents ad set chain_id = m.root_id
    from realisasi._chain_map() m
   where m.doc_id = ad.original_document_id and ad.chain_id is distinct from m.root_id;

  -- Unit revision reminder (R-61). Revisi V.1: no SLA tracking and no escalation; just a reminder to the unit.
  for r in select a.* from realisasi.activities a where a.mobility_status = 'revision_requested' order by a.code loop
    v_since := r.mobility_since;
    v_days := v_today - (v_since at time zone 'Asia/Jakarta')::date;
    v_epoch := extract(epoch from v_since)::bigint;
    if v_days >= realisasi.setting_int('revision_reminder_days')
       and realisasi._mark_once(format('rev_remind:%s:mobility:%s', r.id, v_epoch)) then
      perform realisasi._notify_unit(r.submitter_unit_id, 'revision_reminder', 'Pengingat revisi: ' || r.code,
        format('Revisi kegiatan "%s" belum diajukan ulang (%s hari).', r.name, v_days), '/realisasi/kegiatan/' || r.id);
      v_rem := v_rem + 1;
    end if;
  end loop;

  -- Reporting-deadline reminders for drafts (R-62): one notification per run for the most advanced new tag
  for r in select * from realisasi.activities where status = 'draft' and reporting_deadline is not null order by code loop
    v_tag := null; v_kind := null;
    if v_today >= r.reporting_deadline - realisasi.setting_int('deadline_reminder_before_days')
       and realisasi._mark_once(format('deadline:%s:h7', r.id)) then v_tag := 'h7'; v_kind := 'deadline_h7'; end if;
    if v_today >= r.reporting_deadline and realisasi._mark_once(format('deadline:%s:h0', r.id)) then
      v_tag := 'h0'; v_kind := 'deadline_h0';
    end if;
    v_n := (v_today - r.reporting_deadline) / 7;
    if v_n >= 1 and realisasi._mark_once(format('deadline:%s:w%s', r.id, v_n)) then v_tag := 'w' || v_n; v_kind := 'deadline_weekly'; end if;
    if v_kind is not null then
      perform realisasi._notify_unit(r.submitter_unit_id, v_kind,
        format('Batas pelaporan %s: %s', realisasi._fmt_date(r.reporting_deadline), r.code),
        format('Draf kegiatan "%s" harus diajukan paling lambat %s.', r.name, realisasi._fmt_date(r.reporting_deadline)),
        '/realisasi/kegiatan/baru?draft=' || r.id);
      v_dl := v_dl + 1;
    end if;
  end loop;

  -- Semester freezes (R-55)
  for r in select s.*, ay.label as ay_label,
                  case when s.term = 'ganjil' then 'ganjil_ytd' else 'genap_full_year' end::realisasi.snapshot_kind as kind
             from realisasi.semesters s join realisasi.academic_years ay on ay.id = s.academic_year_id
            where s.cutoff_date <= v_today
              and not exists (select 1 from realisasi.kpi_snapshots k where k.academic_year_id = s.academic_year_id
                                and k.superseded_by is null
                                and k.kind = case when s.term = 'ganjil' then 'ganjil_ytd' else 'genap_full_year' end::realisasi.snapshot_kind)
            order by s.cutoff_date loop
    v_id := realisasi._freeze(r.academic_year_id, r.kind,
              least(realisasi.now_ts(), (r.cutoff_date + time '01:00') at time zone 'Asia/Jakarta'), null, null, null);
    v_frozen := v_frozen || jsonb_build_object('snapshot_id', v_id, 'ay_label', r.ay_label, 'kind', r.kind);
  end loop;

  return jsonb_build_object('today', v_today, 'revision_reminders', v_rem,
                            'deadline_reminders', v_dl, 'frozen', v_frozen);
end $$;
