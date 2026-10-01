-- 60_duplicates_known: R-32..R-35 (duplicates, event groups), R-51..R-54 (Known Activities).
\ir _helpers.inc

create temp table _ids (k text primary key, id uuid);
grant all on _ids to authenticated;
create function pg_temp.id(p_k text) returns uuid language sql as $$ select id from _ids where k = p_k $$;
grant execute on all functions in schema pg_temp to authenticated;

-- R-33: FTI submits a seminar on the Nanyang chain, same dates and a similar name as S-13/S-14
:as_fti
insert into _ids select 'n', realisasi.save_activity_draft(null, '{"name":"Summer Program Smart Manufacturing Nanyang Polytechnic","type_id":6,"start_date":"2026-08-05",
   "end_date":"2026-08-20","mode":"offline","venue":"Nanyang Polytechnic","city":"Singapura","country_code":"SG","description":"x","submitter_unit_id":10,"document_ids":[113]}');
select realisasi.storage_put('realisasi-files/' || pg_temp.id('n') || '/' || k || '/f.pdf', 'application/pdf', convert_to('%PDF-1.4', 'UTF8')),
       realisasi.register_activity_file(pg_temp.id('n'), k::realisasi.file_kind, 'realisasi-files/' || pg_temp.id('n') || '/' || k || '/f.pdf', k || '.pdf', 8, 'application/pdf')
  from unnest(array['ia','ir']) k;
select pg_temp.eq((realisasi.submit_activity(pg_temp.id('n')) ->> 'duplicates_found')::int, 2, 'R-33 candidates against S-13 and S-14');
reset role;
create temp table _cand as select id from realisasi.duplicate_candidates where pg_temp.id('n') in (activity_a, activity_b) order by id;
grant select on _cand to authenticated;
select pg_temp.ok((select bool_and(score >= 0.5 and status = 'open') from realisasi.duplicate_candidates
                    where pg_temp.id('n') in (activity_a, activity_b)), 'open candidates with score >= threshold');
select pg_temp.ok(not exists (select 1 from realisasi.duplicate_candidates where pg_temp.id('n') in (activity_a, activity_b)
                               and pg_temp.aid(18) in (activity_a, activity_b)), 'rejected S-18 never a candidate');
select pg_temp.ok(exists (select 1 from realisasi.notifications where recipient_id = :'PART' and kind = 'duplicate_candidate'
                           and created_at = realisasi.now_ts()), 'partnership notified');
-- no candidate when the chain differs
:as_fbe
insert into _ids select 'x', realisasi.save_activity_draft(null, '{"name":"Summer Program Smart Manufacturing Nanyang Polytechnic","type_id":6,"start_date":"2026-08-05",
   "end_date":"2026-08-20","mode":"online","venue":"Zoom","description":"x","submitter_unit_id":20,"document_ids":[102]}');
select realisasi.storage_put('realisasi-files/' || pg_temp.id('x') || '/' || k || '/f.pdf', 'application/pdf', convert_to('%PDF-1.4', 'UTF8')),
       realisasi.register_activity_file(pg_temp.id('x'), k::realisasi.file_kind, 'realisasi-files/' || pg_temp.id('x') || '/' || k || '/f.pdf', k || '.pdf', 8, 'application/pdf')
  from unnest(array['ia','ir']) k;
select pg_temp.eq((realisasi.submit_activity(pg_temp.id('x')) ->> 'duplicates_found')::int, 0, 'R-33 requires a shared renewal chain');

-- R-34 link (merge event groups) / dismiss / unlink
:as_fti
select pg_temp.throws(format('select realisasi.link_duplicates(%s)', (select min(id) from _cand)), 'AUTH_FORBIDDEN', 'unit cannot link');
:as_part
select pg_temp.eq(realisasi.link_duplicates((select min(id) from _cand), 'Program yang sama') ->> 'event_group_id', 'e0000000-0000-4000-8000-000000000013',
                  'R-34 linked into the earlier group (…13)');
select pg_temp.eq((select count(*) from realisasi.activities where event_group_id = 'e0000000-0000-4000-8000-000000000013'), 3::bigint, 'group now has 3 activities');
select pg_temp.eq((select linked_count from realisasi.v_activity_list where id = pg_temp.id('n')), 2, 'linked_count');
select pg_temp.throws(format('select realisasi.link_duplicates(%s)', (select min(id) from _cand)), 'STATE_INVALID', 'candidate no longer open');
select pg_temp.throws(format('select realisasi.link_activities(%L, %L, %L)', pg_temp.id('n'), pg_temp.aid(14), 'x'), 'DUP_SAME_GROUP', 'already same group');
select pg_temp.throws(format('select realisasi.link_activities(%L, %L, %L)', pg_temp.id('n'), pg_temp.aid(23), 'x'), 'STATE_INVALID', 'cannot link a draft');
-- the second open candidate of n now lies inside one group: resolved automatically (review L4), so it cannot be dismissed
select pg_temp.eq((select status::text from realisasi.duplicate_candidates where id = (select max(id) from _cand)), 'linked', 'open candidate in the merged group auto-resolved');
select pg_temp.throws(format('select realisasi.dismiss_duplicate(%s)', (select max(id) from _cand)), 'STATE_INVALID', 'dismiss only open');
-- R-35: linked activities keep their own records; KPI S1 counts the group once (internal fn: superuser)
reset role;
select pg_temp.eq((select count(*) from realisasi.kpi_items('2026-08-01', '2026-10-01', '2026-10-01', 2) where kpi_code = '1.19.S1'
                    and activity_id in (pg_temp.aid(13), pg_temp.aid(14), pg_temp.id('n'))), 1::bigint, 'R-35 group counted once in S1');
:as_part
-- manual link of the open S-28 / S-30 candidate pair
select pg_temp.ok((realisasi.link_activities(pg_temp.aid(28), pg_temp.aid(30), 'Rombongan yang sama') -> 'activity_ids') @> to_jsonb(array[pg_temp.aid(28), pg_temp.aid(30)]),
                  'link_activities merges');
select pg_temp.eq((select status::text from realisasi.duplicate_candidates where pg_temp.aid(28) in (activity_a, activity_b)), 'linked', 'candidate upserted as linked');
select pg_temp.throws(format('select realisasi.unlink_activity(%L, %L)', pg_temp.id('n'), 'x'), 'R34_UNLINK_ADMIN_ONLY', 'R-34 unlink admin only');
:as_admin
select pg_temp.throws(format('select realisasi.unlink_activity(%L, %L)', pg_temp.id('n'), ''), 'VALIDATION_REQUIRED', 'unlink needs a note');
select pg_temp.ok((realisasi.unlink_activity(pg_temp.id('n'), 'Bukan program yang sama') ->> 'event_group_id') <> 'e0000000-0000-4000-8000-000000000013', 'unlinked to a new group');
select pg_temp.eq((select status::text from realisasi.duplicate_candidates where id = (select min(id) from _cand)), 'dismissed', 'linked candidate dismissed on unlink');
select pg_temp.ok(exists (select 1 from realisasi.activity_log where activity_id = pg_temp.id('n') and action = 'unlink_duplicate' and kind = 'update'), 'unlink logged');
select pg_temp.throws(format('select realisasi.unlink_activity(%L, %L)', pg_temp.id('n'), 'x'), 'STATE_INVALID', 'nothing left to unlink');

-- ---- Known Activities -------------------------------------------------------------------------------------------
:as_part
select pg_temp.throws($$select realisasi.create_known_activity('{"activity_date":"2026-09-01","is_international":true,"source":"email"}')$$, 'VALIDATION_REQUIRED', 'title required');
select pg_temp.throws($$select realisasi.create_known_activity('{"title":"x","activity_date":"2026-09-01","is_international":true,"source":"fax"}')$$, 'VALIDATION_INVALID', 'source enum');
create temp table _k as select realisasi.create_known_activity('{"title":"Summer program Nanyang Polytechnic","activity_date":"2026-08-05","unit_id":10,
   "partner_name":"Nanyang Polytechnic","country_code":"SG","is_international":true,"source":"surat_tugas"}') as id;
select pg_temp.ok(exists (select 1 from jsonb_array_elements(realisasi.known_match_suggestions((select id from _k))) e where e ->> 'code' = 'RL-2026-0013'),
                  'R-52 suggestion: same unit, ±7 days, similar name');
select pg_temp.ok((select array_agg((e ->> 'score')::numeric order by o) = array_agg((e ->> 'score')::numeric order by (e ->> 'score')::numeric desc)
                     from jsonb_array_elements(realisasi.known_match_suggestions((select id from _k))) with ordinality x(e, o)), 'suggestions sorted by score');
select pg_temp.ok((select bool_and((e ->> 'score')::numeric >= 0.4) from jsonb_array_elements(realisasi.known_match_suggestions((select id from _k))) e), 'suggestion scores >= 0.4');
select pg_temp.ok(not exists (select 1 from jsonb_array_elements(realisasi.known_match_suggestions((select id from _k))) e where e ->> 'code' in ('RL-2026-0014','RL-2026-0018')),
                  'other-unit and rejected activities not suggested');
select realisasi.update_known_activity((select id from _k), '{"unit_id":30}');
select pg_temp.eq(jsonb_array_length(realisasi.known_match_suggestions((select id from _k))), 0, 'unit mismatch -> no suggestion');
-- R-53
select realisasi.match_known_activity(6, pg_temp.aid(17));
select pg_temp.throws($$select realisasi.match_known_activity(6, pg_temp.aid(13))$$, 'R53_ALREADY_MATCHED', 'R-53 one SIM activity per known entry');
select pg_temp.throws($$select realisasi.update_known_activity(6, '{"title":"y"}')$$, 'STATE_INVALID', 'matched entry not editable');
select realisasi.match_known_activity(7, pg_temp.aid(17));
select pg_temp.eq((select count(*) from realisasi.known_activities where matched_activity_id = pg_temp.aid(17)), 2::bigint, 'R-53 a SIM activity can satisfy several entries');
select pg_temp.eq((select matched_activity_code from realisasi.v_known_activities where id = 6), 'RL-2026-0017', 'v_known_activities join');
select realisasi.unmatch_known_activity(6);
select pg_temp.throws($$select realisasi.match_known_activity(8, pg_temp.aid(13))$$, 'STATE_INVALID', 'dismissed cannot be matched');
select pg_temp.throws($$select realisasi.match_known_activity(6, pg_temp.aid(23))$$, 'STATE_INVALID', 'draft cannot be matched');
select realisasi.dismiss_known_activity((select id from _k), 'Duplikat entri');
select pg_temp.ok((select status = 'dismissed' and notes like '%Duplikat entri%' from realisasi.known_activities where id = (select id from _k)), 'dismiss appends note');
-- R-54 nudge once, re-send after 14 days
select pg_temp.throws($$select realisasi.nudge_known_activity(8)$$, 'STATE_INVALID', 'only unmatched can be nudged');
reset role;
update realisasi.known_activities set status = 'unmatched' where id = 8;
:as_part
select pg_temp.throws($$select realisasi.nudge_known_activity(8)$$, 'R54_NO_UNIT', 'R-54 needs a unit');
select pg_temp.ok(realisasi.nudge_known_activity(6) = realisasi.now_ts(), 'nudge returns nudged_at');
reset role;
select pg_temp.ok(exists (select 1 from realisasi.notifications where recipient_id = :'FBE' and kind = 'known_nudge' and link = '/realisasi/kegiatan/baru'), 'unit notified');
:as_part
select pg_temp.throws($$select realisasi.nudge_known_activity(6)$$, 'R54_NUDGE_TOO_SOON', 'R-54 resend too soon');
select pg_temp.eq((select can_nudge from realisasi.v_known_activities where id = 6), false, 'can_nudge false');
:as_admin
select realisasi.update_settings(format('{"demo_today": "%s"}', realisasi.today() + 15)::jsonb);
:as_part
select pg_temp.ok(realisasi.nudge_known_activity(6) is not null, 'R-54 resend allowed after 14 days');
:as_fti
select pg_temp.throws($$select realisasi.known_match_suggestions(6)$$, 'AUTH_FORBIDDEN', 'register IO only');
rollback;
