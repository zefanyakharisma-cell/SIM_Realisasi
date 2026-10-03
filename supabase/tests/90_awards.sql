-- 90_awards: International Awards dashboard tab (Revisi V.1): four leaderboards per Program Studi.
\ir _helpers.inc

:as_view
create temp table _aw as select realisasi.international_awards(2, 'ytd') as v;
select pg_temp.eq((select v #>> '{period,label}' from _aw), 'YTD 2026/2027', 'awards follow the period context');
-- Outbound internasional, by each student's own prodi: FTI short program S-13 (12 students minus the 2 still open with
-- S-18) = 6 Informatika + 4 Teknik Elektro; FBE exchange S-10 (2) = Manajemen students
select pg_temp.eq((select v -> 'outbound_international' from _aw),
  '[{"jd_dd":0,"total":6,"unit_id":11,"unit_name":"Prodi Informatika","short_summer":6,"student_exchange":0,"short_international":0},
    {"jd_dd":0,"total":4,"unit_id":12,"unit_name":"Prodi Teknik Elektro","short_summer":4,"student_exchange":0,"short_international":0},
    {"jd_dd":0,"total":2,"unit_id":21,"unit_name":"Prodi Manajemen","short_summer":0,"student_exchange":2,"short_international":0}]'::jsonb,
  'outbound internasional board by student prodi, ranked by total');
-- only Program Studi units are ranked (never a Fakultas, Program or UP)
select pg_temp.ok((select bool_and(u.kind = 'prodi')
                     from _aw, jsonb_array_elements((v -> 'inbound') || (v -> 'outbound_domestic') || (v -> 'outbound_international')
                                                    || (v -> 'initiatives')) r
                     join kerjasama.units u on u.id = (r ->> 'unit_id')::int), 'only prodi rows');
-- Outbound dalam negeri: DKV Studi Ekskursi to Bali, 5 days -> "<14 hari" column
select pg_temp.eq((select v -> 'outbound_domestic' from _aw),
  '[{"jd_dd":0,"total":3,"unit_id":31,"unit_name":"Prodi Desain Komunikasi Visual","short_summer":0,"student_exchange":0,"short_international":3}]'::jsonb,
  'outbound dalam negeri board (<14 hari)');
-- inbound exchange students have no PETRA prodi ("Program Pertukaran"); S-11 was submitted by a Fakultas -> not ranked
select pg_temp.eq((select v -> 'inbound' from _aw), '[]'::jsonb, 'inbound: no prodi host -> not counted');
-- Inisiatif internasional: activities with a foreign partner or held abroad, by submitting PRODI (FBE's 3 are not ranked)
select pg_temp.eq((select i from _aw, jsonb_array_elements(v -> 'initiatives') i where (i ->> 'unit_id')::int = 11),
  '{"total":1,"inbound":0,"unit_id":11,"outbound":1,"unit_name":"Prodi Informatika","activities":0}'::jsonb, 'initiatives row Informatika');
select pg_temp.ok(not exists (select 1 from _aw, jsonb_array_elements(v -> 'initiatives') i where (i ->> 'unit_id')::int = 20),
                  'faculty-submitted initiatives not ranked');
select pg_temp.ok((select bool_and((i ->> 'total')::int = (i ->> 'inbound')::int + (i ->> 'outbound')::int + (i ->> 'activities')::int)
                     from _aw, jsonb_array_elements(v -> 'initiatives') i), 'initiatives total = inbound + outbound + kegiatan');
select pg_temp.ok((select bool_and((r ->> 'total')::int = (r ->> 'jd_dd')::int + (r ->> 'student_exchange')::int + (r ->> 'short_summer')::int
                                    + (r ->> 'short_international')::int)
                     from _aw, jsonb_array_elements((v -> 'inbound') || (v -> 'outbound_domestic') || (v -> 'outbound_international')) r),
                  'student totals = sum of the four columns');
-- JD/DD column (AY 2025/2026, whole year): S-34 double degree (Manajemen students)
select pg_temp.eq((select r ->> 'jd_dd' from jsonb_array_elements(realisasi.international_awards(1, 'full') -> 'outbound_international') r
                    where (r ->> 'unit_id')::int = 21), '2', 'JD/DD column (Prodi Manajemen, S-34)');
-- Genap only vs Ganjil only
select pg_temp.ok(not exists (select 1 from jsonb_array_elements(realisasi.international_awards(1, 'ganjil') -> 'outbound_international') r
                               where (r ->> 'jd_dd')::int > 0), 'Ganjil only: no S-34');
-- a co-unit prodi does not get the students (they go to their own prodi)
reset role;
insert into realisasi.activity_units values (pg_temp.aid(10), 31, false);
:as_view
select pg_temp.ok(not exists (select 1 from jsonb_array_elements(realisasi.international_awards(2, 'ytd') -> 'outbound_international') r
                               where (r ->> 'unit_id')::int = 31), 'co-unit not credited');
-- a Fakultas scope shows the prodis of that faculty
select pg_temp.eq((select jsonb_agg(r ->> 'unit_id' order by r ->> 'unit_id')
                     from jsonb_array_elements(realisasi.international_awards(2, 'ytd', 10) -> 'outbound_international') r),
                  '["11", "12"]'::jsonb, 'faculty scope = its prodis');
-- conflict decisions apply
:as_mob
select realisasi.resolve_conflict(id, pg_temp.aid(13)) from realisasi.participant_conflicts where status = 'open';
select pg_temp.eq((select sum((r ->> 'short_summer')::int)::int from jsonb_array_elements(realisasi.international_awards(2, 'ytd') -> 'outbound_international') r
                     where (r ->> 'unit_id')::int in (11, 12)), 12, 'resolved conflicts move students back to S-13');
-- submitters see their own unit only (Rules §10 dashboard scope): a faculty submitter sees its prodis
:as_fbe
select pg_temp.eq((select jsonb_agg(distinct r ->> 'unit_id') from jsonb_array_elements(realisasi.international_awards(2, 'ytd', 10) -> 'outbound_international') r),
                  '["21"]'::jsonb, 'submitter scope forced to own unit');
select pg_temp.throws($$select realisasi.international_awards(2, 'live')$$, 'VALIDATION_INVALID', 'period validated');
rollback;
