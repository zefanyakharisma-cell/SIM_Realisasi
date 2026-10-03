-- 60_conflicts: Verifikasi Mobilitas duplicates (Revisi V.1). Rule 2.1: one student claimed in the same kegiatan by two
-- units (same NRP, overlapping dates, different submitter units) -> Mobility picks the activity that keeps the student.
-- Rule 2.2: one student in two kegiatan of the same unit -> counted in both, never a conflict.
\ir _helpers.inc

create temp table _ids (k text primary key, id uuid);
grant all on _ids to authenticated;
create function pg_temp.id(p_k text) returns uuid language sql as $$ select id from _ids where k = p_k $$;
create function pg_temp.new_mobility(p_unit int, p_start date, p_end date, p_nrps text[]) returns uuid language plpgsql as $$
declare v uuid; k text; v_path text;
begin
  v := realisasi.save_activity_draft(null, jsonb_build_object('name', 'Uji konflik ' || p_unit || ' ' || p_start, 'agenda_id', 23,
         'direction', 'outbound', 'start_date', p_start, 'end_date', p_end, 'mode', 'offline', 'venue', 'Nanyang Polytechnic',
         'country_code', 'SG', 'description', 'Uji', 'submitter_unit_id', p_unit, 'document_id', 113));
  perform realisasi.save_participants(v, (select jsonb_agg(jsonb_build_object('section', 'internal', 'nrp', n)) from unnest(p_nrps) n), '[]');
  foreach k in array array['ia','ir','mobility_bundle'] loop
    v_path := case when k = 'mobility_bundle' then 'realisasi-transcripts/' else 'realisasi-files/' end || v || '/' || k || '/f.pdf';
    perform realisasi.storage_put(v_path, 'application/pdf', convert_to('%PDF-1.4 t', 'UTF8'));
    perform realisasi.register_activity_file(v, k::realisasi.file_kind, v_path, k || '.pdf', null, null);
  end loop;
  return v;
end $$;
grant execute on all functions in schema pg_temp to authenticated;

-- seeded state: S-13 (FTI) vs S-14 (Informatika) resolved for S-13; S-13 vs S-18 open
select pg_temp.eq((select count(*) from realisasi.participant_conflicts where status = 'resolved' and kept_activity_id = pg_temp.aid(13)), 12::bigint,
                  'S-13/S-14: 12 decisions kept on S-13');
select pg_temp.eq((select count(*) from realisasi.participant_conflicts where status = 'open'), 2::bigint, 'S-13/S-18: 2 open');
select pg_temp.ok(not exists (select 1 from realisasi.participant_conflicts c join realisasi.activities a on a.id = c.activity_a
                                join realisasi.activities b on b.id = c.activity_b where a.submitter_unit_id = b.submitter_unit_id),
                  'rule 2.2: never a conflict within one unit');

-- conflict_list / activity_detail for the mobility team
:as_mob
select pg_temp.eq((select jsonb_agg(c ->> 'nrp' order by c ->> 'nrp') from jsonb_array_elements(realisasi.conflict_list()) c),
                  '["B11227366", "B11234310"]'::jsonb, 'conflict_list open');
select pg_temp.ok((select bool_and(c -> 'a' -> 'bundle' ->> 'href' like '/api/files/realisasi-transcripts/%'
                               and c -> 'b' -> 'bundle' ->> 'href' like '/api/files/realisasi-transcripts/%')
                     from jsonb_array_elements(realisasi.conflict_list()) c), 'both sides link their mobility bundle PDF');
select pg_temp.eq((realisasi.conflict_list() -> 0 ->> 'student_name'), 'Cindy Liem', 'student name from BAAK');
select pg_temp.eq((select jsonb_agg(distinct c -> 'b' ->> 'unit_name') from jsonb_array_elements(realisasi.conflict_list()) c),
                  '["Program Studi Informatika"]'::jsonb, 'unit names on both sides');
select pg_temp.eq((realisasi.activity_detail(pg_temp.aid(18)) #>> '{flags,conflicts_open}')::int, 2, 'activity_detail flags open conflicts');
select pg_temp.eq(jsonb_array_length(realisasi.activity_detail(pg_temp.aid(18)) -> 'conflicts'), 2, 'activity_detail lists the conflicts');
select pg_temp.throws($$select realisasi.conflict_list(null, 'bogus')$$, 'VALIDATION_INVALID', 'status filter validated');

-- resolve_conflict validation and effects
select pg_temp.throws($$select realisasi.resolve_conflict(999999, pg_temp.aid(13))$$, 'NOT_FOUND', 'unknown conflict');
select pg_temp.throws(format('select realisasi.resolve_conflict(%s, %L)', (select min(id) from realisasi.participant_conflicts where status = 'open'), pg_temp.aid(10)),
                      'VALIDATION_INVALID', 'kept activity must be one of the two');
select pg_temp.eq(realisasi.resolve_conflict((select min(id) from realisasi.participant_conflicts where status = 'open'), pg_temp.aid(18), 'Bukti di PDF Informatika')
                  ->> 'open_remaining', '1', 'one decision, one left');
select pg_temp.throws($$select realisasi.mobility_approve(pg_temp.aid(18))$$, 'CONFLICT_OPEN', 'still blocked while one is open');
reset role;
select pg_temp.ok(exists (select 1 from realisasi.activity_log where activity_id = pg_temp.aid(13) and action = 'resolve_conflict'
                            and diff ->> 'not_counted' = 'RL-2026-0013'), 'decision logged on both activities');
select pg_temp.ok(exists (select 1 from realisasi.notifications where recipient_id = :'FTI' and kind = 'conflict_resolved'), 'losing unit notified');
-- the student kept on S-18 does not count anywhere until S-18 is verified; S-13 no longer counts them
select pg_temp.eq((select count(*) from realisasi.kpi_items('2026-08-01', '2026-10-01', '2026-10-01', 2) where kpi_code = '1.1' and ref_id like '%:B11227366'),
                  0::bigint, 'kept on an unverified activity: counted nowhere yet');
:as_mob
select realisasi.resolve_conflict(id, pg_temp.aid(18)) from realisasi.participant_conflicts where status = 'open';
select pg_temp.eq(realisasi.mobility_approve(pg_temp.aid(18)) ->> 'status', 'verified', 'S-18 approvable after all decisions');
reset role;
select pg_temp.eq((select string_agg(split_part(ref_id, ':', 1), ',') from realisasi.kpi_items('2026-08-01', '2026-10-01', '2026-10-01', 2)
                    where kpi_code = '1.1' and ref_id like '%:B11227366'), pg_temp.aid(18)::text, 'rule 2.1: counted once, on the kept activity');
-- a decision may be changed later
:as_mob
select realisasi.resolve_conflict(id, pg_temp.aid(13), 'Koreksi') from realisasi.participant_conflicts where nrp = 'B11227366' and pg_temp.aid(18) in (activity_a, activity_b);
reset role;
select pg_temp.eq((select string_agg(split_part(ref_id, ':', 1), ',') from realisasi.kpi_items('2026-08-01', '2026-10-01', '2026-10-01', 2)
                    where kpi_code = '1.1' and ref_id like '%:B11227366'), pg_temp.aid(13)::text, 'changed decision moves the student');

-- scan on submit: another unit claims S-10's students (FBE, 2026-08-03..09-18) with overlapping dates
:as_fti
insert into _ids select 'x', pg_temp.new_mobility(10, '2026-09-01', '2026-09-10', array['D31252983','B11240422']);
select pg_temp.eq((realisasi.submit_activity(pg_temp.id('x')) ->> 'conflicts_found')::int, 1, 'submit finds the overlapping claim of another unit');
reset role;
select pg_temp.eq((select nrp from realisasi.participant_conflicts where pg_temp.id('x') in (activity_a, activity_b) and status = 'open'), 'D31252983',
                  'conflict on the shared NRP only');
select pg_temp.ok(not exists (select 1 from realisasi.participant_conflicts where pg_temp.id('x') in (activity_a, activity_b) and nrp = 'B11240422'),
                  'B11240422 also in FTI''s S-13, same unit: no conflict (rule 2.2)');
select pg_temp.ok(exists (select 1 from realisasi.notifications where recipient_id = :'MOB' and kind = 'conflict_found' and created_at = realisasi.now_ts()),
                  'mobility team notified');
-- no conflict without overlapping dates
:as_fti
insert into _ids select 'y', pg_temp.new_mobility(10, '2026-09-20', '2026-09-25', array['D31252983']);
select pg_temp.eq((realisasi.submit_activity(pg_temp.id('y')) ->> 'conflicts_found')::int, 0, 'no overlap, no conflict');
-- a draft claims nobody
insert into _ids select 'z', pg_temp.new_mobility(10, '2026-09-01', '2026-09-10', array['D31243593']);
reset role;
select pg_temp.ok(not exists (select 1 from realisasi.participant_conflicts where pg_temp.id('z') in (activity_a, activity_b)), 'drafts are never in a conflict');
-- a revision that removes the student drops the open conflict
:as_mob
select realisasi.mobility_request_revision(pg_temp.id('x'), 'Hapus D31252983');
:as_fti
select realisasi.ensure_participant_draft(pg_temp.id('x'));
select realisasi.save_participants(pg_temp.id('x'), '[{"section":"internal","nrp":"B11240422"}]', '[]');
select realisasi.submit_activity(pg_temp.id('x'));
reset role;
select pg_temp.ok(not exists (select 1 from realisasi.participant_conflicts where pg_temp.id('x') in (activity_a, activity_b)),
                  'open conflict dropped when the student is removed');
-- non-mobility kegiatan never take part
select pg_temp.ok(not exists (select 1 from realisasi.participant_conflicts c join realisasi.activities a on a.id in (c.activity_a, c.activity_b)
                               where not realisasi.agenda_is_mobility(a.agenda_id)), 'only mobility kegiatan');
rollback;
