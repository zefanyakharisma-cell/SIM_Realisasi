-- 10_status_machine: R-23..R-28, AT-03, AT-04, verified_at immutability, post-verification edits.
\ir _helpers.inc

-- R-25 derivation in the trigger (all combinations, as superuser on S-25, undone via savepoint)
savepoint r25;
create temp table _combo as
select p::realisasi.track_status as p, m::realisasi.track_status as m, s::boolean as submitted
  from unnest(array['pending','approved','revision_requested','rejected']) p,
       unnest(array['not_required','pending','approved','revision_requested']) m, unnest(array['t','f']) s;
do $$
declare r record; v realisasi.activity_status; v_exp text;
begin
  for r in select * from _combo loop
    update realisasi.activities set partnership_status = r.p, mobility_status = r.m,
           submitted_at = case when r.submitted then coalesce(submitted_at, now()) end, verified_at = null
     where id = pg_temp.aid(25) returning status into v;
    v_exp := case when not r.submitted then 'draft' when r.p = 'rejected' then 'rejected'
                  when r.p = 'revision_requested' or r.m = 'revision_requested' then 'revision_requested'
                  when r.p = 'approved' and r.m in ('approved','not_required') then 'verified' else 'in_verification' end;
    perform pg_temp.eq(v::text, v_exp, format('R-25 P=%s M=%s submitted=%s', r.p, r.m, r.submitted));
  end loop;
end $$;
rollback to savepoint r25;

-- seeded states
select pg_temp.eq(status::text, 'revision_requested', 'AT-03 S-16 overall revision_requested') from realisasi.activities where id = pg_temp.aid(16);
select pg_temp.eq(partnership_status::text || '/' || mobility_status, 'approved/revision_requested', 'S-16 tracks') from realisasi.activities where id = pg_temp.aid(16);
select pg_temp.eq(status::text, 'revision_requested', 'S-17 revision_requested') from realisasi.activities where id = pg_temp.aid(17);
select pg_temp.eq(status::text, 'rejected', 'S-18 rejected') from realisasi.activities where id = pg_temp.aid(18);
select pg_temp.eq(status::text, 'draft', 'S-23 draft') from realisasi.activities where id = pg_temp.aid(23);
select pg_temp.eq(count(*), 6::bigint, 'S-25..S-30 in_verification') from realisasi.activities where status = 'in_verification';

-- ---- Partnership track -------------------------------------------------------------------
:as_fti
select pg_temp.throws($$select realisasi.partnership_approve(pg_temp.aid(27))$$, 'NOT_FOUND', 'submitter cannot see other unit activity');
:as_mob
select pg_temp.throws($$select realisasi.partnership_approve(pg_temp.aid(25))$$, 'AUTH_FORBIDDEN', 'mobility team cannot approve partnership');
:as_part
select pg_temp.throws($$select realisasi.partnership_approve(pg_temp.aid(23))$$, 'STATE_INVALID', 'cannot approve a draft');
select pg_temp.throws($$select realisasi.partnership_approve(pg_temp.aid(13))$$, 'TRACK_NOT_PENDING', 'cannot approve twice');
select pg_temp.throws($$select realisasi.mobility_approve(pg_temp.aid(28))$$, 'AUTH_FORBIDDEN', 'partnership cannot approve mobility');
select pg_temp.eq((realisasi.partnership_approve(pg_temp.aid(25), 'OK')) ->> 'status', 'verified', 'R-23 approve S-25 (no mobility) -> verified');
select pg_temp.ok(verified_at is not null and verified_at = realisasi.now_ts(), 'R-28 verified_at set on first verification')
  from realisasi.activities where id = pg_temp.aid(25);
select pg_temp.ok(exists (select 1 from realisasi.activity_log where activity_id = pg_temp.aid(25) and action = 'approve' and actor_id = :'PART'), 'approve logged');
reset role;
-- R-28: verified_at can never be changed or cleared
update realisasi.activities set verified_at = '2020-01-01', submitted_at = submitted_at where id = pg_temp.aid(25);
select pg_temp.ok(verified_at > '2026-01-01', 'R-28 verified_at immutable on update') from realisasi.activities where id = pg_temp.aid(25);
update realisasi.activities set verified_at = null where id = pg_temp.aid(25);
select pg_temp.ok(verified_at is not null, 'R-28 verified_at cannot be cleared') from realisasi.activities where id = pg_temp.aid(25);

-- R-26 reject
:as_part
select pg_temp.throws($$select realisasi.partnership_reject(pg_temp.aid(26), null, 'x')$$, 'R26_REASON_REQUIRED', 'reject needs reason');
select pg_temp.throws($$select realisasi.partnership_reject(pg_temp.aid(26), 'bogus', 'x')$$, 'R26_REASON_REQUIRED', 'reject reason must be valid');
select pg_temp.throws($$select realisasi.partnership_reject(pg_temp.aid(26), 'other', '  ')$$, 'R26_NOTE_REQUIRED', 'reject needs note');
select pg_temp.eq(realisasi.partnership_reject(pg_temp.aid(26), 'not_partnership', 'Bukan kegiatan kerja sama.') ->> 'status', 'rejected', 'R-26 reject');
select pg_temp.eq(rejection_reason, 'not_partnership', 'rejection_reason stored') from realisasi.activities where id = pg_temp.aid(26);
select pg_temp.throws($$select realisasi.partnership_approve(pg_temp.aid(26))$$, 'STATE_INVALID', 'R-26 rejection is terminal');
select pg_temp.eq((realisasi.activity_detail(pg_temp.aid(26)) -> 'rejection' ->> 'note'), 'Bukan kegiatan kerja sama.', 'activity_detail.rejection');
:as_admin
select pg_temp.throws($$select realisasi.submit_activity(pg_temp.aid(26))$$, 'STATE_INVALID', 'rejected cannot be resubmitted');

-- R-27 revision request needs a note; R-23 revision -> resubmit -> pending; track clock restarts (R-60)
:as_part
select pg_temp.throws($$select realisasi.partnership_request_revision(pg_temp.aid(27), '')$$, 'R27_NOTE_REQUIRED', 'R-27 note required');
select pg_temp.eq(realisasi.partnership_request_revision(pg_temp.aid(27), 'Lengkapi tempat kegiatan.') ->> 'status', 'revision_requested', 'request revision');
select pg_temp.ok(partnership_since = realisasi.now_ts(), 'partnership_since restarted') from realisasi.activities where id = pg_temp.aid(27);
select pg_temp.ok(partnership_sla_days is null, 'no SLA while unit revises') from realisasi.v_activity_list where id = pg_temp.aid(27);
:as_admin
select realisasi.save_activity_draft(pg_temp.aid(27), '{"venue":"Lab Tenaga Listrik Gedung T"}');
select pg_temp.eq(diff, '{"venue": ["Lab Tenaga Listrik PCU", "Lab Tenaga Listrik Gedung T"]}'::jsonb, 'revision edit logged with diff')
  from realisasi.activity_log where activity_id = pg_temp.aid(27) and action = 'edit_detail';
select pg_temp.eq(realisasi.submit_activity(pg_temp.aid(27)) ->> 'status', 'in_verification', 'R-23 resubmit -> pending');
select pg_temp.eq(mobility_status::text, 'not_required', 'R-24 no Jenis change -> Mobility untouched') from realisasi.activities where id = pg_temp.aid(27);
select pg_temp.throws($$select realisasi.submit_activity(pg_temp.aid(27))$$, 'STATE_INVALID', 'cannot resubmit while pending');
:as_fti
select pg_temp.throws($$select realisasi.save_activity_draft(pg_temp.aid(13), '{"venue":"x"}')$$, 'STATE_INVALID', 'verified activity not editable by unit');

-- ---- AT-03: S-16 Partnership approved, Mobility revision; v2 approved -> verified; v1 kept read-only -------------
:as_fti
select pg_temp.throws($$select realisasi.submit_activity(pg_temp.aid(16))$$, 'R21_NEW_VERSION_REQUIRED', 'R-21 resubmit needs a new version');
select pg_temp.ok((realisasi.activity_detail(pg_temp.aid(16)) -> 'permissions' ->> 'can_edit_participants')::boolean, 'unit may edit participants');
select pg_temp.ok(not (realisasi.activity_detail(pg_temp.aid(16)) -> 'permissions' ->> 'can_edit_detail')::boolean, 'unit may not edit detail (mobility-only revision)');
select pg_temp.eq((realisasi.ensure_participant_draft(pg_temp.aid(16)) ->> 'version')::int, 2, 'v2 draft created');
select pg_temp.eq((realisasi.ensure_participant_draft(pg_temp.aid(16)) ->> 'created')::boolean, false, 'ensure is idempotent');
select pg_temp.eq((select count(*) from realisasi.participant_students s join realisasi.participant_set_versions v on v.id = s.set_version_id
                    where v.activity_id = pg_temp.aid(16) and v.version = 2 and s.row_note is null), 3::bigint, 'v2 copies rows with notes cleared');
select pg_temp.eq((realisasi.save_participants(pg_temp.aid(16),
   '[{"section":"internal","nrp":"B12251882"},{"section":"internal","nrp":"B12252182"},{"section":"internal","nrp":"b12257991"}]', '[]') ->> 'students')::int,
   3, 'save_participants v2');
select pg_temp.eq(realisasi.submit_activity(pg_temp.aid(16)) ->> 'mobility_status', 'pending', 'resubmit -> mobility pending');
select pg_temp.eq(status::text, 'in_verification', 'S-16 in verification') from realisasi.activities where id = pg_temp.aid(16);
:as_mob
select pg_temp.eq(realisasi.mobility_approve(pg_temp.aid(16), 'Data sesuai.') ->> 'status', 'verified', 'AT-03 v2 approved -> verified');
select pg_temp.eq(status::text, 'approved', 'v2 approved') from realisasi.participant_set_versions where activity_id = pg_temp.aid(16) and version = 2;
select pg_temp.eq(status::text, 'revision_requested', 'AT-03 v1 kept, status unchanged') from realisasi.participant_set_versions where activity_id = pg_temp.aid(16) and version = 1;
select pg_temp.ok((select array_agg(nrp order by nrp) from realisasi.participant_students s join realisasi.participant_set_versions v on v.id = s.set_version_id
                    where v.activity_id = pg_temp.aid(16) and v.version = 1) = array['B12251882','B12252182','B12254341'], 'v1 rows unchanged');
select pg_temp.eq((realisasi.participant_version(pg_temp.aid(16), 1) -> 'students' -> 2 ->> 'row_note'), 'NRP tidak tercantum pada surat tugas.', 'v1 row note preserved');
:as_fti
select pg_temp.throws($$select realisasi.ensure_participant_draft(pg_temp.aid(16))$$, 'STATE_INVALID', 'v1/v2 read-only for unit after verification');

-- ---- AT-04: S-17 Partnership revision changes Jenis Joint Seminar -> Student Outbound => Mobility resets to pending ----
:as_fbe
select pg_temp.eq(mobility_status::text, 'not_required', 'S-17 mobility not_required before') from realisasi.activities where id = pg_temp.aid(17);
select realisasi.save_activity_draft(pg_temp.aid(17), '{"type_id": 1}');
select pg_temp.eq(diff -> 'type_id', '[6, 1]'::jsonb, 'type change in revision log') from realisasi.activity_log
 where activity_id = pg_temp.aid(17) and action = 'edit_detail';
select pg_temp.throws($$select realisasi.submit_activity(pg_temp.aid(17))$$, 'R11_PARTICIPANTS_REQUIRED', 'new Jenis requires participants');
select realisasi.save_participants(pg_temp.aid(17), '[{"section":"internal","nrp":"D31238836"}]', '[]');
select pg_temp.eq(realisasi.submit_activity(pg_temp.aid(17)) ->> 'mobility_status', 'pending', 'AT-04 Mobility track reset to pending');
select pg_temp.eq(partnership_status::text || '/' || status, 'pending/in_verification', 'S-17 back in verification') from realisasi.activities where id = pg_temp.aid(17);
select pg_temp.eq(status::text, 'pending', 'S-17 participant v1 pending') from realisasi.participant_set_versions where activity_id = pg_temp.aid(17);
select pg_temp.ok(exists (select 1 from realisasi.activity_log where activity_id = pg_temp.aid(17) and action = 'resubmit' and track = 'partnership'), 'resubmit logged');

-- ---- Mobility revision with row notes (R-27) on S-29 ----------------------------------------------------------------
:as_mob
select pg_temp.throws($$select realisasi.mobility_request_revision(pg_temp.aid(29), null)$$, 'R27_NOTE_REQUIRED', 'mobility revision note required');
select pg_temp.eq(realisasi.mobility_request_revision(pg_temp.aid(29), 'Transkrip buram.', '[{"kind":"student","id":"X02260008","note":"Unggah ulang transkrip"}]') ->> 'status',
                  'revision_requested', 'mobility request revision');
select pg_temp.eq(row_note, 'Unggah ulang transkrip', 'row note stored') from realisasi.participant_students s
  join realisasi.participant_set_versions v on v.id = s.set_version_id where v.activity_id = pg_temp.aid(29) and s.nrp = 'X02260008';
select pg_temp.throws($$select realisasi.mobility_approve(pg_temp.aid(29))$$, 'TRACK_NOT_PENDING', 'mobility not pending anymore');
select pg_temp.eq(realisasi.mobility_approve(pg_temp.aid(28)) ->> 'status', 'verified', 'S-28 mobility approve -> verified (P already approved)');

-- ---- Post-verification edits (R-29..R-31) ----------------------------------------------------------------------------
:as_fti
select pg_temp.throws($$select realisasi.edit_verified_activity(pg_temp.aid(13), '{"venue":"x"}', 'n')$$, 'R29_EDIT_FORBIDDEN', 'unit cannot edit verified');
:as_mob
select pg_temp.throws($$select realisasi.edit_verified_activity(pg_temp.aid(13), '{"venue":"x"}', 'n')$$, 'AUTH_FORBIDDEN', 'mobility cannot edit detail');
:as_part
select pg_temp.throws($$select realisasi.edit_verified_activity(pg_temp.aid(13), '{"submitter_unit_id": 11}', 'n')$$, 'VALIDATION_INVALID', 'submitter unit immutable');
select pg_temp.throws($$select realisasi.edit_verified_activity(pg_temp.aid(13), '{"end_date": "2027-01-01"}', 'n')$$, 'R08_END_AFTER_TODAY', 'R-08 on verified edit');
select pg_temp.eq((realisasi.edit_verified_activity(pg_temp.aid(1), '{"venue":"Hanyang University ERICA Campus"}', 'Koreksi kampus') ->> 'in_frozen_period')::boolean,
                  true, 'R-31 edit of frozen-window activity flagged');
select pg_temp.eq((realisasi.edit_verified_activity(pg_temp.aid(13), '{"sdg_ids":[4,9,17]}', 'Tambah SDG') -> 'diff' -> 'sdg_ids'), '[[4, 9], [4, 9, 17]]'::jsonb, 'R-30 diff for arrays');
select pg_temp.ok(status = 'verified' and verified_at = '2026-09-10 14:00+07', 'status/verified_at unchanged by edit') from realisasi.activities where id = pg_temp.aid(13);
select pg_temp.eq((realisasi.edit_verified_activity(pg_temp.aid(13), '{"sdg_ids":[4,9,17]}', 'noop') -> 'diff'), '{}'::jsonb, 'no-op edit has empty diff');
:as_mob
select realisasi.ensure_participant_draft(pg_temp.aid(13));
select realisasi.save_participants(pg_temp.aid(13), (select jsonb_agg(jsonb_build_object('section','internal','nrp',s.nrp)) from realisasi.participant_students s
   join realisasi.participant_set_versions v on v.id = s.set_version_id where v.activity_id = pg_temp.aid(13) and v.version = 1 and s.nrp <> 'B12249536'), '[]');
select pg_temp.eq(realisasi.commit_participant_edit(pg_temp.aid(13), 'Satu peserta batal berangkat') -> 'diff' -> 'students' -> 'removed', '["B12249536"]'::jsonb,
                  'commit_participant_edit diff');
select pg_temp.eq(string_agg(version || ':' || status, ',' order by version), '1:superseded,2:approved', 'R-21 previous approved superseded')
  from realisasi.participant_set_versions where activity_id = pg_temp.aid(13);
select pg_temp.eq(actor_id, :'MOB'::uuid, 'update/mobility/edit logged') from realisasi.activity_log where activity_id = pg_temp.aid(13) and kind = 'update' and track = 'mobility';
select pg_temp.throws($$select realisasi.commit_participant_edit(pg_temp.aid(13), 'x')$$, 'STATE_INVALID', 'commit needs a draft version');

-- one_approved_pset invariant always holds
reset role;
select pg_temp.ok(not exists (select activity_id from realisasi.participant_set_versions where status = 'approved' group by 1 having count(*) > 1),
                  'at most one approved version per activity');
rollback;
