-- 61_dup_review: regressions from docs/reviews/database-review.md (L3, L4, L7).
\ir _helpers.inc

-- ---- L3 (R-33): duplicates are rescanned on resubmit --------------------------------------------
-- S-17 (FBE, chain 102, P revision) is revised into a copy of S-15 (same chain, overlapping dates)
:as_fbe
select realisasi.save_activity_draft(pg_temp.aid(17), '{"name":"Student Exchange Semester Genap di Hanyang University","start_date":"2026-02-10","end_date":"2026-02-12"}');
select realisasi.submit_activity(pg_temp.aid(17));
reset role;
select pg_temp.ok(exists (select 1 from realisasi.duplicate_candidates where status = 'open'
                           and least(activity_a, activity_b) = least(pg_temp.aid(15), pg_temp.aid(17))
                           and greatest(activity_a, activity_b) = greatest(pg_temp.aid(15), pg_temp.aid(17))), 'L3 resubmit rescans duplicates');

-- ---- L4: event-group edge cases ------------------------------------------------------------------
-- link_duplicates refuses a candidate whose activity was rejected meanwhile
insert into realisasi.duplicate_candidates (activity_a, activity_b, score)
values (least(pg_temp.aid(18), pg_temp.aid(10)), greatest(pg_temp.aid(18), pg_temp.aid(10)), 0.6);
:as_part
select pg_temp.throws(format('select realisasi.link_duplicates(%s)', (select id from realisasi.duplicate_candidates
                       where least(activity_a, activity_b) = least(pg_temp.aid(18), pg_temp.aid(10)) and greatest(activity_a, activity_b) = greatest(pg_temp.aid(18), pg_temp.aid(10)))),
                      'STATE_INVALID', 'L4 cannot link a rejected activity');
reset role;

-- unlinking the middle member of A-B-C splits the group into connected components
savepoint mid;
:as_part
select realisasi.link_activities(pg_temp.aid(14), pg_temp.aid(10), 'rantai');   -- 13-14 (seed) + 14-10
:as_admin
select realisasi.unlink_activity(pg_temp.aid(14), 'salah tautan');
reset role;
select pg_temp.ok((select count(distinct event_group_id) from realisasi.activities where id in (pg_temp.aid(13), pg_temp.aid(14), pg_temp.aid(10))) = 3,
                  'L4 unlinking the middle member leaves no unconnected pair in one group');
rollback to savepoint mid;

-- an open candidate whose pair ends up in one group is resolved automatically
insert into realisasi.duplicate_candidates (activity_a, activity_b, score)
values (least(pg_temp.aid(13), pg_temp.aid(10)), greatest(pg_temp.aid(13), pg_temp.aid(10)), 0.5);
:as_part
select realisasi.link_activities(pg_temp.aid(14), pg_temp.aid(10), 'rantai');
reset role;
select pg_temp.eq((select status::text from realisasi.duplicate_candidates where least(activity_a, activity_b) = least(pg_temp.aid(13), pg_temp.aid(10))
                     and greatest(activity_a, activity_b) = greatest(pg_temp.aid(13), pg_temp.aid(10))), 'linked', 'L4 open candidate in one group auto-resolved');

-- ---- L7: _merge_groups locks rows in a deterministic order ------------------------------------------
select pg_temp.ok(pg_get_functiondef('realisasi._merge_groups(uuid,uuid,text)'::regprocedure) ~* 'order by id for update', 'L7 merge locks both rows ordered by id');
rollback;
