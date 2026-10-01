-- 21_kpi_1_19_24: AT-05 grace, AT-06 auto-renewed, AT-07 renewal chain, R-42..R-47.
\ir _helpers.inc

create function pg_temp.has(p_from date, p_to date, p_cutoff date, p_bucket text, p_chain int, p_as_of timestamptz default null) returns boolean
language sql as $$ select exists (select 1 from realisasi.kpi_items(p_from, p_to, p_cutoff, null, p_as_of) where kpi_code = '1.19.24' and bucket = p_bucket and ref_id = p_chain::text) $$;

-- AT-05: doc 902 (start 2026-12-02) in Ganjil 2026/2027 (cutoff 2027-03-02) -> grace-excluded, listed, not in denominator
select pg_temp.ok(pg_temp.has('2026-08-01', '2027-01-31', '2027-03-02', 'grace_excluded', 902), 'AT-05 902 grace_excluded (Ganjil 26/27)');
select pg_temp.ok(not pg_temp.has('2026-08-01', '2027-01-31', '2027-03-02', 'denominator', 902), 'AT-05 902 not in denominator');
select pg_temp.ok(not pg_temp.has('2026-08-01', '2027-01-31', '2027-03-02', 'grace_excluded', 901), '901 (2026-06-15) past grace at Ganjil cutoff');
select pg_temp.ok(pg_temp.has('2026-08-01', '2027-01-31', '2027-03-02', 'denominator', 901), '901 in Ganjil denominator');
-- Live (cutoff = today 2026-10-01): 901 inside grace; 902 not yet active
select pg_temp.ok(pg_temp.has('2026-08-01', '2026-10-01', '2026-10-01', 'grace_excluded', 901), 'AT-05 Live: 901 grace_excluded');
select pg_temp.ok(not pg_temp.has('2026-08-01', '2026-10-01', '2026-10-01', 'denominator', 902) and not pg_temp.has('2026-08-01', '2026-10-01', '2026-10-01', 'grace_excluded', 902),
                  '902 not active yet in Live');
select pg_temp.ok((select (r ->> 'grace_until')::date = '2026-12-15' from jsonb_array_elements(
                    (select realisasi.kpi_drilldown(2, 'live', '1.19.24', 'grace_excluded') from (select set_config('request.jwt.claims', json_build_object('sub', :'ADMIN')::text, true)) x) -> 'rows') r
                   where (r ->> 'chain_id')::int = 901), 'R-47 grace-excluded listed with grace_until');

-- AT-06: auto-renewed 903 without activity: in denominator, never numerator (Live and both 2025/2026 snapshots)
select pg_temp.ok(pg_temp.has('2026-08-01', '2026-10-01', '2026-10-01', 'denominator', 903) and not pg_temp.has('2026-08-01', '2026-10-01', '2026-10-01', 'numerator', 903),
                  'AT-06 Live: 903 denominator only');
select pg_temp.ok(exists (select 1 from realisasi.kpi_snapshot_items i join realisasi.kpi_snapshots s on s.id = i.snapshot_id
                           where s.kind = k and s.academic_year_id = 1 and i.kpi_code = '1.19.24' and i.bucket = 'denominator' and i.ref_id = '903')
              and not exists (select 1 from realisasi.kpi_snapshot_items i join realisasi.kpi_snapshots s on s.id = i.snapshot_id
                           where s.kind = k and s.academic_year_id = 1 and i.kpi_code = '1.19.24' and i.bucket = 'numerator' and i.ref_id = '903'),
                  'AT-06 snapshot ' || k || ': 903 denominator only')
  from unnest(array['ganjil_ytd','genap_full_year']::realisasi.snapshot_kind[]) k;
select pg_temp.ok(not pg_temp.has('2026-08-01', '2026-10-01', '2026-10-01', 'grace_excluded', 903), 'R-43 auto-renewed never grace-excluded');

-- AT-07: S-20 (doc 904) + S-20b (doc 905, renewal): chain 904 once in denominator and once in numerator
select pg_temp.eq((select count(*) from realisasi.kpi_items('2025-08-01', '2026-07-31', '2026-08-30', 1) where kpi_code = '1.19.24' and bucket = 'denominator' and ref_id = '904'),
                  1::bigint, 'AT-07 chain 904 once in denominator');
select pg_temp.eq((select count(*) from realisasi.kpi_items('2025-08-01', '2026-07-31', '2026-08-30', 1) where kpi_code = '1.19.24' and bucket = 'numerator' and ref_id = '904'),
                  1::bigint, 'AT-07 chain 904 once in numerator');
select pg_temp.ok(not exists (select 1 from realisasi.kpi_items('2025-08-01', '2026-07-31', '2026-08-30', 1) where kpi_code = '1.19.24' and ref_id = '905'), 'no separate chain for 905');
select pg_temp.eq((select string_agg(original_doc_number || '>' || current_doc_number || '@' || chain_id, ',' order by original_document_id)
                     from realisasi.v_activity_documents where activity_id in (pg_temp.aid(20), pg_temp.aid(32))),
                  '018/MoU/PCU-OU/IX/2023>015/MoU/PCU-OU/IV/2026@904,015/MoU/PCU-OU/IV/2026>015/MoU/PCU-OU/IV/2026@904', 'AT-07 original vs current doc numbers');
select pg_temp.eq((select doc_numbers from realisasi.v_chains where chain_id = 904), array['018/MoU/PCU-OU/IX/2023','015/MoU/PCU-OU/IV/2026'], 'v_chains ordered docs');
select pg_temp.eq((select current_document_id || '/' || chain_start || '/' || chain_end from realisasi.v_chains where chain_id = 904), '905/2023-09-01/2031-03-31', 'v_chains window');

-- R-44: numerator needs a verified activity dated between AY start and cutoff; R-45 MoA under MoU does not realize the MoU
select pg_temp.ok(pg_temp.has('2026-08-01', '2026-10-01', '2026-10-01', 'numerator', 117) and not pg_temp.has('2026-08-01', '2026-10-01', '2026-10-01', 'numerator', 116),
                  'R-45 activity on MoA 117 realizes chain 117 only, not parent MoU 116');
select pg_temp.ok(pg_temp.has('2026-08-01', '2026-10-01', '2026-10-01', 'denominator', 116), 'MoU 116 still counted in denominator');
select pg_temp.ok(not pg_temp.has('2026-08-01', '2026-10-01', '2026-10-01', 'numerator', 112), 'pending S-25 does not realize 112');
select pg_temp.ok(not pg_temp.has('2025-08-01', '2026-01-31', '2026-03-02', 'numerator', 106, '2026-03-02 01:00+07'),
                  'as_of: S-19 (verified 2026-04-15) does not realize 106 at the Ganjil freeze');
select pg_temp.ok(not pg_temp.has('2025-08-01', '2026-07-31', '2026-08-30', 'denominator', 118) and not pg_temp.has('2025-08-01', '2026-07-31', '2026-08-30', 'denominator', 119),
                  'expired / terminated chains inactive');
select pg_temp.ok(not exists (select 1 from realisasi.kpi_items('2025-08-01', '2027-07-31', '2027-07-31', null) where kpi_code = '1.19.24' and ref_id in ('906','907')),
                  'in_process / rejected documents never counted');

-- R-46 scopes: all = international + domestic
select pg_temp.ok((v #>> '{kpi_1_19_24,all,numerator}')::int = (v #>> '{kpi_1_19_24,international,numerator}')::int + (v #>> '{kpi_1_19_24,domestic,numerator}')::int
              and (v #>> '{kpi_1_19_24,all,denominator}')::int = (v #>> '{kpi_1_19_24,international,denominator}')::int + (v #>> '{kpi_1_19_24,domestic,denominator}')::int,
                  'R-46 all = international + domestic')
  from (select realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2) v) x;
select pg_temp.eq(realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2) #> '{kpi_1_19_24,all}',
                  '{"numerator": 6, "denominator": 19, "grace_excluded": 1, "pct": 31.6}'::jsonb, 'Live 2026/2027 KPI 1.19.24 all');
select pg_temp.eq((select v_chains.is_international from realisasi.v_chains where chain_id = 903), false, '903 domestic chain');
select pg_temp.eq((select numerator || '/' || denominator || '/' || grace_excluded from realisasi.kpi_1_19_24('2026-08-01', '2026-10-01', 6) where scope = 'all'),
                  '6/19/1', 'Schema wrapper kpi_1_19_24 agrees');
select pg_temp.eq((select grace_excluded from realisasi.kpi_1_19_24('2026-08-01', '2026-10-01', 0) where scope = 'all'), 0::bigint, 'wrapper honours p_grace_months');

-- unit scope: chains with a document scoped to the unit
select pg_temp.eq((realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2, null, 10) #> '{kpi_1_19_24,all}') - 'pct',
                  '{"numerator": 2, "denominator": 6, "grace_excluded": 1}'::jsonb, 'FTI unit KPI 1.19.24');

-- agreement read models
:as_view
select pg_temp.eq((realisasi.agreement_realization(905) #>> '{chain,chain_id}')::int, 904, 'agreement_realization resolves chain');
select pg_temp.eq((select jsonb_agg(a ->> 'original_doc_number' order by a ->> 'start_date') from jsonb_array_elements(realisasi.agreement_realization(905) -> 'activities') a),
                  '["018/MoU/PCU-OU/IX/2023", "015/MoU/PCU-OU/IV/2026"]'::jsonb, 'AT-07 realization tab shows both original docs');
select pg_temp.eq(realisasi.agreement_realization(905) #>> '{summary,last_activity_date}', '2026-05-11', 'last activity date');
select pg_temp.eq((select f ->> 'flag' from jsonb_array_elements(realisasi.agreement_flags(2)) f where (f ->> 'document_id')::int = 901), 'grace', 'flag grace 901');
select pg_temp.eq((select f ->> 'flag' from jsonb_array_elements(realisasi.agreement_flags(2)) f where (f ->> 'document_id')::int = 905), 'not_realized', 'flag 905 (no AY2 activity)');
select pg_temp.eq((select f ->> 'flag' from jsonb_array_elements(realisasi.agreement_flags(1)) f where (f ->> 'document_id')::int = 904), 'realized', 'flag 904 in AY1');
select pg_temp.eq((select f ->> 'flag' from jsonb_array_elements(realisasi.agreement_flags(2)) f where (f ->> 'document_id')::int = 906), 'inactive', 'flag in_process inactive');
select pg_temp.eq((select f ->> 'flag' from jsonb_array_elements(realisasi.agreement_flags(2)) f where (f ->> 'document_id')::int = 113), 'realized', 'flag 113 realized');
rollback;
