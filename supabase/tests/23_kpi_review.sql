-- 23_kpi_review: regressions from docs/reviews/database-review.md (H1, H2, H3, M2, L8, L9/R-52).
\ir _helpers.inc

-- ---- H1 (R-38/R-39): a unit on two linked activities counts the event once --------------------
create temp table _h1 as
select realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2, null, 10) as fti,
       realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2) as univ;
-- FTI becomes co-unit of S-14, which is linked with FTI's own S-13 (same 12 students)
insert into realisasi.activity_units values (pg_temp.aid(14), 10, false);
select pg_temp.eq((realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2, null, 10) #>> '{kpi_1_1,outbound}')::int, 12,
                  'H1 FTI outbound stays 12 when FTI is on both linked activities');
select pg_temp.eq(realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2, null, 10) -> 'kpi_1_19_s1', (select fti -> 'kpi_1_19_s1' from _h1),
                  'H1 FTI S1 unchanged (one event group)');
select pg_temp.eq(realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2, null, 10) -> 'kpi_1_19_s8', (select fti -> 'kpi_1_19_s8' from _h1),
                  'H1 FTI S8 unchanged (one event group)');
select pg_temp.eq((select count(*) from realisasi.kpi_items('2026-08-01', '2026-10-01', '2026-10-01', 2, null, 10) where kpi_code = '1.1'), 12::bigint,
                  'H1 kpi_items unit rows = distinct (nrp, event group)');
select pg_temp.eq((realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2, null, 11) #>> '{kpi_1_1,outbound}')::int, 12,
                  'H1 Informatika still counts the event (R-39 both units)');
select pg_temp.eq((select x -> 'kpi_1_1' ->> 'outbound' from jsonb_array_elements(realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2) -> 'by_unit') x
                    where (x ->> 'unit_id')::int = 10), '12', 'H1 by_unit FTI = 12');
select pg_temp.eq((realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2) -> 'kpi_1_1') - 'by_semester', (select (univ -> 'kpi_1_1') - 'by_semester' from _h1),
                  'H1 university unchanged');
delete from realisasi.activity_units where activity_id = pg_temp.aid(14) and unit_id = 10;

-- ---- H2 (R-04/R-43): terminated or replaced auto-renewed agreements stop being active -----------
savepoint h2;
select pg_temp.ok(exists (select 1 from realisasi.kpi_items('2026-08-01', '2026-10-01', '2026-10-01', 2) where kpi_code = '1.19.24' and ref_id = '903'),
                  'H2 precondition: auto-renewed 903 in the denominator');
update public.dokumen_kerja_sama set status = 'Diarsipkan', alasan_arsip = 'expired_without_renewal' where no = 903;
update realisasi.document_overrides set terminated_at = '2024-03-01' where document_id = 903;
select pg_temp.ok(not exists (select 1 from realisasi.kpi_items('2026-08-01', '2026-10-01', '2026-10-01', 2) where kpi_code = '1.19.24' and ref_id = '903'),
                  'H2 terminated auto-renewed chain leaves KPI 1.19.24');
select pg_temp.eq((select chain_end from realisasi.v_chains where chain_id = 903), '2024-03-01'::date, 'H2 chain_end = termination date');
select pg_temp.ok(not exists (select 1 from realisasi.documents_valid_between('2026-09-01', '2026-09-05') where document_id = 903),
                  'H2 terminated auto-renewed doc not selectable after termination');
select pg_temp.ok(exists (select 1 from realisasi.documents_valid_between('2024-02-01', '2024-02-10') where document_id = 903),
                  'H2 still selectable before termination');
rollback to savepoint h2;
-- auto-renewed document replaced by a fixed-term renewal that has expired
select pg_temp.simks_doc(950, 'TEST/MoU/950', 'MoU', 'Diarsipkan', '2022-01-15', '2024-01-14', p_prev_no => 903,
                         p_alasan => 'expired_without_renewal', p_title => 'Renewal of 903');
update public.dokumen_kerja_sama set status = 'Diarsipkan', alasan_arsip = 'superseded_by_renewal' where no = 903;
select pg_temp.ok(not (select auto_renewed from realisasi.v_chains where chain_id = 903), 'H2 chain auto_renewed follows the current document');
select pg_temp.ok(not exists (select 1 from realisasi.kpi_items('2026-08-01', '2026-10-01', '2026-10-01', 2) where kpi_code = '1.19.24' and ref_id = '903'),
                  'H2 expired fixed-term renewal ends the chain');
select pg_temp.ok(not exists (select 1 from realisasi.documents_valid_between('2026-09-01', '2026-09-05') where document_id = 903),
                  'H2 replaced auto-renewed doc not selectable after its successor started');
rollback to savepoint h2;

-- ---- H3 (R-49/R-50): known entries matched to non-qualifying activities stay in the gap --------
select pg_temp.eq((realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2) #>> '{kpi_1_19_s8,unmatched_known}')::int, 2, 'H3 precondition gap = 2');
:as_part
select realisasi.match_known_activity(7, pg_temp.aid(26));      -- S-26 in_verification
reset role;
select pg_temp.eq((realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2) #>> '{kpi_1_19_s8,unmatched_known}')::int, 2,
                  'H3 entry matched to an unverified activity is still a gap');
:as_part
select realisasi.match_known_activity(6, pg_temp.aid(25));      -- S-25 in_verification
select realisasi.partnership_reject(pg_temp.aid(25), 'not_partnership', 'x');
reset role;
select pg_temp.eq((select status::text from realisasi.known_activities where id = 6), 'unmatched', 'H3 reject reverts the match');
select pg_temp.ok(exists (select 1 from realisasi.activity_log where activity_id = pg_temp.aid(25) and action = 'unmatch_known'), 'H3 revert logged');
select pg_temp.eq(realisasi.compute_kpis('2026-08-01', '2026-10-01', '2026-10-01', 2) -> 'kpi_1_19_s8', '{"reported": 4, "unmatched_known": 2, "pct": 66.7}'::jsonb,
                  'H3 S8 unchanged by the rejected duplicate');
select pg_temp.eq((select count(*) from realisasi.kpi_items('2026-08-01', '2026-10-01', '2026-10-01', 2, null, 30) where kpi_code = '1.19.S8' and bucket = 'unmatched_known'),
                  1::bigint, 'H3 unit FSD keeps known #7 in its gap');

-- ---- M2 (R-56/R-59): frozen participant exports do not drift after post-freeze edits -------------
:as_mob
select pg_temp.eq(jsonb_array_length(realisasi.kpi_participant_rows(1, 'full')), 19, 'M2 precondition Genap 25/26 export rows = 19');
create temp table _m2 as
select s.nrp from realisasi.participant_students s join realisasi.participant_set_versions v on v.id = s.set_version_id
 where v.activity_id = pg_temp.aid(15) and v.status = 'approved' order by s.nrp limit 2;
grant select on _m2 to authenticated;
select realisasi.ensure_participant_draft(pg_temp.aid(15));
select realisasi.save_participants(pg_temp.aid(15),
  (select jsonb_agg(jsonb_build_object('section', s.section, 'nrp', s.nrp)) from realisasi.participant_students s
     join realisasi.participant_set_versions v on v.id = s.set_version_id
    where v.activity_id = pg_temp.aid(15) and v.status = 'approved' and s.nrp not in (select nrp from _m2)), '[]');
select realisasi.commit_participant_edit(pg_temp.aid(15), 'hapus dua mahasiswa');
select pg_temp.eq(jsonb_array_length(realisasi.kpi_participant_rows(1, 'full')), 19, 'M2 frozen export still 19 rows after the edit');
select pg_temp.ok((select count(*) from jsonb_array_elements(realisasi.kpi_participant_rows(1, 'full')) r
                    where (r ->> 'activity_id')::uuid = pg_temp.aid(15) and r ->> 'nrp' in (select nrp from _m2)) = 2,
                  'M2 removed students still in the frozen export');
select pg_temp.eq((select sum((r ->> 'students')::int) from jsonb_array_elements(realisasi.kpi_drilldown(1, 'full', '1.1', null, 20) -> 'rows') r)::int,
                  (select (x #>> '{kpi_1_1,total}')::int from jsonb_array_elements((select values -> 'by_unit' from realisasi.kpi_snapshots
                     where academic_year_id = 1 and kind = 'genap_full_year' and superseded_by is null)) x where (x ->> 'unit_id')::int = 20),
                  'M2 frozen unit drill-down = frozen unit value');
reset role;
select pg_temp.eq((realisasi.compute_kpis('2025-08-01', '2026-07-31', '2026-08-30', 1) #>> '{kpi_1_1,total}')::int, 17, 'M2 live view reflects the edit');

-- ---- L8: changing reporting_deadline_days recomputes drafts' deadlines -------------------------
:as_admin
select realisasi.update_settings('{"reporting_deadline_days": 45}');
reset role;
select pg_temp.eq(reporting_deadline, end_date + 45, 'L8 draft deadline follows the setting') from realisasi.activities where id = pg_temp.aid(23);
select pg_temp.ok(reporting_deadline = end_date + 30, 'L8 submitted activity keeps its deadline') from realisasi.activities where id = pg_temp.aid(13);
-- L8: a root document that later gets a predecessor; the daily job refreshes stored chain ids
select pg_temp.simks_doc(951, 'TEST/MoU/951', 'MoU', 'Diarsipkan', '2018-01-01', '2022-02-28',
                         p_alasan => 'superseded_by_renewal', p_title => 'Older root');
select pg_temp.simks_set_prev(101, 951);
:as_system
select realisasi.run_daily_jobs();
select pg_temp.ok(not exists (select 1 from realisasi.activity_documents where original_document_id = 101 and chain_id <> 951), 'L8 job refreshes activity_documents.chain_id');
select pg_temp.ok(exists (select 1 from realisasi.kpi_items('2025-08-01', '2026-07-31', '2026-08-30', 1) where kpi_code = '1.19.24' and bucket = 'numerator' and ref_id = '951'),
                  'L8 numerator follows the new chain root');

-- ---- L9 R-52: match suggestions look at the whole activity span ---------------------------------
:as_part
create temp table _l9 as select realisasi.create_known_activity('{"title":"Summer Program Smart Manufacturing Nanyang","activity_date":"2026-08-19","unit_id":10,"is_international":true,"source":"email"}') as id;
select pg_temp.ok(exists (select 1 from jsonb_array_elements(realisasi.known_match_suggestions((select id from _l9))) s where s ->> 'code' = 'RL-2026-0013'),
                  'L9 multi-week S-13 suggested for a date inside its span');
rollback;
