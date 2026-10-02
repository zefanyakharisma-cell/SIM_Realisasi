-- 41_access_review: regressions from docs/reviews/database-review.md (H5, M6, M7, M8, M9, L5), re-cut for Revisi V.1.
\ir _helpers.inc

-- ---- H5 (R-30/R-31/R-64): registered blobs are immutable ------------------------------------------
create temp table _h5 as select storage_path as p, (select md5(data) from realisasi.file_blobs b where b.path = f.storage_path) as md5
  from realisasi.activity_files f where activity_id = pg_temp.aid(5) and kind = 'ia' and is_current;
grant select on _h5 to authenticated;
:as_part
select pg_temp.throws(format('select realisasi.storage_put(%L, %L, convert_to(%L, %L))', (select p from _h5), 'application/pdf', '%PDF-1.4 SILENTLY REPLACED', 'UTF8'),
                      'FILE_FORBIDDEN', 'H5 cannot overwrite a registered IA of a verified activity');
reset role;
select pg_temp.eq((select md5(data) from realisasi.file_blobs where path = (select p from _h5)), (select md5 from _h5), 'H5 bytes unchanged');
-- an unregistered upload of the caller's own may still be retried (same path); verified files are io_admin's (R-29)
:as_fbe
select pg_temp.throws(format('select realisasi.storage_put(%L, %L, convert_to(%L, %L))', 'realisasi-files/' || pg_temp.aid(17) || '/evidence/x.pdf',
                      'application/pdf', '%PDF-1.4 x', 'UTF8'), 'FILE_FORBIDDEN', 'unit cannot add files to a verified activity');
:as_admin
select realisasi.storage_put('realisasi-files/' || pg_temp.aid(17) || '/evidence/retry.pdf', 'application/pdf', convert_to('%PDF-1.4 a', 'UTF8'));
select realisasi.storage_put('realisasi-files/' || pg_temp.aid(17) || '/evidence/retry.pdf', 'application/pdf', convert_to('%PDF-1.4 b', 'UTF8'));
select realisasi.register_activity_file(pg_temp.aid(17), 'evidence', 'realisasi-files/' || pg_temp.aid(17) || '/evidence/retry.pdf', 'retry.pdf', null, null);
select pg_temp.throws(format('select realisasi.storage_put(%L, %L, convert_to(%L, %L))', 'realisasi-files/' || pg_temp.aid(17) || '/evidence/retry.pdf',
                      'application/pdf', '%PDF-1.4 c', 'UTF8'), 'FILE_FORBIDDEN', 'H5 once registered the path is immutable');

-- ---- M8 (R-13): register_activity_file uses the stored blob's type and size ------------------------
select realisasi.storage_put('realisasi-files/' || pg_temp.aid(17) || '/ia/x.png', 'image/png', '\x89504e470d0a1a0a0000'::bytea);
select pg_temp.throws(format('select realisasi.register_activity_file(%L, %L, %L, %L, %s, %L)', pg_temp.aid(17), 'ia',
                      'realisasi-files/' || pg_temp.aid(17) || '/ia/x.png', 'x.pdf', 10, 'application/pdf'), 'R13_FILE_TYPE', 'M8 PNG cannot be registered as IA');
select realisasi.storage_put('realisasi-files/' || pg_temp.aid(17) || '/evidence/foto.png', 'image/png', '\x89504e470d0a1a0a0000'::bytea);
select realisasi.register_activity_file(pg_temp.aid(17), 'evidence', 'realisasi-files/' || pg_temp.aid(17) || '/evidence/foto.png', 'foto.png', 999999, 'application/pdf');
reset role;
select pg_temp.eq((select mime || '/' || size_bytes from realisasi.activity_files where storage_path like '%/evidence/foto.png'), 'image/png/10',
                  'M8 registered mime/size come from the blob');

-- ---- M6: counts-only readers (viewers) never get participant identifiers through logs or reports ---------------
:as_mob
select realisasi.ensure_participant_draft(pg_temp.aid(15));
select realisasi.save_participants(pg_temp.aid(15),
  (select jsonb_agg(jsonb_build_object('section', s.section, 'nrp', s.nrp)) from realisasi.participant_students s
     join realisasi.participant_set_versions v on v.id = s.set_version_id
    where v.activity_id = pg_temp.aid(15) and v.status = 'approved' and s.nrp <> 'D31240187'), '[]');
select realisasi.commit_participant_edit(pg_temp.aid(15), 'hapus satu');
select pg_temp.ok(realisasi.activity_detail(pg_temp.aid(15)) -> 'log' @> '[{"action":"edit","track":"mobility"}]'
                  and (realisasi.activity_detail(pg_temp.aid(15)) -> 'log')::text like '%D31240187%', 'M6 mobility still sees identifiers');
:as_view
select pg_temp.ok(not exists (select 1 from realisasi.activity_log where diff::text like '%D31240187%'), 'M6 log table hides identifiers from viewers');
select pg_temp.eq(realisasi.activity_detail(pg_temp.aid(15)) -> 'log', '[]'::jsonb, 'M6 viewer gets no log');
select pg_temp.ok(realisasi.snapshot_post_freeze_changes((select id from realisasi.kpi_snapshots where academic_year_id = 1 and kind = 'genap_full_year'
                  and superseded_by is null))::text not like '%D31240187%', 'M6 post-freeze change report masked for viewers');

-- ---- M7: read RPCs respect activity visibility ------------------------------------------------------
:as_fsd
select pg_temp.ok(not exists (select 1 from jsonb_array_elements(realisasi.agreement_realization(905) -> 'activities') a where a ->> 'code' = 'RL-2026-0032'),
                  'M7 FSD does not see FTI activities on the chain');
select pg_temp.eq((realisasi.agreement_realization(905) #>> '{summary,total_activities}')::int, 2, 'M7 summary counts stay complete');

-- ---- L5: registry lookups only for roles that enter participants -------------------------------------
:as_view
select pg_temp.throws($$select * from realisasi.lookup_students(array['D31240187'])$$, 'AUTH_FORBIDDEN', 'L5 viewer cannot query BAAK');
:as_view
select pg_temp.throws($$select * from realisasi.lookup_employees(array['PG0010'])$$, 'AUTH_FORBIDDEN', 'L5 viewer cannot query HR');
:as_part
select pg_temp.eq((select count(*) from realisasi.lookup_employees(array['PG204517'])), 1::bigint, 'L5 IO staff (mobility team) may query HR');
:as_fti
select pg_temp.eq((select count(*) from realisasi.lookup_students(array['D31240187'])), 1::bigint, 'L5 submitter lookup works');
select pg_temp.throws($$select * from realisasi.lookup_students(array(select 'N' || g from generate_series(1, 501) g))$$, 'VALIDATION_INVALID', 'L5 lookup capped');

-- ---- M9: demo time travel is gated by a deployment flag ---------------------------------------------
reset role;
select pg_temp.ok(realisasi.demo_time_travel_enabled(), 'M9 demo seed enables time travel');
update realisasi.deployment_flags set enabled = false where key = 'demo_time_travel';
update realisasi.settings set value = '"2027-09-01"' where key = 'demo_today';
select pg_temp.eq(realisasi.today(), (now() at time zone 'Asia/Jakarta')::date, 'M9 stale demo_today ignored when the flag is off');
select pg_temp.ok(realisasi.now_ts() = now(), 'M9 now_ts() is real time when the flag is off');
:as_admin
select pg_temp.throws($$select realisasi.update_settings('{"demo_today": "2027-09-01"}')$$, 'SETTINGS_INVALID', 'M9 demo_today cannot be set in production');
select pg_temp.eq(realisasi.update_settings('{"demo_today": null}') -> 'demo_today', 'null'::jsonb, 'M9 clearing demo_today is always allowed');
:as_system
select pg_temp.eq((select count(*) from jsonb_array_elements(realisasi.run_daily_jobs() -> 'frozen')), 0::bigint, 'M9 jobs use the real date');
rollback;
