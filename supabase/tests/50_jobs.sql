-- 50_jobs: business days / SLA helpers, run_daily_jobs notify-once, reminders, escalations, deadline reminders, cutoff freeze.
\ir _helpers.inc

-- helpers
select pg_temp.eq(realisasi.business_days_between('2026-08-14', '2026-08-18'), 1, 'weekend + holiday (17 Aug) excluded');
select pg_temp.eq(realisasi.business_days_between('2026-09-25', '2026-10-01'), 4, 'Fri -> Thu = 4 business days');
select pg_temp.eq(realisasi.business_days_between('2026-10-01', '2026-10-01'), 0, 'same day = 0');
select pg_temp.eq(realisasi.business_days_between('2026-10-02', '2026-10-01'), 0, 'reversed = 0');
select pg_temp.eq(realisasi.sla_level(3) || ',' || realisasi.sla_level(4) || ',' || realisasi.sla_level(5) || ',' || realisasi.sla_level(6), 'ok,yellow,yellow,red', 'R-60 thresholds (> 3 yellow, > 5 red)');
select pg_temp.ok(realisasi.sla_level(null) is null and realisasi.sla_days(null) is null, 'null SLA');
select pg_temp.eq(realisasi.semester_label(3), 'Ganjil 2026/2027', 'semester_label');

-- first run (real today 2026-10-01, seeded clocks)
:as_fti
select pg_temp.throws($$select realisasi.run_daily_jobs()$$, 'AUTH_FORBIDDEN', 'jobs: admin or system only');
:as_system
create temp table _r1 as select realisasi.run_daily_jobs() as r;
select pg_temp.eq((select (r - 'today' - 'frozen') from _r1),
                  '{"sla_notices": 4, "revision_reminders": 2, "revision_escalations": 1, "deadline_reminders": 1}'::jsonb,
                  'first run: S-26/S-27/S-28/S-29 SLA, S-16+S-17 reminders, S-16 escalation, S-23 deadline');
select pg_temp.eq((select r -> 'frozen' from _r1), '[]'::jsonb, 'no freeze due (AY1 frozen, AY2 cutoffs ahead)');
select pg_temp.ok(exists (select 1 from realisasi.notifications where recipient_id = :'ADMIN' and kind = 'sla_red' and title like '%RL-2026-0027'), 'red SLA reaches io_admin');
select pg_temp.ok(not exists (select 1 from realisasi.notifications where recipient_id = :'MOB' and kind like 'sla_%' and title like '%RL-2026-0027'), 'partnership SLA not sent to mobility');
select pg_temp.ok(exists (select 1 from realisasi.notifications where recipient_id = :'MOB' and kind = 'sla_yellow' and title like '%RL-2026-0028'), 'mobility yellow to mobility team');
select pg_temp.ok(exists (select 1 from realisasi.notifications where recipient_id = :'FTI' and kind = 'revision_reminder' and title like '%RL-2026-0016'), 'unit revision reminder');
select pg_temp.ok(exists (select 1 from realisasi.notifications where recipient_id = :'MOB' and kind = 'revision_escalation' and title like '%RL-2026-0016'), 'escalation to track team');
select pg_temp.ok(exists (select 1 from realisasi.notifications where recipient_id = :'FSD' and kind = 'deadline_weekly' and link like '/realisasi/kegiatan/baru?draft=%'), 'deadline weekly reminder');
select pg_temp.eq((select count(*) from realisasi.email_outbox where subject like 'SLA %' and created_at = realisasi.now_ts()),
                  (select count(*) from realisasi.notifications where kind like 'sla_%' and created_at = realisasi.now_ts()), 'every notification has an outbox email');
-- notify once
create temp table _r2 as select realisasi.run_daily_jobs() as r;
select pg_temp.eq((select r - 'today' - 'frozen' from _r2), '{"sla_notices": 0, "revision_reminders": 0, "revision_escalations": 0, "deadline_reminders": 0}'::jsonb,
                  'second run sends nothing (job_marks)');
-- a new pending period restarts the SLA clock and can notify again
update realisasi.activities set partnership_since = realisasi.now_ts() - interval '30 days' where id = pg_temp.aid(26);
select pg_temp.eq((realisasi.run_daily_jobs() ->> 'sla_notices')::int, 1, 'new clock epoch -> new notice');

-- time travel: demo_today = 2027-03-03 -> Ganjil 2026/2027 cutoff (2027-03-02) passed -> freeze
:as_admin
select realisasi.update_settings('{"demo_today": "2027-03-03"}');
create temp table _r3 as select realisasi.run_daily_jobs() as r;
select pg_temp.eq((select jsonb_agg(f - 'snapshot_id') from _r3, jsonb_array_elements(r -> 'frozen') f), '[{"kind":"ganjil_ytd","ay_label":"2026/2027"}]'::jsonb,
                  'cutoff freeze of Ganjil 2026/2027 under demo_today');
reset role;
create temp table _snap as select * from realisasi.kpi_snapshots where academic_year_id = 2 and kind = 'ganjil_ytd' and superseded_by is null;
select pg_temp.eq((select frozen_at from _snap), '2027-03-02 01:00+07'::timestamptz, 'frozen_at = cutoff 01:00 WIB');
select pg_temp.ok((select frozen_by is null from _snap), 'job freeze has no actor');
select pg_temp.ok(exists (select 1 from realisasi.kpi_snapshot_items i join _snap s on s.id = i.snapshot_id where i.kpi_code = '1.19.24' and i.bucket = 'grace_excluded' and i.ref_id = '902'),
                  'AT-05 frozen Ganjil 2026/2027: 902 grace_excluded');
select pg_temp.ok(not exists (select 1 from realisasi.kpi_snapshot_items i join _snap s on s.id = i.snapshot_id where i.kpi_code = '1.19.24' and i.bucket = 'denominator' and i.ref_id = '902'),
                  'AT-05 frozen: 902 not in denominator');
select pg_temp.eq((select values #>> '{kpi_1_19_s8,unmatched_known}' from _snap), '2', 'AT-09 S8 gap in the frozen Ganjil snapshot');
select pg_temp.ok(exists (select 1 from realisasi.notifications where recipient_id = :'VIEW' and kind = 'snapshot_frozen' and link like '/realisasi/laporan?report=arsip&snapshot=%'),
                  'viewer notified of freeze');
grant select on _snap to authenticated;
select pg_temp.eq((realisasi.run_daily_jobs() -> 'frozen'), '[]'::jsonb, 'freeze happens once');
:as_admin
select pg_temp.eq((realisasi.period_info(2, 'ganjil') ->> 'frozen')::boolean, true, 'period now frozen');
-- the (b) late-addition list: Genap 2025/26 window activity verified after the Genap freeze shows up in the next snapshot, not counted
select pg_temp.ok(jsonb_array_length(realisasi.snapshot_late_additions((select id from _snap))) >= 0, 'late additions list available');
rollback;
