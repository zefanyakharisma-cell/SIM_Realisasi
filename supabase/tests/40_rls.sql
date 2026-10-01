-- 40_rls: Rules §10 access matrix per role, AT-11 (DB side), file access.
\ir _helpers.inc

create temp table _f as
select (select storage_path from realisasi.activity_files where activity_id = pg_temp.aid(13) and kind = 'ia') as fti_verified,
       (select storage_path from realisasi.activity_files where activity_id = pg_temp.aid(17) and kind = 'ia') as fbe_revision,
       (select storage_path from realisasi.activity_files where activity_id = pg_temp.aid(23) and kind = 'ia') as fsd_draft,
       (select transcript_path from realisasi.participant_students s join realisasi.participant_set_versions v on v.id = s.set_version_id
         where v.activity_id = pg_temp.aid(11) limit 1) as fsd_transcript,
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
select pg_temp.eq((select count(*) from realisasi.duplicate_candidates), 0::bigint, 'viewer: no duplicates');
select pg_temp.eq((select count(*) from realisasi.known_activities), 0::bigint, 'viewer: no known register');
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
select pg_temp.ok(not realisasi.can_read_file((select fsd_transcript from _f)), 'viewer cannot read transcripts');
select pg_temp.throws(format('select * from realisasi.storage_get(%L)', (select fsd_transcript from _f)), 'FILE_FORBIDDEN', 'storage_get transcript forbidden');
select pg_temp.eq((select count(*) from realisasi.notifications where recipient_id <> auth.uid()), 0::bigint, 'notifications: own only');
select pg_temp.eq(realisasi.nav_counts() - 'unread_notifications', '{"partnership_queue":0,"mobility_queue":0,"duplicates_open":0,"revision_inbox":0}'::jsonb, 'viewer nav counts');
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
select pg_temp.eq((select count(*) from realisasi.known_activities), 0::bigint, 'submitter: no register');
select pg_temp.eq((select count(*) from realisasi.duplicate_candidates), 0::bigint, 'submitter: no duplicates');
select pg_temp.eq((select count(*) from realisasi.v_activity_list where duplicate_open), 0::bigint, 'duplicate_open false for non-IO');
select pg_temp.ok((select count(*) > 0 from realisasi.activity_log where activity_id = pg_temp.aid(13)), 'submitter reads own activity log');
select pg_temp.ok(realisasi.can_read_file((select fti_verified from _f)), 'FTI reads own file');
select pg_temp.ok(not realisasi.can_read_file((select fbe_revision from _f)), 'FTI cannot read FBE file');
select pg_temp.throws($$select realisasi.activity_detail(pg_temp.aid(17))$$, 'NOT_FOUND', 'other unit activity_detail NOT_FOUND');
select pg_temp.eq((realisasi.activity_detail(pg_temp.aid(16)) -> 'permissions') - 'can_view_participants' - 'can_view_log',
  '{"can_edit_draft":false,"can_delete_draft":false,"can_edit_detail":false,"can_edit_files":false,"can_edit_participants":true,"can_submit":true,
    "can_partnership_verify":false,"can_reject":false,"can_mobility_verify":false,"can_edit_verified_detail":false,"can_edit_verified_participants":false,
    "can_link_duplicate":false,"can_unlink_duplicate":false}'::jsonb, 'S-16 permissions for FTI');
select pg_temp.ok(realisasi.activity_detail(pg_temp.aid(16)) -> 'checklist' is not null, 'checklist present when can_submit');
select pg_temp.eq(realisasi.activity_detail(pg_temp.aid(13)) -> 'duplicates', '[]'::jsonb, 'duplicates hidden for non-IO');
select pg_temp.eq((realisasi.nav_counts() ->> 'revision_inbox')::int, 1, 'FTI revision inbox (S-16)');

-- co-unit read-only visibility: kaprodi Informatika sees S-14 but not S-13 (exact unit match, no roll-up)
:as_inf
select pg_temp.ok(exists (select 1 from realisasi.activities where id = pg_temp.aid(14)) and not exists (select 1 from realisasi.activities where id = pg_temp.aid(13)),
                  'unit scope is exact-match');
select pg_temp.eq((realisasi.activity_detail(pg_temp.aid(14)) #>> '{linked_activities,0,code}'), 'RL-2026-0013', 'linked activity listed');

-- ---- IO Partnership: all activities, participant counts only, register R/W ------------------------------------------
:as_part
select pg_temp.eq((select count(*) from realisasi.activities), (select n_all from _f), 'partnership sees all');
select pg_temp.eq((select count(*) from realisasi.participant_students), 0::bigint, 'partnership: participant names hidden (counts only)');
select pg_temp.ok(not realisasi.can_read_file((select fsd_transcript from _f)), 'partnership cannot read transcripts');
select pg_temp.ok(realisasi.can_read_file((select fsd_draft from _f)), 'IO reads draft files');
select pg_temp.eq((select count(*) from realisasi.known_activities), 8::bigint, 'partnership reads register');
select pg_temp.eq((select count(*) from realisasi.v_duplicate_candidates), 2::bigint, 'partnership reads duplicates');
select pg_temp.eq((select a_participants + b_participants from realisasi.v_duplicate_candidates where status = 'open'), 3, 'candidate participant counts via definer helper');
select pg_temp.eq((select count(*) from realisasi.email_outbox), 0::bigint, 'outbox admin only');
select pg_temp.eq(realisasi.nav_counts() - 'unread_notifications', '{"partnership_queue":4,"mobility_queue":0,"duplicates_open":1,"revision_inbox":0}'::jsonb, 'partnership nav counts');
select pg_temp.eq((select count(*) from realisasi.v_activity_list where partnership_sla_level = 'red'), 1::bigint, 'SLA red in list');

-- ---- IO Mobility: participants of all activities -----------------------------------------------------------------
:as_mob
select pg_temp.ok((select count(*) > 50 from realisasi.participant_students), 'mobility reads all participant rows');
select pg_temp.ok(realisasi.can_read_file((select fsd_transcript from _f)), 'mobility reads transcripts');
select pg_temp.eq((select count(*) from realisasi.known_activities), 8::bigint, 'mobility views register');
select pg_temp.throws($$select realisasi.create_known_activity('{"title":"x","activity_date":"2026-09-01","is_international":true,"source":"email"}')$$,
                      'AUTH_FORBIDDEN', 'R-51 mobility cannot write register');
select pg_temp.eq(realisasi.nav_counts() - 'unread_notifications', '{"partnership_queue":0,"mobility_queue":3,"duplicates_open":1,"revision_inbox":0}'::jsonb, 'mobility nav counts');
select pg_temp.ok(jsonb_array_length(realisasi.kpi_participant_rows(1, 'full')) > 0, 'mobility may export participant rows');

-- ---- unit FSD: own transcripts ---------------------------------------------------------------------------------
:as_fsd
select pg_temp.ok(realisasi.can_read_file((select fsd_transcript from _f)), 'FSD reads own transcripts');
select pg_temp.eq((select size_bytes from realisasi.storage_get((select fsd_transcript from _f))), (select size_bytes from realisasi.storage_get((select fsd_transcript from _f))),
                  'storage_get works for owner');

-- ---- io_admin: everything --------------------------------------------------------------------------------------
:as_admin
select pg_temp.ok((select count(*) > 0 from realisasi.email_outbox), 'admin reads outbox');
select pg_temp.ok((select count(*) > 50 from realisasi.participant_students), 'admin reads participants');
select pg_temp.eq((realisasi.activity_detail(pg_temp.aid(13)) #>> '{permissions,can_unlink_duplicate}')::boolean, true, 'admin can unlink linked S-13');
select pg_temp.eq(realisasi.log_export('participants', '{"ay":1}', 40, true) > 0, true, 'R-63 export logged');
select pg_temp.eq((select contains_personal_data from realisasi.export_log where actor_id = auth.uid()), true, 'export_log row');
select pg_temp.eq(realisasi.mark_notifications_read(null) >= 1, true, 'mark_notifications_read');
select pg_temp.eq((select count(*) from realisasi.notifications where recipient_id = auth.uid() and read_at is null), 0::bigint, 'all read');

-- admin settings / calendar RPCs are io_admin only
:as_part
select pg_temp.throws($$select realisasi.update_settings('{"sla_yellow_days": 2}')$$, 'AUTH_FORBIDDEN', 'settings admin only');
select pg_temp.throws($$select realisasi.upsert_holiday('2026-12-24', 'Cuti bersama')$$, 'AUTH_FORBIDDEN', 'holidays admin only');
select pg_temp.throws($$select realisasi.run_daily_jobs()$$, 'AUTH_FORBIDDEN', 'jobs admin only');
:as_admin
select pg_temp.throws($$select realisasi.update_settings('{"bogus": 1}')$$, 'SETTINGS_INVALID', 'unknown setting key');
select pg_temp.throws($$select realisasi.update_settings('{"sla_red_days": 2}')$$, 'SETTINGS_INVALID', 'red must exceed yellow');
select pg_temp.throws($$select realisasi.update_settings('{"dup_name_similarity": 1.5}')$$, 'SETTINGS_INVALID', 'similarity range');
select pg_temp.throws($$select realisasi.update_settings('{"demo_today": "31-12-2026"}')$$, 'SETTINGS_INVALID', 'demo_today format');
select pg_temp.eq(realisasi.update_settings('{"sla_yellow_days": 2, "demo_today": "2026-10-15"}') ->> 'demo_today', '2026-10-15', 'update_settings returns all keys');
select pg_temp.eq(realisasi.today(), '2026-10-15'::date, 'demo_today drives today()');
select pg_temp.eq((realisasi.now_ts() at time zone 'Asia/Jakarta')::date, '2026-10-15'::date, 'demo_today drives now_ts()');
select realisasi.update_settings('{"demo_today": null}');
select pg_temp.throws($$select realisasi.upsert_academic_year(null, '2027/2028', '2027-07-01', '2028-06-30')$$, 'CAL_INVALID_RANGE', 'overlapping AY');
create temp table _ay as select realisasi.upsert_academic_year(null, '2027/2028', '2027-08-01', '2028-07-31') as id;
select pg_temp.eq((select count(*) from realisasi.semesters s join _ay on s.academic_year_id = _ay.id), 2::bigint, 'new AY auto-creates two semesters');
select pg_temp.eq((select cutoff_date from realisasi.semesters s join realisasi.academic_years ay on ay.id = s.academic_year_id where ay.label = '2027/2028' and term = 'ganjil'),
                  '2028-03-01'::date, 'Ganjil end + 30 cutoff');
select pg_temp.throws($$select realisasi.upsert_semester(1, 1, 'ganjil', '2025-08-01', '2026-02-15', '2026-02-10')$$, 'CAL_INVALID_RANGE', 'cutoff >= end');
select pg_temp.eq(realisasi.upsert_activity_type(null, '{"name":"Joint Workshop","direction":"none"}') > 9, true, 'new Jenis');
select realisasi.upsert_holiday('2026-12-24', 'Cuti bersama Natal');
select realisasi.delete_holiday('2026-12-24');
select pg_temp.throws($$select realisasi.delete_holiday('2026-12-24')$$, 'NOT_FOUND', 'delete missing holiday');
rollback;
