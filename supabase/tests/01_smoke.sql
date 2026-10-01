-- 01_smoke: catalogue, grants, RLS switches, seed shape.
\ir _helpers.inc

-- every CONTRACTS §3 function exists with its exact signature and is executable by authenticated
select pg_temp.ok(to_regprocedure(f) is not null and has_function_privilege('authenticated', f, 'EXECUTE'), 'rpc ' || f)
  from unnest(array[
    'realisasi.lookup_students(text[])', 'realisasi.lookup_employees(text[])', 'realisasi.documents_valid_between(date,date,integer)',
    'realisasi.save_activity_draft(uuid,jsonb)', 'realisasi.delete_draft(uuid)', 'realisasi.ensure_participant_draft(uuid)',
    'realisasi.save_participants(uuid,jsonb,jsonb)', 'realisasi.submission_checklist(uuid)', 'realisasi.submit_activity(uuid)',
    'realisasi.can_read_file(text)', 'realisasi.storage_put(text,text,bytea)', 'realisasi.storage_get(text)',
    'realisasi.register_activity_file(uuid,realisasi.file_kind,text,text,integer,text)',
    'realisasi.add_evidence_link(uuid,text,text)', 'realisasi.remove_activity_file(bigint)',
    'realisasi.partnership_approve(uuid,text)', 'realisasi.partnership_request_revision(uuid,text)',
    'realisasi.partnership_reject(uuid,text,text)', 'realisasi.mobility_approve(uuid,text)',
    'realisasi.mobility_request_revision(uuid,text,jsonb)', 'realisasi.edit_verified_activity(uuid,jsonb,text)',
    'realisasi.commit_participant_edit(uuid,text)', 'realisasi.link_duplicates(bigint,text)',
    'realisasi.link_activities(uuid,uuid,text)', 'realisasi.dismiss_duplicate(bigint,text)', 'realisasi.unlink_activity(uuid,text)',
    'realisasi.create_known_activity(jsonb)', 'realisasi.update_known_activity(bigint,jsonb)',
    'realisasi.known_match_suggestions(bigint)', 'realisasi.match_known_activity(bigint,uuid)',
    'realisasi.unmatch_known_activity(bigint)', 'realisasi.dismiss_known_activity(bigint,text)',
    'realisasi.nudge_known_activity(bigint)', 'realisasi.update_settings(jsonb)',
    'realisasi.upsert_academic_year(integer,text,date,date)',
    'realisasi.upsert_semester(integer,integer,realisasi.semester_term,date,date,date)',
    'realisasi.upsert_activity_type(integer,jsonb)', 'realisasi.upsert_holiday(date,text)', 'realisasi.delete_holiday(date)',
    'realisasi.freeze_snapshot(integer,realisasi.snapshot_kind,timestamp with time zone,uuid)',
    'realisasi.refreeze_snapshot(uuid,text)', 'realisasi.run_daily_jobs()',
    'realisasi.mark_notifications_read(bigint[])', 'realisasi.log_export(text,jsonb,integer,boolean)',
    'realisasi.period_info(integer,text)', 'realisasi.dashboard(integer,text,integer)',
    'realisasi.kpi_drilldown(integer,text,text,text,integer,uuid)', 'realisasi.kpi_participant_rows(integer,text,integer,uuid)',
    'realisasi.activity_detail(uuid)', 'realisasi.participant_version(uuid,integer)', 'realisasi.participant_counts(uuid)',
    'realisasi.nav_counts()', 'realisasi.agreement_realization(integer)', 'realisasi.agreement_flags(integer)',
    'realisasi.snapshot_list(integer)', 'realisasi.snapshot_detail(uuid)', 'realisasi.snapshot_late_additions(uuid)',
    'realisasi.snapshot_post_freeze_changes(uuid)']) f;

-- core helpers with exact signatures (§2.5)
select pg_temp.ok(to_regprocedure(f) is not null, 'helper ' || f)
  from unnest(array['realisasi.today()', 'realisasi.now_ts()', 'realisasi.setting_int(text)', 'realisasi.setting_num(text)',
    'realisasi.settings_json()', 'realisasi._raise(text,text,jsonb)', 'realisasi.business_days_between(date,date)',
    'realisasi.sla_days(timestamp with time zone)', 'realisasi.sla_level(integer)', 'realisasi.chain_root(integer)',
    'realisasi.chain_current(integer)', 'realisasi.semester_label(integer)', 'realisasi.my_role()', 'realisasi.my_unit()',
    'realisasi.in_team(realisasi.team)', 'realisasi.is_io()', 'realisasi.can_view_activity(uuid)',
    'realisasi.can_view_participants(uuid)', 'realisasi._is_unit_editor(uuid)', 'realisasi.in_frozen_period(uuid)',
    'realisasi.is_late_addition(uuid)', 'realisasi._log(uuid,realisasi.log_kind,realisasi.team,text,text,jsonb)',
    'realisasi._notify(uuid,text,text,text,text)', 'realisasi._scan_duplicates(uuid)', 'realisasi._rederive_periods()',
    'realisasi.kpi_items(date,date,date,integer,timestamp with time zone,integer)',
    'realisasi.compute_kpis(date,date,date,integer,timestamp with time zone,integer)',
    'realisasi.kpi_1_1(date,date)', 'realisasi.kpi_1_19_s1(date,date)', 'realisasi.kpi_1_19_24(date,date,integer)',
    'realisasi.kpi_1_19_s8(date,date)']) f;

-- internal functions are not callable by authenticated
select pg_temp.ok(not has_function_privilege('authenticated', p.oid, 'EXECUTE'), 'internal not granted: ' || p.oid::regprocedure)
  from pg_proc p where p.pronamespace = 'realisasi'::regnamespace
   and (p.proname like '\_%' or p.proname in ('compute_kpis','kpi_items','kpi_1_1','kpi_1_19_s1','kpi_1_19_24','kpi_1_19_s8'));

-- every function is security definer with a pinned search_path (trigger fns and pure helpers excepted); extensions before public (review L6)
select pg_temp.ok(p.prosecdef and array_to_string(p.proconfig, ',') like 'search_path=realisasi, extensions, public, pg_temp%',
                  'definer + search_path: ' || p.oid::regprocedure)
  from pg_proc p where p.pronamespace = 'realisasi'::regnamespace
   and has_function_privilege('authenticated', p.oid, 'EXECUTE');

-- RLS on every realisasi table; no write grants for authenticated anywhere
select pg_temp.ok(c.relrowsecurity, 'RLS enabled on realisasi.' || c.relname)
  from pg_class c where c.relnamespace = 'realisasi'::regnamespace and c.relkind = 'r';
select pg_temp.ok(not has_table_privilege('authenticated', c.oid, 'INSERT') and not has_table_privilege('authenticated', c.oid, 'UPDATE')
                  and not has_table_privilege('authenticated', c.oid, 'DELETE'), 'no write grant on ' || c.oid::regclass)
  from pg_class c where c.relnamespace in ('realisasi'::regnamespace, 'mock_baak'::regnamespace, 'mock_hr'::regnamespace, 'public'::regnamespace)
   and c.relkind in ('r','v');
select pg_temp.ok(not has_table_privilege('authenticated', 'realisasi.activities', 'INSERT'), 'authenticated lacks INSERT on realisasi.activities');
select pg_temp.ok(not has_table_privilege('authenticated', t, 'SELECT'), 'no select on ' || t)
  from unnest(array['realisasi.file_blobs', 'realisasi.job_marks', 'mock_baak.students', 'mock_hr.employees']) t;
select pg_temp.ok(has_table_privilege('authenticated', t, 'SELECT'), 'select granted on ' || t)
  from unnest(array['realisasi.v_activity_list', 'realisasi.v_chains', 'realisasi.v_activity_documents', 'realisasi.v_known_activities',
                    'realisasi.v_duplicate_candidates', 'realisasi.activities', 'realisasi.kpi_snapshots', 'public.documents']) t;
select pg_temp.ok((select reloptions from pg_class where oid = v::regclass) @> array['security_invoker=true'], 'security_invoker ' || v)
  from unnest(array['realisasi.v_activity_documents','realisasi.v_activity_list','realisasi.v_known_activities','realisasi.v_duplicate_candidates']) v;

-- triggers present
select pg_temp.ok(exists (select 1 from pg_trigger where tgname = t and not tgisinternal), 'trigger ' || t)
  from unnest(array['trg_activities_derive_period','trg_activities_derive_deadline','trg_activities_status',
                    'trg_activity_documents_snapshot','trg_pset_supersede','trg_touch_updated_at']) t;

-- seed shape
select pg_temp.eq((select count(*) from mock_baak.students), 60::bigint, '60 BAAK students');
select pg_temp.eq((select count(*) from mock_baak.students where category = 'inbound_exchange'), 15::bigint, '15 inbound_exchange');
select pg_temp.eq((select count(*) from mock_baak.students where status = 'graduated'), 3::bigint, '3 graduated');
select pg_temp.eq((select count(*) from mock_baak.students where status = 'inactive'), 2::bigint, '2 inactive');
select pg_temp.ok((select bool_and(nrp ~ '^[A-H][0-9]{2}[0-9]{2}[0-9]{4}$') from mock_baak.students where category = 'regular'), 'regular NRP format');
select pg_temp.ok((select bool_and(nrp ~ '^X[0-9]{2}[0-9]{2}[0-9]{4}$') from mock_baak.students where category = 'inbound_exchange'), 'inbound NRP format');
select pg_temp.ok(exists (select 1 from mock_baak.students where nrp = 'D31240187' and category = 'regular' and status = 'active'), 'D31240187 regular active');
select pg_temp.ok(exists (select 1 from mock_baak.students where nrp = 'X01260012' and category = 'inbound_exchange'), 'X01260012 inbound');
select pg_temp.ok(exists (select 1 from mock_baak.students where nrp = 'B11200005' and status = 'graduated'), 'B11200005 graduated');
select pg_temp.ok(not exists (select 1 from mock_baak.students where nrp = 'Z99999999'), 'Z99999999 absent');
select pg_temp.eq((select count(*) from mock_hr.employees), 25::bigint, '25 employees');
select pg_temp.eq((select count(*) from mock_hr.employees where status = 'inactive'), 2::bigint, '2 inactive employees');
select pg_temp.ok((select bool_and(employee_id ~ '^PG[0-9]{6}$') from mock_hr.employees), 'employee id format');
select pg_temp.eq((select count(*) from public.profiles), 8::bigint, '8 demo accounts');
select pg_temp.eq((select count(*) from realisasi.activity_types), 9::bigint, '9 Jenis');
select pg_temp.eq((select count(*) from realisasi.sdgs), 17::bigint, '17 SDGs');
select pg_temp.eq((select count(*) from realisasi.activities), 32::bigint, '32 seeded activities (S-01…S-30 + S-15b + S-20b)');
select pg_temp.eq((select count(*) from realisasi.known_activities), 8::bigint, '8 known activities');
select pg_temp.eq((select count(*) from realisasi.kpi_snapshots where superseded_by is null), 2::bigint, '2 historical snapshots');
select pg_temp.eq((select count(*) from realisasi.settings), 13::bigint, '13 settings keys');
select pg_temp.ok((select bool_and(exists (select 1 from realisasi.file_blobs b where b.path = f.storage_path)) from realisasi.activity_files f
                    where f.storage_path is not null), 'every file row has a blob');
select pg_temp.ok((select bool_and(substring(data from 1 for 5) = '\x255044462d'::bytea) from realisasi.file_blobs), 'blobs are PDFs');
select pg_temp.ok((select count(*) = 31 from realisasi.activities a where exists (select 1 from realisasi.activity_files f where f.activity_id = a.id and f.kind = 'ir')),
                  'all but the draft S-23 have an IR');

-- auth.uid() follows the JWT claims (also with an empty claims GUC)
:as_fti
select pg_temp.eq(auth.uid(), :'FTI'::uuid, 'auth.uid() from request.jwt.claims');
select pg_temp.eq(realisasi.my_role(), 'submitter', 'my_role');
select pg_temp.eq(realisasi.my_unit(), 10, 'my_unit');
select pg_temp.eq((select count(*) from realisasi.lookup_students(array['D31240187','Z99999999'])), 1::bigint, 'lookup_students via RPC');
select pg_temp.eq((select count(*) from realisasi.lookup_employees(array['PG204517'])), 1::bigint, 'lookup_employees via RPC');
select pg_temp.ok(pg_temp.err('select count(*) from mock_baak.students') like '%permission denied%', 'mock_baak not directly readable');
:as_system
select pg_temp.ok(auth.uid() is null, 'auth.uid() null with empty claims');
select pg_temp.throws('select realisasi.nav_counts()', 'AUTH_REQUIRED', 'RPC without session');
rollback;
