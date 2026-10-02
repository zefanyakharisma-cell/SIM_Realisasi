-- 31_snapshots_review: regressions from docs/reviews/database-review.md (M3, M4, M5).
\ir _helpers.inc

-- ---- requirements-review L-6: one "Snapshot dibekukan" per seeded snapshot, dated at its frozen_at -------
select pg_temp.eq((select count(*) from realisasi.notifications where recipient_id = :'VIEW' and kind = 'snapshot_frozen'), 2::bigint,
                  'L-6 viewer has one notification per seeded snapshot');
select pg_temp.ok((select bool_and(n.created_at = k.frozen_at) from realisasi.notifications n
                     join realisasi.kpi_snapshots k on n.link = '/realisasi/laporan?report=arsip&snapshot=' || k.id
                    where n.kind = 'snapshot_frozen'), 'L-6 seeded snapshot notifications dated at frozen_at');

-- ---- M4: freeze_snapshot ignores caller-supplied as_of/actor for users -------------------------
:as_admin
select pg_temp.throws($$select realisasi.freeze_snapshot(2, 'ganjil_ytd', '2027-03-02 01:00+07', '00000000-0000-4000-8000-000000000003')$$,
                      'R55_BEFORE_CUTOFF', 'M4 users cannot freeze before the cutoff');
create temp table _ay0 as select realisasi.upsert_academic_year(null, '2024/2025', '2024-08-01', '2025-07-31') as id;
grant select on _ay0 to authenticated;
create temp table _m4 as select realisasi.freeze_snapshot((select id from _ay0), 'ganjil_ytd', '2030-01-01 00:00+07', '00000000-0000-4000-8000-000000000003') as id;
reset role;
select pg_temp.ok((select frozen_at = realisasi.now_ts() and frozen_by = :'ADMIN'::uuid from realisasi.kpi_snapshots where id = (select id from _m4)),
                  'M4 user freeze: as_of = now_ts(), actor = caller');
-- an authenticated connection with empty claims is not the system caller
set local role authenticated;
select set_config('request.jwt.claims', '', true);
select pg_temp.throws($$select realisasi.freeze_snapshot((select id from _ay0), 'genap_full_year')$$, 'AUTH_REQUIRED', 'M4 empty claims as authenticated: no system freeze');
select pg_temp.throws($$select realisasi.run_daily_jobs()$$, 'AUTH_REQUIRED', 'M4 empty claims as authenticated: no system job run');
reset role;

-- ---- M3: previous snapshot P is the preceding period, not the latest frozen_at --------------------
-- S-08 (Genap 2025/2026) is verified late, on 2026-10-15
alter table realisasi.activities disable trigger trg_activities_status;
update realisasi.activities set verified_at = '2026-10-15 10:00+07' where id = pg_temp.aid(8);
alter table realisasi.activities enable trigger trg_activities_status;
-- Ganjil 2025/2026 is re-frozen first (frozen_at = now = 2026-10-01)
:as_admin
select realisasi.refreeze_snapshot((select id from realisasi.kpi_snapshots where academic_year_id = 1 and kind = 'ganjil_ytd' and superseded_by is null), 'Koreksi');
:as_system
create temp table _m3 as select realisasi.freeze_snapshot(2, 'ganjil_ytd', '2027-03-02 01:00+07') as id;
select pg_temp.eq((select jsonb_agg(jsonb_build_object('code', r ->> 'code', 'counted', r -> 'counted_in_this_snapshot', 'prev', r ->> 'previous_snapshot_label'))
                     from jsonb_array_elements(realisasi._snapshot_late_additions((select id from _m3))) r),
                  '[{"code":"RL-2026-0008","counted":false,"prev":"Setahun 2025/2026"}]'::jsonb,
                  'M3 late Genap activity listed in next Ganjil report despite a re-freeze of an older period');

-- ---- M5 (R-31): a conflict decision on verified activities in a frozen window is a post-freeze change --------
insert into realisasi.participant_conflicts (nrp, activity_a, activity_b)
values ('D31240187', least(pg_temp.aid(3), pg_temp.aid(15)), greatest(pg_temp.aid(3), pg_temp.aid(15)));
:as_mob
select realisasi.resolve_conflict((select id from realisasi.participant_conflicts where nrp = 'D31240187'), pg_temp.aid(15), 'acara yang sama');
reset role;
select pg_temp.eq((select count(*) from realisasi.activity_log where action = 'resolve_conflict' and in_frozen_period
                     and activity_id in (pg_temp.aid(3), pg_temp.aid(15))), 2::bigint, 'M5 conflict decision logs flagged in_frozen_period');
rollback;
