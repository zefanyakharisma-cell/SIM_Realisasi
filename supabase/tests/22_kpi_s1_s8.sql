-- 22_kpi_s1_s8: R-41 (KPI 1.19.S1), R-48..R-50 + AT-09 (KPI 1.19.S8).
\ir _helpers.inc

-- R-41 distinct event groups of verified international counts_for_s1 activities
select pg_temp.eq(realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2) -> 'kpi_1_19_s1', '{"international": 4, "domestic": 2}'::jsonb,
                  'R-41 Live 2026/2027 S1 (S-13/S-14 one group)');
select pg_temp.eq(count(*), 1::bigint, 'S-13/S-14 group counted once') from realisasi.kpi_items('2026-08-01', '2026-10-01', '2026-10-01', 2)
 where kpi_code = '1.19.S1' and activity_id in (pg_temp.aid(13), pg_temp.aid(14));
select pg_temp.eq(realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2, null, 11) -> 'kpi_1_19_s1', '{"international": 1, "domestic": 0}'::jsonb,
                  'unit level counts the linked activity');
select pg_temp.eq(count(*), 1::bigint, 'S-21 with two countries counted once') from realisasi.kpi_items('2025-08-01', '2026-07-31', '2026-08-30', 1)
 where kpi_code = '1.19.S1' and activity_id = pg_temp.aid(21);
select pg_temp.eq(bucket, 'domestic', 'S-22 domestic (UGM)') from realisasi.kpi_items('2026-08-01', '2026-10-01', '2026-10-01', 2)
 where kpi_code = '1.19.S1' and activity_id = pg_temp.aid(22);
select pg_temp.eq(realisasi.kpi_1_19_s1('2026-08-01', '2026-10-01'), 4::bigint, 'Schema wrapper kpi_1_19_s1');
-- a non-S1 type is not counted in S1 but still counts for S8 (any type)
update realisasi.activity_types set counts_for_s1 = false where id = 5;
select pg_temp.eq((realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2) #>> '{kpi_1_19_s1,international}')::int, 3, 'counts_for_s1=false excludes Joint Research (S-09)');
select pg_temp.eq((realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2) #>> '{kpi_1_19_s8,reported}')::int, 4, 'S8 counts any type (R-48)');
update realisasi.activity_types set counts_for_s1 = true where id = 5;

-- AT-09: 5 matched, 2 unmatched international, 1 dismissed in the Ganjil 2026/2027 window
select pg_temp.eq(realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2) -> 'kpi_1_19_s8', '{"reported": 4, "unmatched_known": 2, "pct": 66.7}'::jsonb,
                  'AT-09 Live S8: denominator = reported + 2');
select pg_temp.eq((select reported || '/' || unmatched_known || '/' || pct from realisasi.kpi_1_19_s8('2026-08-01', '2026-10-01')), '4/2/66.7', 'Schema wrapper kpi_1_19_s8');
select pg_temp.eq((realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2, null, 20) #>> '{kpi_1_19_s8,unmatched_known}')::int, 1, 'unit FBE: known #6');
-- as_of 2026-09-15: #7 (created 2026-09-23) not yet known; #2..#4 are matched to activities verified only after
-- 2026-09-15, so at that moment they are still gaps (review H3: matched counts only via a qualifying reported activity)
select pg_temp.eq((realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2, '2026-09-15 00:00+07') #>> '{kpi_1_19_s8,unmatched_known}')::int, 4,
                  'as_of: known #7 not yet known; #2..#4 matched to not-yet-verified activities are gaps');
-- R-50 matching an entry to its (verified, international) SIM activity removes it from the gap
:as_part
select realisasi.match_known_activity(6, pg_temp.aid(17));
reset role;
select pg_temp.eq((realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2) #>> '{kpi_1_19_s8,unmatched_known}')::int, 2,
                  'R-50/H3 entry matched to an activity still in revision stays in the gap');
:as_part
select realisasi.unmatch_known_activity(6);
select realisasi.match_known_activity(6, pg_temp.aid(10));
reset role;
select pg_temp.eq((realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2) #>> '{kpi_1_19_s8,unmatched_known}')::int, 1, 'R-50 matched entry leaves the gap');
:as_part
select realisasi.unmatch_known_activity(6);
select realisasi.create_known_activity('{"title":"Visiting researcher dari Korea","activity_date":"2026-09-20","unit_id":10,"is_international":true,"source":"email"}');
select realisasi.create_known_activity('{"title":"Seminar lokal","activity_date":"2026-09-20","unit_id":10,"is_international":false,"source":"email"}');
reset role;
select pg_temp.eq((realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2) #>> '{kpi_1_19_s8,unmatched_known}')::int, 3, 'new unmatched international entry counts; domestic ignored');

-- dashboard / drill-down read models carry the same numbers
:as_admin
select pg_temp.eq(realisasi.dashboard(2, 'live') #> '{values,kpi_1_19_s8,unmatched_known}', '3'::jsonb, 'dashboard values = compute_kpis');
select pg_temp.eq((select count(*) from jsonb_array_elements(realisasi.kpi_drilldown(2, 'live', '1.19.S8') -> 'rows') r where r ->> 'row_type' = 'known'), 3::bigint,
                  'drilldown lists unmatched known rows');
select pg_temp.eq((select count(*) from jsonb_array_elements(realisasi.kpi_drilldown(2, 'live', '1.19.S8', 'reported') -> 'rows') r), 4::bigint, 'drilldown reported rows');
select pg_temp.eq((select jsonb_agg(r ->> 'code' order by r ->> 'code') from jsonb_array_elements(realisasi.kpi_drilldown(2, 'live', '1.19.S1', 'international') -> 'rows') r),
                  '["RL-2026-0009", "RL-2026-0010", "RL-2026-0011", "RL-2026-0013"]'::jsonb, 'S1 drilldown rows');
select pg_temp.eq((select r ->> 'linked_count' from jsonb_array_elements(realisasi.kpi_drilldown(2, 'live', '1.19.S1') -> 'rows') r where r ->> 'code' = 'RL-2026-0013'), '1', 'linked_count on row');
:as_fbe
select pg_temp.eq(realisasi.dashboard(2, 'live', null) #> '{scope,unit_id}', '20'::jsonb, 'submitter dashboard forced to own unit');
select pg_temp.eq(realisasi.dashboard(2, 'live', 10) #> '{scope,unit_id}', '20'::jsonb, 'submitter cannot pick another unit');
:as_fsd
select pg_temp.eq((realisasi.dashboard(2, 'live') -> 'drafts_near_deadline' -> 0 ->> 'days_left')::int, -18, 'S-23 in drafts_near_deadline (deadline passed 18 days ago)');
rollback;
