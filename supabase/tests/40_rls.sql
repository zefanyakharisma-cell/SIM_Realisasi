-- 40_rls: Rules §10 access matrix per role, AT-11 (DB side), file access.
\ir _helpers.inc

create temp table _f as
select (select storage_path from realisasi.activity_files where activity_id = pg_temp.aid(13) and kind = 'ia') as fti_verified,
       (select storage_path from realisasi.activity_files where activity_id = pg_temp.aid(17) and kind = 'ia') as fbe_verified,
       (select storage_path from realisasi.activity_files where activity_id = pg_temp.aid(23) and kind = 'ia') as fsd_draft,
       (select storage_path from realisasi.activity_files where activity_id = pg_temp.aid(11) and kind = 'mobility_bundle') as fsd_transcript,
       (select count(*) from realisasi.activities where status = 'verified') as n_verified,
       (select count(*) from realisasi.activities) as n_all;
grant select on _f to authenticated;

-- ---- viewer (Rektorat): verified only, no participants, no logs, no register ----------------------------------
:as_view
select pg_temp.eq((select count(*) from realisasi.activities), (select n_verified from _f), 'viewer sees verified activities only');
select pg_temp.eq((select count(*) from realisasi.v_activity_list where status <> 'verified'), 0::bigint, 'viewer list verified only');
select pg_temp.eq((select count(*) from realisasi.participant_students), 0::bigint, 'AT-11 viewer cannot read participant_students');
select pg_temp.eq((select count(*) from realisasi.participant_staff), 0::bigint, 'viewer cannot read participant_staff');
select pg_temp.ok((select count(*) > 0 from realisasi.participant_set_versions), 'viewer sees version metadata of verified activities');
select pg_temp.eq((select count(*) from realisasi.activity_log), 0::bigint, 'viewer cannot read activity_log');
select pg_temp.eq((select count(*) from realisasi.participant_conflicts), 0::bigint, 'viewer: no student conflicts');
select pg_temp.eq((select count(*) from realisasi.activity_files where kind = 'mobility_bundle'), 0::bigint, 'viewer: mobility bundles hidden');
select pg_temp.ok(not (realisasi.activity_detail(pg_temp.aid(11))::text like '%mobility_bundle%'), 'viewer: activity_detail omits the bundle');
select pg_temp.eq((select count(*) from realisasi.email_outbox), 0::bigint, 'viewer: no outbox');
select pg_temp.eq((select count(*) from realisasi.kpi_snapshots), 2::bigint, 'viewer reads snapshots');
select pg_temp.throws($$select realisasi.kpi_participant_rows(1, 'full')$$, 'AUTH_FORBIDDEN', 'AT-11 viewer participant rows forbidden');
select pg_temp.throws($$select realisasi.participant_version(pg_temp.aid(13))$$, 'AUTH_FORBIDDEN', 'viewer participant_version forbidden');
select pg_temp.ok(realisasi.participant_counts(pg_temp.aid(13)) ->> 'internal_students' = '12', 'viewer gets counts only');
select pg_temp.throws($$select realisasi.activity_detail(pg_temp.aid(23))$$, 'NOT_FOUND', 'viewer cannot open a draft');
select pg_temp.eq(realisasi.activity_detail(pg_temp.aid(13)) -> 'log', '[]'::jsonb, 'viewer: activity_detail.log empty');
select pg_temp.eq((realisasi.activity_detail(pg_temp.aid(13)) #>> '{participants,can_view_rows}')::boolean, false, 'viewer: can_view_rows false');
select pg_temp.eq((realisasi.activity_detail(pg_temp.aid(13)) #>> '{permissions,can_view_log}')::boolean, false, 'viewer: can_view_log false');
select pg_temp.ok(realisasi.can_read_file((select fti_verified from _f)), 'viewer reads files of verified activity');
select pg_temp.ok(not realisasi.can_read_file((select fsd_draft from _f)), 'viewer cannot read draft files');
select pg_temp.ok(not realisasi.can_read_file((select fsd_transcript from _f)), 'viewer cannot read the mobility bundle (transcripts)');
select pg_temp.throws(format('select * from realisasi.storage_get(%L)', (select fsd_transcript from _f)), 'FILE_FORBIDDEN', 'storage_get bundle forbidden');
select pg_temp.eq((select count(*) from realisasi.notifications where recipient_id <> auth.uid()), 0::bigint, 'notifications: own only');
select pg_temp.eq(realisasi.nav_counts() - 'unread_notifications', '{"mobility_queue":0,"conflicts_open":0,"revision_inbox":0}'::jsonb, 'viewer nav counts');
select pg_temp.throws($$select realisasi.conflict_list()$$, 'AUTH_FORBIDDEN', 'viewer cannot list conflicts');
select pg_temp.ok(jsonb_array_length(realisasi.international_awards(2, 'ytd') -> 'outbound_international') > 0, 'viewer reads International Awards');
select pg_temp.ok(pg_temp.err('insert into realisasi.activities (name) values (''x'')') like '%permission denied%', 'no direct INSERT');
select pg_temp.ok(pg_temp.err('update realisasi.activities set name = ''x''') like '%permission denied%', 'no direct UPDATE');
select pg_temp.ok(pg_temp.err('delete from realisasi.activity_log') like '%permission denied%', 'no direct DELETE (R-64)');
select pg_temp.ok(pg_temp.err('select count(*) from realisasi.file_blobs') like '%permission denied%', 'file_blobs not selectable');
select pg_temp.ok(pg_temp.err('select count(*) from realisasi.job_marks') like '%permission denied%', 'job_marks not selectable');

-- ---- submitter FTI (unit 10): own + co-unit activities; own participants ------------------------------------------
:as_fti
select pg_temp.eq((select count(*) from realisasi.activities),
                  (select count(*) from realisasi.activity_units where unit_id = 10)::bigint, 'FTI sees own-unit activities only');
select pg_temp.ok(not exists (select 1 from realisasi.activities where id in (pg_temp.aid(14), pg_temp.aid(17))), 'FTI cannot see S-14 / S-17');
select pg_temp.ok((select count(*) = 12 from realisasi.participant_students s join realisasi.participant_set_versions v on v.id = s.set_version_id
                    where v.activity_id = pg_temp.aid(13)), 'FTI reads own participants');
select pg_temp.ok(not exists (select 1 from realisasi.participant_students s join realisasi.participant_set_versions v on v.id = s.set_version_id
                    where v.activity_id = pg_temp.aid(10)), 'FTI cannot read FBE participants');
select pg_temp.eq((select count(*) from realisasi.participant_conflicts), 0::bigint, 'submitter: no conflict rows');
select pg_temp.eq((select open_conflicts from realisasi.v_activity_list where id = pg_temp.aid(13)), 2, 'unit sees how many students wait for a decision (count only)');
select pg_temp.throws($$select realisasi.resolve_conflict(1, pg_temp.aid(13))$$, 'AUTH_FORBIDDEN', 'submitter cannot resolve conflicts');
select pg_temp.ok((select count(*) > 0 from realisasi.activity_log where activity_id = pg_temp.aid(13)), 'submitter reads own activity log');
select pg_temp.ok(realisasi.can_read_file((select fti_verified from _f)), 'FTI reads own file');
select pg_temp.ok(not realisasi.can_read_file((select fbe_verified from _f)), 'FTI cannot read FBE file');
select pg_temp.throws($$select realisasi.activity_detail(pg_temp.aid(17))$$, 'NOT_FOUND', 'other unit activity_detail NOT_FOUND');
select pg_temp.eq((realisasi.activity_detail(pg_temp.aid(16)) -> 'permissions') - 'can_view_participants' - 'can_view_log',
  '{"can_edit_draft":false,"can_delete_draft":false,"can_edit_detail":true,"can_edit_files":true,"can_edit_participants":true,"can_submit":true,
    "can_mobility_verify":false,"can_edit_verified_detail":false,"can_edit_verified_participants":false}'::jsonb, 'S-16 permissions for FTI');
select pg_temp.ok(realisasi.activity_detail(pg_temp.aid(16)) -> 'checklist' is not null, 'checklist present when can_submit');
select pg_temp.eq(realisasi.activity_detail(pg_temp.aid(13)) -> 'conflicts', '[]'::jsonb, 'conflicts hidden for units');
select pg_temp.ok(realisasi.can_read_file((select storage_path from realisasi.activity_files where activity_id = pg_temp.aid(13) and kind = 'mobility_bundle')),
                  'FTI reads its own mobility bundle');
select pg_temp.eq((realisasi.nav_counts() ->> 'revision_inbox')::int, 1, 'FTI revision inbox (S-16)');

-- co-unit read-only visibility: kaprodi Informatika sees S-14 but not S-13 (exact unit match, no roll-up)
:as_inf
select pg_temp.ok(exists (select 1 from realisasi.activities where id = pg_temp.aid(14)) and not exists (select 1 from realisasi.activities where id = pg_temp.aid(13)),
                  'unit scope is exact-match');
select pg_temp.ok(not (realisasi.activity_detail(pg_temp.aid(14)) ? 'linked_activities'), 'no linked activities any more');

-- ---- IO staff (all are in the mobility team since Revisi V.1): all activities and participants --------------------
:as_part
select pg_temp.eq((select count(*) from realisasi.activities), (select n_all from _f), 'IO staff sees all');
select pg_temp.ok((select count(*) > 50 from realisasi.participant_students), 'IO staff reads all participant rows');
select pg_temp.ok(realisasi.can_read_file((select fsd_transcript from _f)), 'IO staff reads mobility bundles');
select pg_temp.ok(realisasi.can_read_file((select fsd_draft from _f)), 'IO reads draft files');
select pg_temp.eq((select count(*) from realisasi.participant_conflicts), 14::bigint, 'IO staff reads conflicts');
select pg_temp.eq(jsonb_array_length(realisasi.conflict_list()), 2, 'conflict_list: 2 open');
select pg_temp.eq(jsonb_array_length(realisasi.conflict_list(pg_temp.aid(13), null)), 14, 'conflict_list per activity, all statuses');
select pg_temp.eq((select count(*) from realisasi.email_outbox), 0::bigint, 'outbox admin only');
:as_mob
select pg_temp.eq(realisasi.nav_counts() - 'unread_notifications', '{"mobility_queue":3,"conflicts_open":2,"revision_inbox":0}'::jsonb, 'mobility nav counts');
select pg_temp.eq((select count(*) from realisasi.v_activity_list where open_conflicts > 0), 2::bigint, 'open_conflicts in the list (S-13, S-18)');
select pg_temp.ok(jsonb_array_length(realisasi.kpi_participant_rows(1, 'full')) > 0, 'mobility may export participant rows');
select pg_temp.ok(not exists (select 1 from information_schema.columns where table_schema = 'realisasi' and column_name like '%sla%'),
                  'no SLA columns anywhere');

-- ---- unit FSD: own transcripts ---------------------------------------------------------------------------------
:as_fsd
select pg_temp.ok(realisasi.can_read_file((select fsd_transcript from _f)), 'FSD reads own transcripts');
select pg_temp.eq((select size_bytes from realisasi.storage_get((select fsd_transcript from _f))), (select size_bytes from realisasi.storage_get((select fsd_transcript from _f))),
                  'storage_get works for owner');

-- ---- io_admin: everything --------------------------------------------------------------------------------------
:as_admin
select pg_temp.ok((select count(*) > 0 from realisasi.email_outbox), 'admin reads outbox');
select pg_temp.ok((select count(*) > 50 from realisasi.participant_students), 'admin reads participants');
select pg_temp.eq((realisasi.activity_detail(pg_temp.aid(13)) #>> '{permissions,can_edit_verified_detail}')::boolean, true, 'admin edits verified detail');
select pg_temp.eq(realisasi.log_export('participants', '{"ay":1}', 40, true) > 0, true, 'R-63 export logged');
select pg_temp.eq((select contains_personal_data from realisasi.export_log where actor_id = auth.uid()), true, 'export_log row');
select pg_temp.eq(realisasi.mark_notifications_read(null) >= 1, true, 'mark_notifications_read');
select pg_temp.eq((select count(*) from realisasi.notifications where recipient_id = auth.uid() and read_at is null), 0::bigint, 'all read');

-- admin settings / calendar RPCs are io_admin only
:as_part
select pg_temp.throws($$select realisasi.update_settings('{"revision_reminder_days": 2}')$$, 'AUTH_FORBIDDEN', 'settings admin only');
select pg_temp.throws($$select realisasi.set_agenda_rule(2, '{"mobility_category": null}')$$, 'AUTH_FORBIDDEN', 'agenda rules admin only');
select pg_temp.throws($$select realisasi.run_daily_jobs()$$, 'AUTH_FORBIDDEN', 'jobs admin only');
:as_admin
select pg_temp.throws($$select realisasi.update_settings('{"bogus": 1}')$$, 'SETTINGS_INVALID', 'unknown setting key');
select pg_temp.throws($$select realisasi.update_settings('{"sla_red_days": 7}')$$, 'SETTINGS_INVALID', 'SLA settings are gone');
select pg_temp.throws($$select realisasi.update_settings('{"revision_reminder_days": -1}')$$, 'SETTINGS_INVALID', 'non-negative integers');
select pg_temp.throws($$select realisasi.update_settings('{"demo_today": "31-12-2026"}')$$, 'SETTINGS_INVALID', 'demo_today format');
select pg_temp.eq(realisasi.update_settings('{"revision_reminder_days": 5, "demo_today": "2026-10-15"}') ->> 'demo_today', '2026-10-15', 'update_settings returns all keys');
select pg_temp.eq(realisasi.today(), '2026-10-15'::date, 'demo_today drives today()');
select pg_temp.eq((realisasi.now_ts() at time zone 'Asia/Jakarta')::date, '2026-10-15'::date, 'demo_today drives now_ts()');
select realisasi.update_settings('{"demo_today": null}');
select pg_temp.throws($$select realisasi.upsert_academic_year(null, '2027/2028', '2027-07-01', '2028-06-30')$$, 'CAL_INVALID_RANGE', 'overlapping AY');
create temp table _ay as select realisasi.upsert_academic_year(null, '2027/2028', '2027-08-01', '2028-07-31') as id;
select pg_temp.eq((select count(*) from realisasi.semesters s join _ay on s.academic_year_id = _ay.id), 2::bigint, 'new AY auto-creates two semesters');
select pg_temp.eq((select cutoff_date from realisasi.semesters s join realisasi.academic_years ay on ay.id = s.academic_year_id where ay.label = '2027/2028' and term = 'ganjil'),
                  '2028-03-01'::date, 'Ganjil end + 30 cutoff');
select pg_temp.throws($$select realisasi.upsert_semester(1, 1, 'ganjil', '2025-08-01', '2026-02-15', '2026-02-10')$$, 'CAL_INVALID_RANGE', 'cutoff >= end');
-- Jenis Kegiatan rules over SIMKS agendas (Revisi V.1)
select pg_temp.eq(realisasi.set_agenda_rule(27, '{"mobility_category":"short_summer"}') ->> 'mobility_category', 'short_summer', 'Academic Visit becomes mobility');
select pg_temp.ok(realisasi.agenda_is_mobility(27), 'agenda_is_mobility follows the rule');
select pg_temp.eq(realisasi.set_agenda_rule(27, '{"mobility_category":null,"counts_for_s1":false}') -> 'counts_for_s1', 'false'::jsonb, 'rule cleared, S1 off');
select pg_temp.ok(not realisasi.agenda_is_mobility(27), 'no longer mobility');
select pg_temp.throws($$select realisasi.set_agenda_rule(27, '{"mobility_category":"space_travel"}')$$, 'VALIDATION_INVALID', 'unknown category');
select pg_temp.throws($$select realisasi.set_agenda_rule(1, '{"mobility_category":null}')$$, 'NOT_FOUND', 'amendment agenda is not a Jenis');
rollback;
