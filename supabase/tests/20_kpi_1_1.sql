-- 20_kpi_1_1: AT-01 (event-group dedupe vs unit double count), AT-02 (per person per event), R-38..R-40.
\ir _helpers.inc

-- AT-01: S-13 (FTI) + S-14 (Informatika), 12 shared students, linked in event group …13
select pg_temp.eq(count(*), 12::bigint, 'AT-01 university: 12 outbound rows for the S-13/S-14 event group')
  from realisasi.kpi_items('2026-08-01', '2027-01-31', '2027-03-02', 2) i
  join realisasi.activities a on a.id = i.activity_id
 where i.kpi_code = '1.1' and i.bucket = 'outbound' and a.event_group_id = 'e0000000-0000-4000-8000-000000000013';
select pg_temp.eq(min(i.activity_id::text), pg_temp.aid(13)::text, 'representative = earliest verified (S-13)')
  from realisasi.kpi_items('2026-08-01', '2027-01-31', '2027-03-02', 2) i
  join realisasi.activities a on a.id = i.activity_id where i.kpi_code = '1.1' and a.event_group_id = 'e0000000-0000-4000-8000-000000000013';
select pg_temp.eq((realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2, null, 10) #>> '{kpi_1_1,outbound}')::int, 12, 'AT-01 FTI unit outbound = 12');
select pg_temp.eq((realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2, null, 11) #>> '{kpi_1_1,outbound}')::int, 12, 'AT-01 Informatika unit outbound = 12');
select pg_temp.eq((realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2) #>> '{kpi_1_1,outbound}')::int, 15, 'university live outbound = 12 (S-13/14) + 3 (S-10)');
select pg_temp.eq((realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2) #>> '{kpi_1_1,inbound}')::int, 4, 'university live inbound (S-11)');
select pg_temp.eq((select x -> 'kpi_1_1' ->> 'outbound' from jsonb_array_elements(realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2) -> 'by_unit') x
                    where (x ->> 'unit_id')::int = 11), '12', 'by_unit entry = unit computation (R-39 counted in both units)');

-- AT-02: D31240187 in S-15a and S-15b (different event groups) contributes 2
select pg_temp.eq(count(*), 2::bigint, 'AT-02 D31240187 contributes 2 in AY 2025/2026 Genap')
  from realisasi.kpi_items('2026-02-01', '2026-07-31', '2026-07-31', 1) where kpi_code = '1.1' and ref_id like '%:D31240187';
select pg_temp.eq(count(*), 2::bigint, 'AT-02 also 2 for the full year (unit FBE)')
  from realisasi.kpi_items('2025-08-01', '2026-07-31', '2026-08-30', 1, null, 20) where kpi_code = '1.1' and ref_id like '%:D31240187';

-- R-38 only approved versions of verified activities; sections by direction
select pg_temp.ok(not exists (select 1 from realisasi.kpi_items('2025-08-01', '2027-07-31', '2027-07-31', null) i
                               join realisasi.activities a on a.id = i.activity_id where i.kpi_code = '1.1' and a.status <> 'verified'),
                  'only verified activities');
select pg_temp.ok(not exists (select 1 from realisasi.kpi_items('2025-08-01', '2027-07-31', '2027-07-31', null) where kpi_code = '1.1'
                               and activity_id in (pg_temp.aid(16), pg_temp.aid(18), pg_temp.aid(29))), 'S-16/S-18/S-29 (not verified) excluded');
select pg_temp.ok(not exists (select 1 from realisasi.kpi_items('2025-08-01', '2026-07-31', '2026-08-30', 1) i where i.kpi_code = '1.1' and i.bucket = 'inbound'
                               and split_part(i.ref_id, ':', 2) not like 'X%'), 'inbound counts only inbound section');
select pg_temp.ok(not exists (select 1 from realisasi.kpi_items('2025-08-01', '2026-07-31', '2026-08-30', 1) i where i.kpi_code = '1.1' and i.bucket = 'outbound'
                               and split_part(i.ref_id, ':', 2) like 'X%'), 'outbound counts only internal section');
select pg_temp.ok(not exists (select 1 from realisasi.kpi_items('2025-08-01', '2026-07-31', '2026-08-30', 1) i where i.kpi_code = '1.1' and i.ref_id like '%:PG%'),
                  'staff never counted (R-19)');

-- R-40 per semester; wrapper agrees with kpi_items
select pg_temp.eq((select jsonb_agg(jsonb_build_object('label', s ->> 'label', 'in', s -> 'inbound', 'out', s -> 'outbound'))
                     from jsonb_array_elements(realisasi.compute_kpis('2025-08-01', '2026-07-31', '2026-08-30', 1) #> '{kpi_1_1,by_semester}') s),
  '[{"label":"Ganjil 2025/2026","in":3,"out":4},{"label":"Genap 2025/2026","in":2,"out":10}]'::jsonb, 'R-40 by_semester AY 2025/2026');
select pg_temp.eq((select students from realisasi.kpi_1_1('2026-08-01', '2026-10-01') where direction = 'outbound'), 15::bigint, 'Schema wrapper kpi_1_1');

-- linking a mobility approval later changes nothing for unverified; approving S-29 adds inbound students
:as_part
select realisasi.partnership_approve(pg_temp.aid(25));
:as_mob
select realisasi.mobility_approve(pg_temp.aid(29));
reset role;
select pg_temp.eq((realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2) #>> '{kpi_1_1,inbound}')::int, 6, 'S-29 verified adds 2 inbound');

-- kpi_participant_rows (personal data) agree with the 1.1 items
:as_mob
select pg_temp.eq(jsonb_array_length(realisasi.kpi_participant_rows(2, 'live')), 21, 'participant rows = 1.1 items (live, after S-29)');
:as_fti
select pg_temp.eq(jsonb_array_length(realisasi.kpi_participant_rows(2, 'live', 20)), 12, 'submitter forced to own unit (FTI)');
:as_part
select pg_temp.throws($$select realisasi.kpi_participant_rows(2, 'live')$$, 'AUTH_FORBIDDEN', 'partnership-only staff: counts only');

-- drill-down rows aggregate per activity without personal data
select pg_temp.eq((select jsonb_agg(r ->> 'code' || ':' || (r ->> 'students')) from jsonb_array_elements(realisasi.kpi_drilldown(2, 'live', '1.1', 'outbound') -> 'rows') r),
                  '["RL-2026-0010:3", "RL-2026-0013:12"]'::jsonb, 'drilldown 1.1 rows');
select pg_temp.ok(not (realisasi.kpi_drilldown(2, 'live', '1.1')::text like '%B11227366%'), 'drilldown has no NRPs');
rollback;
