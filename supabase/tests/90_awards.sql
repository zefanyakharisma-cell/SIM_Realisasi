-- 90_awards: International Awards dashboard tab (Revisi V.1): four leaderboards per submitting unit.
\ir _helpers.inc

:as_view
create temp table _aw as select realisasi.international_awards(2, 'ytd') as v;
select pg_temp.eq((select v #>> '{period,label}' from _aw), 'YTD 2026/2027', 'awards follow the period context');
-- Outbound internasional: FTI short program S-13 (12 students minus the 2 still open with S-18), FBE exchange S-10 (2)
select pg_temp.eq((select v -> 'outbound_international' from _aw),
  '[{"jd_dd":0,"total":10,"unit_id":10,"unit_name":"Fakultas Teknologi Industri","short_summer":10,"student_exchange":0,"short_international":0},
    {"jd_dd":0,"total":2,"unit_id":20,"unit_name":"Fakultas Bisnis & Ekonomi","short_summer":0,"student_exchange":2,"short_international":0}]'::jsonb,
  'outbound internasional board ranked by total');
-- Outbound dalam negeri: DKV Studi Ekskursi to Bali, 5 days -> "<14 hari" column
select pg_temp.eq((select v -> 'outbound_domestic' from _aw),
  '[{"jd_dd":0,"total":3,"unit_id":31,"unit_name":"Prodi Desain Komunikasi Visual","short_summer":0,"student_exchange":0,"short_international":3}]'::jsonb,
  'outbound dalam negeri board (<14 hari)');
select pg_temp.eq((select v -> 'inbound' -> 0 ->> 'student_exchange' from _aw), '4', 'inbound board: FSD exchange (S-11)');
-- Inisiatif internasional: activities with a foreign partner or held abroad, by submitting unit
select pg_temp.eq((select i from _aw, jsonb_array_elements(v -> 'initiatives') i where (i ->> 'unit_id')::int = 20),
  '{"total":3,"inbound":0,"unit_id":20,"outbound":1,"unit_name":"Fakultas Bisnis & Ekonomi","activities":2}'::jsonb, 'initiatives row FBE');
select pg_temp.ok((select bool_and((i ->> 'total')::int = (i ->> 'inbound')::int + (i ->> 'outbound')::int + (i ->> 'activities')::int)
                     from _aw, jsonb_array_elements(v -> 'initiatives') i), 'initiatives total = inbound + outbound + kegiatan');
select pg_temp.ok((select bool_and((r ->> 'total')::int = (r ->> 'jd_dd')::int + (r ->> 'student_exchange')::int + (r ->> 'short_summer')::int
                                    + (r ->> 'short_international')::int)
                     from _aw, jsonb_array_elements((v -> 'inbound') || (v -> 'outbound_domestic') || (v -> 'outbound_international')) r),
                  'student totals = sum of the four columns');
-- JD/DD column (AY 2025/2026, whole year): S-34 double degree
select pg_temp.eq((select r ->> 'jd_dd' from jsonb_array_elements(realisasi.international_awards(1, 'full') -> 'outbound_international') r
                    where (r ->> 'unit_id')::int = 21), '2', 'JD/DD column (Prodi Manajemen, S-34)');
-- Genap only vs Ganjil only
select pg_temp.ok(not exists (select 1 from jsonb_array_elements(realisasi.international_awards(1, 'ganjil') -> 'outbound_international') r
                               where (r ->> 'unit_id')::int = 21), 'Ganjil only: no S-34');
-- grouped by the SUBMITTING unit only (a co-unit does not get the students)
reset role;
insert into realisasi.activity_units values (pg_temp.aid(10), 31, false);
:as_view
select pg_temp.ok(not exists (select 1 from jsonb_array_elements(realisasi.international_awards(2, 'ytd') -> 'outbound_international') r
                               where (r ->> 'unit_id')::int = 31), 'co-unit not credited');
-- conflict decisions apply
:as_mob
select realisasi.resolve_conflict(id, pg_temp.aid(13)) from realisasi.participant_conflicts where status = 'open';
select pg_temp.eq((realisasi.international_awards(2, 'ytd') #>> '{outbound_international,0,short_summer}')::int, 12, 'resolved conflicts move students back to FTI');
-- submitters see their own unit only (Rules §10 dashboard scope)
:as_fbe
select pg_temp.eq((select jsonb_agg(distinct r ->> 'unit_id') from jsonb_array_elements(realisasi.international_awards(2, 'ytd') -> 'initiatives') r),
                  '["20"]'::jsonb, 'submitter scope forced to own unit');
select pg_temp.throws($$select realisasi.international_awards(2, 'live')$$, 'VALIDATION_INVALID', 'period validated');
rollback;
