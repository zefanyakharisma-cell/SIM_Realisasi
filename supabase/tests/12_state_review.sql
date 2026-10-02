-- 12_state_review: state regressions (former database-review H4, L2, M1, L9) re-cut for Revisi V.1 (one Mobility track,
-- agenda as Jenis, direction per kegiatan).
\ir _helpers.inc

-- ---- H4: Jenis/direction change during a Mobility revision -------------------------------------------------------
-- S-30 (Prodi Manajemen, Short Program outbound, v1 pending); io_admin acts for the unit (unit 21 has no submitter)
:as_mob
select realisasi.mobility_request_revision(pg_temp.aid(30), 'Arah kegiatan salah');
:as_admin
select realisasi.save_activity_draft(pg_temp.aid(30), '{"direction": "inbound"}');
select pg_temp.eq((realisasi.ensure_participant_draft(pg_temp.aid(30)) ->> 'version')::int, 2, 'H4 unit opens a new participant version during revision');
select pg_temp.throws($$select realisasi.submit_activity(pg_temp.aid(30))$$, 'R12_INBOUND_STUDENT_REQUIRED', 'H4 R-12 follows the new direction');
select realisasi.save_participants(pg_temp.aid(30), '[{"section":"inbound","nrp":"X01260027"}]', '[]');
select pg_temp.eq(realisasi.submit_activity(pg_temp.aid(30)) ->> 'mobility_status', 'pending', 'H4 resubmit succeeds; Mobility pending');
select pg_temp.eq((select string_agg(version || ':' || status, ',' order by version) from realisasi.participant_set_versions where activity_id = pg_temp.aid(30)),
                  '1:revision_requested,2:pending', 'H4 v1 kept as reviewed, v2 pending');
reset role;
select pg_temp.eq((select count(*) from realisasi.notifications where recipient_id = :'MOB' and title = 'Revisi diajukan: RL-2026-0030'
                     and created_at = realisasi.now_ts()), 1::bigint, 'mobility team notified once of the resubmission');
:as_mob
select realisasi.mobility_approve(pg_temp.aid(30));
reset role;
select pg_temp.eq((select string_agg(version || ':' || status, ',' order by version) from realisasi.participant_set_versions where activity_id = pg_temp.aid(30)),
                  '1:revision_requested,2:approved', 'H4 no orphan pending version after approval');
-- L2 invariant: at most one pending version per activity
select pg_temp.ok(exists (select 1 from pg_indexes where schemaname = 'realisasi' and indexname = 'one_pending_pset'), 'L2 one_pending_pset index exists');

-- ---- M1: Jenis/direction change on a verified activity is validated ------------------------------------------------
:as_admin
select pg_temp.throws($$select realisasi.edit_verified_activity(pg_temp.aid(24), '{"agenda_id":2}', 'x')$$, 'R11_PARTICIPANTS_REQUIRED',
                      'M1 S-24 cannot become Student Exchange without participants');
select pg_temp.throws($$select realisasi.edit_verified_activity(pg_temp.aid(15), '{"direction":"inbound"}', 'x')$$, 'R12_INBOUND_STUDENT_REQUIRED',
                      'M1 S-15 cannot become inbound without inbound students');
select pg_temp.eq(realisasi.edit_verified_activity(pg_temp.aid(15), '{"agenda_id":23}', 'x') #>> '{diff,agenda_id,1}', '23', 'M1 mobility -> mobility allowed');
select pg_temp.eq(realisasi.edit_verified_activity(pg_temp.aid(24), '{"agenda_id":4}', 'x') #>> '{diff,agenda_id,1}', '4', 'M1 change between non-mobility agendas allowed');
select pg_temp.eq(sks_recognized, null::numeric, 'non-mobility keeps no SKS') from realisasi.activities where id = pg_temp.aid(24);

-- ---- L9 R-11 in commit_participant_edit ----------------------------------------------------------------------------
:as_mob
select realisasi.ensure_participant_draft(pg_temp.aid(10));
select realisasi.save_participants(pg_temp.aid(10), '[]', '[]');
select pg_temp.throws($$select realisasi.commit_participant_edit(pg_temp.aid(10), 'kosongkan')$$, 'R11_PARTICIPANTS_REQUIRED',
                      'L9 R-11 empty set rejected for a mobility kegiatan');
:as_admin
select pg_temp.ok(not (realisasi.activity_detail(pg_temp.aid(24)) #>> '{permissions,can_edit_verified_participants}')::boolean,
                  'non-mobility kegiatan has no participant editing');
rollback;
