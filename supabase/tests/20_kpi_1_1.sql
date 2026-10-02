-- 20_kpi_1_1: KPI 1.1 under Revisi V.1 rules: rule 2.1 (one student claimed by two units' overlapping activities counts
-- only on the activity Mobility kept; while open, on neither), rule 2.2 (same unit, two activities: counted in both),
-- AT-01/AT-02, R-38..R-40.
\ir _helpers.inc

-- AT-01: S-13 (FTI) and S-14 (Informatika) claim the same 12 students; Mobility kept all of them on S-13.
-- S-18 (Informatika, pending) claims 2 of them again: those 2 conflicts are still open.
select pg_temp.eq(count(*), 10::bigint, 'AT-01 S-13 counts its 12 students minus the 2 with an open conflict')
  from realisasi.kpi_items('2026-08-01', '2027-01-31', '2027-03-02', 2) i where i.kpi_code = '1.1' and i.activity_id = pg_temp.aid(13);
select pg_temp.eq(count(*), 0::bigint, 'AT-01 S-14 lost every conflict: counts nobody')
  from realisasi.kpi_items('2026-08-01', '2027-01-31', '2027-03-02', 2) i where i.kpi_code = '1.1' and i.activity_id = pg_temp.aid(14);
select pg_temp.eq((realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2, null, 10) #>> '{kpi_1_1,outbound}')::int, 10, 'AT-01 FTI unit outbound = 10');
select pg_temp.eq((realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2, null, 11) #>> '{kpi_1_1,outbound}')::int, 0, 'AT-01 Informatika unit outbound = 0');
select pg_temp.eq((realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2) #>> '{kpi_1_1,outbound}')::int, 15,
                  'university live outbound = 10 (S-13) + 2 (S-10) + 3 (S-33)');
select pg_temp.eq((realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2) #>> '{kpi_1_1,inbound}')::int, 4, 'university live inbound (S-11)');
select pg_temp.eq((select x -> 'kpi_1_1' ->> 'outbound' from jsonb_array_elements(realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2) -> 'by_unit') x
                    where (x ->> 'unit_id')::int = 10), '10', 'by_unit entry = unit computation');

-- rule 2.1: Mobility keeps the 2 open students on S-13 -> FTI back to 12; keeping them on S-18 would move them nowhere
-- until S-18 is verified
:as_mob
select realisasi.resolve_conflict(id, pg_temp.aid(13), 'Transkrip dari FTI') from realisasi.participant_conflicts where status = 'open';
reset role;
select pg_temp.eq((realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2, null, 10) #>> '{kpi_1_1,outbound}')::int, 12,
                  'rule 2.1 resolved for S-13: FTI counts all 12');
:as_mob
select pg_temp.eq(realisasi.mobility_approve(pg_temp.aid(18)) ->> 'status', 'verified', 'S-18 approvable once its conflicts are resolved');
reset role;
select pg_temp.eq(count(*), 0::bigint, 'S-18 verified but its 2 students stay with S-13')
  from realisasi.kpi_items('2026-08-01', '2027-01-31', '2027-03-02', 2) i where i.kpi_code = '1.1' and i.activity_id = pg_temp.aid(18);
select pg_temp.eq((realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2) #>> '{kpi_1_1,outbound}')::int, 17,
                  'university outbound: 12 + 2 + 3');

-- AT-02 / rule 2.2: D31240187 in S-15 and S-31, both FBE: counted in both
select pg_temp.eq(count(*), 2::bigint, 'AT-02 D31240187 contributes 2 in AY 2025/2026 Genap')
  from realisasi.kpi_items('2026-02-01', '2026-07-31', '2026-07-31', 1) where kpi_code = '1.1' and ref_id like '%:D31240187';
select pg_temp.eq(count(*), 2::bigint, 'AT-02 also 2 for the full year (unit FBE)')
  from realisasi.kpi_items('2025-08-01', '2026-07-31', '2026-08-30', 1, null, 20) where kpi_code = '1.1' and ref_id like '%:D31240187';
select pg_temp.ok(not exists (select 1 from realisasi.participant_conflicts where nrp = 'D31240187'), 'rule 2.2 same unit is never a conflict');

-- R-38 only approved versions of verified mobility kegiatan; sections by the kegiatan's direction
select pg_temp.ok(not exists (select 1 from realisasi.kpi_items('2025-08-01', '2027-07-31', '2027-07-31', null) i
                               join realisasi.activities a on a.id = i.activity_id where i.kpi_code = '1.1' and a.status <> 'verified'),
                  'only verified activities');
select pg_temp.ok(not exists (select 1 from realisasi.kpi_items('2025-08-01', '2027-07-31', '2027-07-31', null) where kpi_code = '1.1'
                               and activity_id in (pg_temp.aid(16), pg_temp.aid(29), pg_temp.aid(30))), 'S-16/S-29/S-30 (not verified) excluded');
select pg_temp.ok(not exists (select 1 from realisasi.kpi_items('2025-08-01', '2026-07-31', '2026-08-30', 1) i where i.kpi_code = '1.1' and i.bucket = 'inbound'
                               and split_part(i.ref_id, ':', 2) not like 'X%'), 'inbound counts only inbound section');
select pg_temp.ok(not exists (select 1 from realisasi.kpi_items('2025-08-01', '2026-07-31', '2026-08-30', 1) i where i.kpi_code = '1.1' and i.bucket = 'outbound'
                               and split_part(i.ref_id, ':', 2) like 'X%'), 'outbound counts only internal section');
select pg_temp.ok(not exists (select 1 from realisasi.kpi_items('2025-08-01', '2026-07-31', '2026-08-30', 1) i where i.kpi_code = '1.1' and i.ref_id like '%:PG%'),
                  'staff never counted (R-19)');

-- R-40 per semester; wrapper agrees with kpi_items
select pg_temp.eq((select jsonb_agg(jsonb_build_object('label', s ->> 'label', 'in', s -> 'inbound', 'out', s -> 'outbound'))
                     from jsonb_array_elements(realisasi.compute_kpis('2025-08-01', '2026-07-31', '2026-08-30', 1) #> '{kpi_1_1,by_semester}') s),
  '[{"label":"Ganjil 2025/2026","in":3,"out":4},{"label":"Genap 2025/2026","in":2,"out":12}]'::jsonb, 'R-40 by_semester AY 2025/2026');
select pg_temp.eq((select students from realisasi.kpi_1_1('2026-08-01', '2026-10-01') where direction = 'outbound'), 17::bigint, 'Schema wrapper kpi_1_1');

-- approving S-29 adds inbound students
:as_mob
select realisasi.mobility_approve(pg_temp.aid(29));
reset role;
select pg_temp.eq((realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2) #>> '{kpi_1_1,inbound}')::int, 6, 'S-29 verified adds 2 inbound');

-- kpi_participant_rows (personal data) agree with the 1.1 items
:as_mob
select pg_temp.eq(jsonb_array_length(realisasi.kpi_participant_rows(2, 'ytd')), 23, 'participant rows = 1.1 items (ytd, after S-18/S-29)');
:as_fti
select pg_temp.eq(jsonb_array_length(realisasi.kpi_participant_rows(2, 'ytd', 20)), 12, 'submitter forced to own unit (FTI)');
:as_view
select pg_temp.throws($$select realisasi.kpi_participant_rows(2, 'ytd')$$, 'AUTH_FORBIDDEN', 'viewer: counts only');

-- drill-down rows aggregate per activity without personal data
:as_mob
select pg_temp.eq((select jsonb_agg(r ->> 'code' || ':' || (r ->> 'students')) from jsonb_array_elements(realisasi.kpi_drilldown(2, 'ytd', '1.1', 'outbound') -> 'rows') r),
                  '["RL-2026-0010:2", "RL-2026-0013:12", "RL-2026-0033:3"]'::jsonb, 'drilldown 1.1 rows');
select pg_temp.ok(not (realisasi.kpi_drilldown(2, 'ytd', '1.1')::text like '%B11227366%'), 'drilldown has no NRPs');
rollback;
