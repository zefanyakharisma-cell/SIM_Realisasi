-- 12_state_review: regressions from docs/reviews/database-review.md (H4, L1, L2, M1, L9/R-11).
\ir _helpers.inc

-- ---- H4 (R-24, R-11/R-12): Jenis change during a Partnership revision while Mobility is pending ----
-- S-30 (Manajemen, Staff Outbound, P and M pending, v1 pending with staff only); io_admin acts for the unit
:as_part
select realisasi.partnership_request_revision(pg_temp.aid(30), 'Jenis kegiatan salah');
:as_admin
select realisasi.save_activity_draft(pg_temp.aid(30), '{"type_id": 1}');
select pg_temp.throws($$select realisasi.submit_activity(pg_temp.aid(30))$$, 'R12_OUTBOUND_STUDENT_REQUIRED', 'H4 R-12 blocks resubmit without a student');
select pg_temp.eq((realisasi.ensure_participant_draft(pg_temp.aid(30)) ->> 'version')::int, 2, 'H4 unit may open a new participant version during P revision');
select realisasi.save_participants(pg_temp.aid(30), '[{"section":"internal","nrp":"D31240187"}]',
  (select jsonb_agg(jsonb_build_object('employee_id', st.employee_id)) from realisasi.participant_staff st
     join realisasi.participant_set_versions v on v.id = st.set_version_id where v.activity_id = pg_temp.aid(30) and v.version = 1));
select pg_temp.eq(realisasi.submit_activity(pg_temp.aid(30)) ->> 'mobility_status', 'pending', 'H4 resubmit succeeds; Mobility pending');
select pg_temp.eq((select string_agg(version || ':' || status, ',' order by version) from realisasi.participant_set_versions where activity_id = pg_temp.aid(30)),
                  '1:superseded,2:pending', 'H4/L2 older pending version superseded on promotion');
:as_mob
select realisasi.mobility_approve(pg_temp.aid(30));
reset role;
select pg_temp.eq((select string_agg(version || ':' || status, ',' order by version) from realisasi.participant_set_versions where activity_id = pg_temp.aid(30)),
                  '1:superseded,2:approved', 'H4 no orphan pending version after approval');
-- L2 invariant: at most one pending version per activity
select pg_temp.ok(exists (select 1 from pg_indexes where schemaname = 'realisasi' and indexname = 'one_pending_pset'), 'L2 one_pending_pset index exists');

-- ---- L1: a rejected activity's participants are frozen --------------------------------------------
update realisasi.activities set partnership_status = 'pending' where id = pg_temp.aid(16);  -- S-16: P pending, M revision_requested
:as_part
select realisasi.partnership_reject(pg_temp.aid(16), 'other', 'Ditolak');
:as_fti
select pg_temp.throws($$select realisasi.ensure_participant_draft(pg_temp.aid(16))$$, 'STATE_INVALID', 'L1 rejected activity: no new participant version');
select pg_temp.ok(not (realisasi.activity_detail(pg_temp.aid(16)) #>> '{permissions,can_submit}')::boolean, 'L1 rejected activity cannot be submitted');
select pg_temp.ok(not (realisasi.activity_detail(pg_temp.aid(16)) #>> '{permissions,can_edit_participants}')::boolean, 'L1 rejected activity: participants read-only');

-- ---- M1 (R-11/R-12/R-24): Jenis change on a verified activity is validated ------------------------
:as_part
select pg_temp.throws($$select realisasi.edit_verified_activity(pg_temp.aid(24), '{"type_id":1}', 'x')$$, 'R11_PARTICIPANTS_REQUIRED',
                      'M1 S-24 cannot become Student Outbound without participants');
select pg_temp.throws($$select realisasi.edit_verified_activity(pg_temp.aid(15), '{"type_id":2}', 'x')$$, 'R12_INBOUND_STUDENT_REQUIRED',
                      'M1 S-15 cannot become Inbound without inbound students');
select pg_temp.eq(realisasi.edit_verified_activity(pg_temp.aid(15), '{"type_id":7}', 'x') #>> '{diff,type_id,1}', '7', 'M1 outbound -> outbound allowed');
select pg_temp.eq(realisasi.edit_verified_activity(pg_temp.aid(24), '{"type_id":5}', 'x') #>> '{diff,type_id,1}', '5', 'M1 change between non-mobility types allowed');

-- ---- L9 R-11 in commit_participant_edit ------------------------------------------------------------
:as_mob
select realisasi.mobility_approve(pg_temp.aid(28));             -- S-28 Staff Outbound -> verified
select realisasi.ensure_participant_draft(pg_temp.aid(28));
select realisasi.save_participants(pg_temp.aid(28), '[]', '[]');
select pg_temp.throws($$select realisasi.commit_participant_edit(pg_temp.aid(28), 'kosongkan')$$, 'R11_PARTICIPANTS_REQUIRED',
                      'L9 R-11 empty set rejected for a type that requires mobility review');
rollback;
