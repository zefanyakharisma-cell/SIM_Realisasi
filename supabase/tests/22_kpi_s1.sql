-- 22_kpi_s1: R-41 (KPI 1.19.S1). Revisi V.1: KPI 1.19.S8 and the Known Activities register are gone; every activity is
-- its own event group (no linking), so S1 counts activities.
\ir _helpers.inc

select pg_temp.eq(realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2) -> 'kpi_1_19_s1', '{"international": 9, "domestic": 4}'::jsonb,
                  'R-41 YTD 2026/2027 S1');
select pg_temp.eq(count(*), 2::bigint, 'S-13 and S-14 are separate activities') from realisasi.kpi_items('2026-08-01', '2026-10-01', '2026-10-01', 2)
 where kpi_code = '1.19.S1' and activity_id in (pg_temp.aid(13), pg_temp.aid(14));
select pg_temp.eq(realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2, null, 11) -> 'kpi_1_19_s1', '{"international": 1, "domestic": 0}'::jsonb,
                  'unit level (Informatika)');
select pg_temp.eq(count(*), 1::bigint, 'S-21 counted once') from realisasi.kpi_items('2025-08-01', '2026-07-31', '2026-08-30', 1)
 where kpi_code = '1.19.S1' and activity_id = pg_temp.aid(21);
select pg_temp.eq(bucket, 'domestic', 'S-22 domestic (UGM)') from realisasi.kpi_items('2026-08-01', '2026-10-01', '2026-10-01', 2)
 where kpi_code = '1.19.S1' and activity_id = pg_temp.aid(22);
select pg_temp.eq(realisasi.kpi_1_19_s1('2026-08-01', '2026-10-01'), 9::bigint, 'Schema wrapper kpi_1_19_s1');
-- agenda rule counts_for_s1 = false excludes that Jenis
insert into realisasi.agenda_rules (agenda_id, counts_for_s1) values (4, false);
select pg_temp.eq((realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2) #>> '{kpi_1_19_s1,international}')::int, 7,
                  'counts_for_s1=false excludes Joint Research (S-09, S-27)');
delete from realisasi.agenda_rules where agenda_id = 4;
-- no S8 left anywhere
select pg_temp.ok(not (realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2) ? 'kpi_1_19_s8'), 'no KPI 1.19.S8 in values');
select pg_temp.eq(count(*), 0::bigint, 'no S8 items') from realisasi.kpi_items('2025-08-01', '2027-07-31', '2027-07-31', null) where kpi_code = '1.19.S8';

-- dashboard / drill-down read models carry the same numbers
:as_admin
select pg_temp.eq(realisasi.dashboard(2, 'ytd') #> '{values,kpi_1_19_s1,international}', '9'::jsonb, 'dashboard values = compute_kpis');
select pg_temp.throws($$select realisasi.kpi_drilldown(2, 'ytd', '1.19.S8')$$, 'VALIDATION_INVALID', 'S8 drill-down no longer exists');
select pg_temp.eq((select jsonb_agg(r ->> 'code' order by r ->> 'code') from jsonb_array_elements(realisasi.kpi_drilldown(2, 'ytd', '1.19.S1', 'domestic') -> 'rows') r),
                  '["RL-2026-0012", "RL-2026-0022", "RL-2026-0025", "RL-2026-0033"]'::jsonb, 'S1 drilldown rows');
select pg_temp.eq((select r ->> 'agenda_name' from jsonb_array_elements(realisasi.kpi_drilldown(2, 'ytd', '1.19.S1') -> 'rows') r where r ->> 'code' = 'RL-2026-0013'),
                  'Short Program', 'agenda name on row');
:as_fbe
select pg_temp.eq(realisasi.dashboard(2, 'ytd', null) #> '{scope,unit_id}', '20'::jsonb, 'submitter dashboard forced to own unit');
select pg_temp.eq(realisasi.dashboard(2, 'ytd', 10) #> '{scope,unit_id}', '20'::jsonb, 'submitter cannot pick another unit');
select pg_temp.ok(realisasi.dashboard(2, 'ytd') -> 'work_queue' = 'null'::jsonb, 'no work queue for units');
:as_mob
select pg_temp.eq(realisasi.dashboard(2, 'ytd') #> '{work_queue,mobility_pending}', '3'::jsonb, 'work queue: 3 waiting for Mobility');
select pg_temp.eq(realisasi.dashboard(2, 'ytd') #> '{work_queue,conflicts_open}', '2'::jsonb, 'work queue: 2 open conflicts');
:as_fsd
-- deadline 2026-09-13; relative to today() so the check holds after midnight WIB too
select pg_temp.eq((realisasi.dashboard(2, 'ytd') -> 'drafts_near_deadline' -> 0 ->> 'days_left')::int, '2026-09-13'::date - realisasi.today(),
                  'S-23 in drafts_near_deadline (deadline passed)');
rollback;
