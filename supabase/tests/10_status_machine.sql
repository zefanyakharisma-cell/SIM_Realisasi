-- 10_status_machine: Revisi V.1 status machine (Mobility is the only verification track), AT-03, verified_at
-- immutability, post-verification edits.
\ir _helpers.inc

-- status derivation in the trigger (all combinations, as superuser on S-25, undone via savepoint)
savepoint st;
create temp table _combo as
select m::realisasi.track_status as m, s::boolean as submitted
  from unnest(array['not_required','pending','approved','revision_requested']) m, unnest(array['t','f']) s;
do $$
declare r record; v realisasi.activity_status; v_exp text;
begin
  for r in select * from _combo loop
    update realisasi.activities set mobility_status = r.m,
           submitted_at = case when r.submitted then coalesce(submitted_at, now()) end, verified_at = null
     where id = pg_temp.aid(25) returning status into v;
    v_exp := case when not r.submitted then 'draft'
                  when r.m = 'revision_requested' then 'revision_requested'
                  when r.m in ('approved','not_required') then 'verified' else 'in_verification' end;
    perform pg_temp.eq(v::text, v_exp, format('status M=%s submitted=%s', r.m, r.submitted));
  end loop;
end $$;
rollback to savepoint st;

-- seeded states
select pg_temp.eq(status::text, 'revision_requested', 'AT-03 S-16 overall revision_requested') from realisasi.activities where id = pg_temp.aid(16);
select pg_temp.eq(status::text, 'verified', 'S-17 non-mobility verified on submit') from realisasi.activities where id = pg_temp.aid(17);
select pg_temp.eq(status::text, 'in_verification', 'S-18 waits for Mobility') from realisasi.activities where id = pg_temp.aid(18);
select pg_temp.eq(status::text, 'draft', 'S-23 draft') from realisasi.activities where id = pg_temp.aid(23);
select pg_temp.eq(count(*), 3::bigint, 'S-18, S-29, S-30 in_verification') from realisasi.activities where status = 'in_verification';
select pg_temp.ok(not exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
                               where t.typname = 'activity_status' and e.enumlabel = 'rejected'), 'no rejected status any more');

-- ---- Non-mobility kegiatan: verified on submit (Revisi V.1 item 9) ---------------------------------------------------
:as_fsd
select pg_temp.eq(realisasi.save_activity_draft(pg_temp.aid(23), '{"end_date":"2026-08-14"}'), pg_temp.aid(23), 'S-23 draft editable');
reset role;
insert into realisasi.file_blobs (path, bucket, data, mime, size_bytes, created_by)
values ('realisasi-files/' || pg_temp.aid(23) || '/ir/t.pdf', 'realisasi-files', '\x255044462d312e340a'::bytea, 'application/pdf', 9, :'FSD');
:as_fsd
select realisasi.register_activity_file(pg_temp.aid(23), 'ir', 'realisasi-files/' || pg_temp.aid(23) || '/ir/t.pdf', 'IR.pdf', 9, 'application/pdf');
select pg_temp.eq(realisasi.submit_activity(pg_temp.aid(23)) ->> 'status', 'verified', 'non-mobility submit -> verified');
select pg_temp.ok(verified_at = realisasi.now_ts() and mobility_status = 'not_required', 'R-28 verified_at set on submit, no Mobility track')
  from realisasi.activities where id = pg_temp.aid(23);
select pg_temp.ok(exists (select 1 from realisasi.notifications where recipient_id = :'FSD' and kind = 'activity_verified'
                            and title like '%RL-2026-0023'), 'unit notified');
select pg_temp.throws($$select realisasi.submit_activity(pg_temp.aid(23))$$, 'STATE_INVALID', 'cannot resubmit a verified activity');
select pg_temp.throws($$select realisasi.save_activity_draft(pg_temp.aid(23), '{"venue":"x"}')$$, 'STATE_INVALID', 'verified activity not editable by unit');
reset role;
-- R-28: verified_at can never be changed or cleared
update realisasi.activities set verified_at = '2020-01-01', submitted_at = submitted_at where id = pg_temp.aid(23);
select pg_temp.ok(verified_at > '2026-01-01', 'R-28 verified_at immutable on update') from realisasi.activities where id = pg_temp.aid(23);
update realisasi.activities set verified_at = null where id = pg_temp.aid(23);
select pg_temp.ok(verified_at is not null, 'R-28 verified_at cannot be cleared') from realisasi.activities where id = pg_temp.aid(23);

-- ---- Mobility track ----------------------------------------------------------------------------------------------
:as_fti
select pg_temp.throws($$select realisasi.mobility_approve(pg_temp.aid(29))$$, 'NOT_FOUND', 'submitter cannot see other unit activity');
:as_fsd
select pg_temp.throws($$select realisasi.mobility_approve(pg_temp.aid(29))$$, 'AUTH_FORBIDDEN', 'unit cannot verify its own activity');
:as_view
select pg_temp.throws($$select realisasi.mobility_approve(pg_temp.aid(13))$$, 'AUTH_FORBIDDEN', 'viewer cannot verify');
:as_mob
select pg_temp.throws($$select realisasi.mobility_approve(pg_temp.aid(13))$$, 'TRACK_NOT_PENDING', 'cannot approve twice');
select pg_temp.throws($$select realisasi.mobility_approve(pg_temp.aid(18))$$, 'CONFLICT_OPEN', 'open student conflicts block approval (rule 2.1)');
select pg_temp.eq(realisasi.mobility_approve(pg_temp.aid(30), 'OK') ->> 'status', 'verified', 'approve S-30 -> verified');
select pg_temp.ok(verified_at = realisasi.now_ts(), 'verified_at set on approval') from realisasi.activities where id = pg_temp.aid(30);
select pg_temp.ok(exists (select 1 from realisasi.activity_log where activity_id = pg_temp.aid(30) and action = 'approve' and actor_id = :'MOB'),
                  'approve logged');
-- every IO staff account is in the mobility team now
:as_part
select pg_temp.ok(realisasi.in_team('mobility'), 'former partnership account is a mobility team member');

-- R-27: one revision note, no per-row notes (Revisi V.1)
:as_mob
select pg_temp.throws($$select realisasi.mobility_request_revision(pg_temp.aid(29), null)$$, 'R27_NOTE_REQUIRED', 'revision note required');
select pg_temp.eq(realisasi.mobility_request_revision(pg_temp.aid(29), 'Transkrip buram.') ->> 'status', 'revision_requested', 'request revision');
select pg_temp.eq(review_note, 'Transkrip buram.', 'note on the version') from realisasi.participant_set_versions where activity_id = pg_temp.aid(29);
select pg_temp.ok(not exists (select 1 from information_schema.columns where table_schema = 'realisasi' and column_name = 'row_note'),
                  'no per-row note columns');
select pg_temp.throws($$select realisasi.mobility_approve(pg_temp.aid(29))$$, 'TRACK_NOT_PENDING', 'mobility not pending anymore');
select pg_temp.eq((realisasi.activity_detail(pg_temp.aid(29)) -> 'revision' -> 'mobility' ->> 'note'), 'Transkrip buram.', 'activity_detail.revision');

-- ---- AT-03: S-16 Mobility revision; v2 approved -> verified; v1 kept read-only --------------------------------------
:as_fti
select pg_temp.throws($$select realisasi.submit_activity(pg_temp.aid(16))$$, 'R21_NEW_VERSION_REQUIRED', 'R-21 resubmit needs a new version');
select pg_temp.ok((realisasi.activity_detail(pg_temp.aid(16)) -> 'permissions' ->> 'can_edit_participants')::boolean, 'unit may edit participants');
select pg_temp.ok((realisasi.activity_detail(pg_temp.aid(16)) -> 'permissions' ->> 'can_edit_detail')::boolean, 'unit may edit detail during revision');
select pg_temp.ok((realisasi.activity_detail(pg_temp.aid(16)) -> 'permissions' ->> 'can_edit_files')::boolean, 'unit may replace files during revision');
select pg_temp.eq((realisasi.ensure_participant_draft(pg_temp.aid(16)) ->> 'version')::int, 2, 'v2 draft created');
select pg_temp.eq((realisasi.ensure_participant_draft(pg_temp.aid(16)) ->> 'created')::boolean, false, 'ensure is idempotent');
select pg_temp.eq((realisasi.save_participants(pg_temp.aid(16),
   '[{"section":"internal","nrp":"B12251882"},{"section":"internal","nrp":"B12252182"},{"section":"internal","nrp":"b12257991"}]', '[]') ->> 'students')::int,
   3, 'save_participants v2');
select realisasi.save_activity_draft(pg_temp.aid(16), '{"venue":"Kyoto Institute of Technology Matsugasaki"}');
select pg_temp.ok(exists (select 1 from realisasi.activity_log where activity_id = pg_temp.aid(16) and action = 'edit_detail' and track = 'mobility'),
                  'revision edit logged with diff');
select pg_temp.eq(realisasi.submit_activity(pg_temp.aid(16)) ->> 'mobility_status', 'pending', 'resubmit -> mobility pending');
select pg_temp.eq(status::text, 'in_verification', 'S-16 in verification') from realisasi.activities where id = pg_temp.aid(16);
select pg_temp.ok(exists (select 1 from realisasi.activity_log where activity_id = pg_temp.aid(16) and action = 'resubmit' and track = 'mobility'),
                  'resubmit logged');
select pg_temp.throws($$select realisasi.submit_activity(pg_temp.aid(16))$$, 'STATE_INVALID', 'cannot resubmit while pending');
:as_mob
select pg_temp.eq(realisasi.mobility_approve(pg_temp.aid(16), 'Data sesuai.') ->> 'status', 'verified', 'AT-03 v2 approved -> verified');
select pg_temp.eq(status::text, 'approved', 'v2 approved') from realisasi.participant_set_versions where activity_id = pg_temp.aid(16) and version = 2;
select pg_temp.eq(status::text, 'revision_requested', 'AT-03 v1 kept, status unchanged') from realisasi.participant_set_versions where activity_id = pg_temp.aid(16) and version = 1;
select pg_temp.ok((select array_agg(nrp order by nrp) from realisasi.participant_students s join realisasi.participant_set_versions v on v.id = s.set_version_id
                    where v.activity_id = pg_temp.aid(16) and v.version = 1) = array['B12251882','B12252182','B12254341'], 'v1 rows unchanged');
:as_fti
select pg_temp.throws($$select realisasi.ensure_participant_draft(pg_temp.aid(16))$$, 'STATE_INVALID', 'v1/v2 read-only for unit after verification');

-- a revision that turns the kegiatan into a non-mobility one is verified on resubmit
:as_fsd
select realisasi.save_activity_draft(pg_temp.aid(29), '{"agenda_id": 15}');
select pg_temp.eq(realisasi.submit_activity(pg_temp.aid(29)) ->> 'status', 'verified', 'Jenis changed to non-mobility -> verified on resubmit');
select pg_temp.eq(mobility_status::text, 'not_required', 'Mobility track no longer required') from realisasi.activities where id = pg_temp.aid(29);

-- ---- Post-verification edits (R-29..R-31): IO Admin for Detail, Mobility for participants --------------------------
:as_fti
select pg_temp.throws($$select realisasi.edit_verified_activity(pg_temp.aid(13), '{"venue":"x"}', 'n')$$, 'R29_EDIT_FORBIDDEN', 'unit cannot edit verified');
:as_mob
select pg_temp.throws($$select realisasi.edit_verified_activity(pg_temp.aid(13), '{"venue":"x"}', 'n')$$, 'R29_EDIT_FORBIDDEN', 'IO staff cannot edit detail');
:as_admin
select pg_temp.throws($$select realisasi.edit_verified_activity(pg_temp.aid(13), '{"submitter_unit_id": 11}', 'n')$$, 'VALIDATION_INVALID', 'submitter unit immutable');
select pg_temp.throws($$select realisasi.edit_verified_activity(pg_temp.aid(13), '{"end_date": "2027-01-01"}', 'n')$$, 'R08_END_AFTER_TODAY', 'R-08 on verified edit');
select pg_temp.eq((realisasi.edit_verified_activity(pg_temp.aid(1), '{"venue":"Hanyang University ERICA Campus"}', 'Koreksi kampus') ->> 'in_frozen_period')::boolean,
                  true, 'R-31 edit of frozen-window activity flagged');
select pg_temp.eq((realisasi.edit_verified_activity(pg_temp.aid(13), '{"sdg_ids":[4,9,17]}', 'Tambah SDG') -> 'diff' -> 'sdg_ids'), '[[4, 9], [4, 9, 17]]'::jsonb, 'R-30 diff for arrays');
select pg_temp.ok(status = 'verified' and verified_at = '2026-09-10 14:00+07', 'status/verified_at unchanged by edit') from realisasi.activities where id = pg_temp.aid(13);
select pg_temp.eq((realisasi.edit_verified_activity(pg_temp.aid(13), '{"sdg_ids":[4,9,17]}', 'noop') -> 'diff'), '{}'::jsonb, 'no-op edit has empty diff');
select pg_temp.throws($$select realisasi.edit_verified_activity(pg_temp.aid(13), '{"direction":"inbound"}', 'n')$$, 'R12_INBOUND_STUDENT_REQUIRED',
                      'direction change must still fit the approved participants');
:as_mob
select realisasi.ensure_participant_draft(pg_temp.aid(14));
select realisasi.save_participants(pg_temp.aid(14), (select jsonb_agg(jsonb_build_object('section','internal','nrp',s.nrp)) from realisasi.participant_students s
   join realisasi.participant_set_versions v on v.id = s.set_version_id where v.activity_id = pg_temp.aid(14) and v.version = 1 and s.nrp <> 'B12249536'), '[]');
select pg_temp.eq(realisasi.commit_participant_edit(pg_temp.aid(14), 'Satu peserta batal berangkat') -> 'diff' -> 'students' -> 'removed', '["B12249536"]'::jsonb,
                  'commit_participant_edit diff');
select pg_temp.eq(string_agg(version || ':' || status, ',' order by version), '1:superseded,2:approved', 'R-21 previous approved superseded')
  from realisasi.participant_set_versions where activity_id = pg_temp.aid(14);
select pg_temp.eq(actor_id, :'MOB'::uuid, 'update/mobility/edit logged') from realisasi.activity_log where activity_id = pg_temp.aid(14) and kind = 'update' and track = 'mobility';
select pg_temp.throws($$select realisasi.commit_participant_edit(pg_temp.aid(14), 'x')$$, 'STATE_INVALID', 'commit needs a draft version');
-- the resolved conflicts of the removed student stay as decided; the rest are untouched
select pg_temp.eq((select count(*) from realisasi.participant_conflicts where status = 'resolved'), 12::bigint, 'resolved conflicts kept after a participant edit');

-- one_approved_pset invariant always holds
reset role;
select pg_temp.ok(not exists (select activity_id from realisasi.participant_set_versions where status = 'approved' group by 1 having count(*) > 1),
                  'at most one approved version per activity');
rollback;
