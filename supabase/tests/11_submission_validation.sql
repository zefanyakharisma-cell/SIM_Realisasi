-- 11_submission_validation: R-04, R-07, R-08, R-09, R-11, R-12, R-13, R-14, R-15, R-16, R-17, R-18, R-19, R-22, AT-10, triggers,
-- Revisi V.1 (agenda as Jenis, direction, one kerja sama, SKS only for mobility, Unit Akademik only, mobility bundle).
\ir _helpers.inc

create temp table _ids (k text primary key, id uuid);
grant all on _ids to authenticated;
create function pg_temp.id(p_k text) returns uuid language sql as $$ select id from _ids where k = p_k $$;
create function pg_temp.payload(p_extra jsonb default '{}') returns jsonb language sql as $$
  select '{"name":"Student Exchange Uji Validasi","agenda_id":2,"direction":"outbound","start_date":"2026-09-01","end_date":"2026-09-05",
           "mode":"offline","venue":"Kyoto Institute of Technology","country_code":"JP","sks_recognized":3,
           "description":"Uji validasi pengajuan.","submitter_unit_id":10,"co_unit_ids":[11],"document_id":101,"sdg_ids":[4],
           "external_persons":[]}'::jsonb || p_extra $$;
-- upload a tiny PDF as IA/IR/mobility bundle the way /api/upload does (storage_put + register_activity_file)
create function pg_temp.upload(p_act uuid, p_kind text) returns jsonb language plpgsql as $$
declare v_path text := case when p_kind = 'mobility_bundle' then 'realisasi-transcripts/' else 'realisasi-files/' end
                       || p_act || '/' || p_kind || '/' || gen_random_uuid() || '.pdf';
        v_pdf bytea := convert_to('%PDF-1.4 test', 'UTF8');
begin
  perform realisasi.storage_put(v_path, 'application/pdf', v_pdf);
  return realisasi.register_activity_file(p_act, p_kind::realisasi.file_kind, v_path, upper(p_kind) || '.pdf', length(v_pdf), 'application/pdf');
end $$;
grant execute on all functions in schema pg_temp to authenticated;

-- ---- save_activity_draft validation ----------------------------------------------------------------
:as_view
select pg_temp.throws($$select realisasi.save_activity_draft(null, pg_temp.payload())$$, 'AUTH_FORBIDDEN', 'viewer cannot create');
:as_part
select pg_temp.throws($$select realisasi.save_activity_draft(null, pg_temp.payload())$$, 'AUTH_FORBIDDEN', 'io_staff cannot create');
-- Revisi V.1: SIM Realisasi is for Unit Akademik only
:as_admin
select pg_temp.throws($$select realisasi.save_activity_draft(null, pg_temp.payload('{"submitter_unit_id":2,"co_unit_ids":[]}'))$$, 'VALIDATION_INVALID',
                      'non-academic submitter unit refused');
select pg_temp.throws($$select realisasi.save_activity_draft(null, pg_temp.payload('{"co_unit_ids":[1]}'))$$, 'VALIDATION_INVALID',
                      'non-academic unit as Unit Lain yang Terlibat refused');
select pg_temp.throws($$select realisasi.save_activity_draft(null, pg_temp.payload('{"agenda_id":1}'))$$, 'VALIDATION_INVALID',
                      'amendment agenda is not a Jenis Kegiatan');
select pg_temp.throws($$select realisasi.save_activity_draft(null, pg_temp.payload('{"agenda_id":3}'))$$, 'VALIDATION_INVALID',
                      'inactive agenda cannot be newly chosen');
select pg_temp.throws($$select realisasi.save_activity_draft(null, pg_temp.payload('{"direction":"sideways"}'))$$, 'VALIDATION_INVALID',
                      'direction must be inbound/outbound');
select pg_temp.throws($$select realisasi.save_activity_draft(null, pg_temp.payload() - 'direction')$$, 'VALIDATION_REQUIRED', 'direction required');
select pg_temp.throws($$select realisasi.save_activity_draft(null, pg_temp.payload('{"document_id":[101,102]}'))$$, 'VALIDATION_INVALID',
                      'one kerja sama only');
:as_fti
select pg_temp.throws($$select realisasi.save_activity_draft(null, pg_temp.payload('{"submitter_unit_id":20}'))$$, 'R14_UNIT_NOT_ALLOWED', 'R-14 own unit only');
select pg_temp.throws($$select realisasi.save_activity_draft(null, pg_temp.payload('{"name":"  ","description":null}'))$$, 'VALIDATION_REQUIRED', 'required fields');
select pg_temp.eq(pg_temp.err_detail($$select realisasi.save_activity_draft(null, pg_temp.payload('{"name":"","description":null}'))$$),
                  '{"fields":["name","description"]}'::jsonb, 'VALIDATION_REQUIRED detail lists fields');
select pg_temp.throws($$select realisasi.save_activity_draft(null, pg_temp.payload('{"end_date":"2026-08-01"}'))$$, 'END_BEFORE_START', 'end before start');
select pg_temp.throws($$select realisasi.save_activity_draft(null, pg_temp.payload('{"mode":"teleport"}'))$$, 'VALIDATION_INVALID', 'invalid enum');
select pg_temp.throws($$select realisasi.save_activity_draft(null, pg_temp.payload('{"document_id":906}'))$$, 'R04_AGREEMENT_NOT_VALID', 'R-04 in_process never selectable');
select pg_temp.throws($$select realisasi.save_activity_draft(null, pg_temp.payload('{"document_id":907}'))$$, 'R04_AGREEMENT_NOT_VALID', 'R-04 rejected never selectable');
select pg_temp.throws($$select realisasi.save_activity_draft(null, pg_temp.payload('{"document_id":118}'))$$, 'R04_AGREEMENT_NOT_VALID', 'R-04 expired doc');
select pg_temp.throws($$select realisasi.save_activity_draft(null, pg_temp.payload('{"document_id":119}'))$$, 'R04_AGREEMENT_NOT_VALID', 'R-04 terminated doc');
select pg_temp.ok(pg_temp.err($$select realisasi.save_activity_draft(null, pg_temp.payload('{"document_id":118}'))$$) like '%001/MoU/PCU-SAXION/I/2018%', 'R-04 message names the document');
select pg_temp.throws($$select realisasi.save_activity_draft(null, pg_temp.payload('{"external_persons":[{"full_name":"A"}]}'))$$, 'VALIDATION_REQUIRED', 'external person fields');

-- R-04: archived (renewed) doc is selectable for dates inside its validity; auto-renewed always
select pg_temp.ok(exists (select 1 from realisasi.documents_valid_between('2025-10-01', '2025-10-10') where document_id = 904 and is_archived), 'R-04 archived 904 selectable for 2025 dates');
select pg_temp.ok(not exists (select 1 from realisasi.documents_valid_between('2026-05-01', '2026-05-10') where document_id = 904), '904 not valid after renewal');
select pg_temp.ok(exists (select 1 from realisasi.documents_valid_between('2026-05-01', '2026-05-10') where document_id = 903), 'auto-renewed 903 still selectable');
select pg_temp.ok(not exists (select 1 from realisasi.documents_valid_between('2020-01-01', '2030-01-01') where document_id in (906, 907)), 'in_process/rejected excluded');
select pg_temp.eq((select current_doc_number from realisasi.documents_valid_between('2025-10-01', '2025-10-10') where document_id = 904), '015/MoU/PCU-OU/IV/2026', 'current doc via chain');
select pg_temp.eq((select partners -> 0 ->> 'country_name' from realisasi.documents_valid_between('2026-09-01', '2026-09-05') where document_id = 101), 'Jepang', 'partners json');
select pg_temp.eq((select in_scope from realisasi.documents_valid_between('2026-09-01', '2026-09-05', 20) where document_id = 101), false, 'in_scope flag');

-- valid draft
insert into _ids select 'a', realisasi.save_activity_draft(null, pg_temp.payload());
reset role;
select pg_temp.eq(status::text, 'draft', 'draft created') from realisasi.activities where id = pg_temp.id('a');
select pg_temp.ok(code ~ '^RL-\d{4}-0\d{3}$' and code > 'RL-2026-0100', 'activity code from sequence') from realisasi.activities where id = pg_temp.id('a');
select pg_temp.eq(academic_year_id || '/' || semester_id, '2/3', 'trg derive_period: AY 2026/2027 Ganjil') from realisasi.activities where id = pg_temp.id('a');
select pg_temp.eq(reporting_deadline, '2026-10-05'::date, 'trg derive_deadline: end + 30') from realisasi.activities where id = pg_temp.id('a');
select pg_temp.eq((select count(*) from realisasi.activity_units where activity_id = pg_temp.id('a')), 2::bigint, 'submitter + co-unit');
select pg_temp.ok(agenda_id = 2 and direction = 'outbound' and sks_recognized = 3, 'agenda, direction and SKS stored') from realisasi.activities where id = pg_temp.id('a');
select pg_temp.eq((select chain_id from realisasi.activity_documents where activity_id = pg_temp.id('a')), 101, 'trg chain_id = chain_root');
select pg_temp.eq((select partner_name || '/' || country_code from realisasi.activity_partner_snapshot where activity_id = pg_temp.id('a')),
                  'Kyoto Institute of Technology/JP', 'trg partner snapshot (R-06)');
select pg_temp.ok((select count(*) = 1 from realisasi.event_groups g join realisasi.activities a on a.event_group_id = g.id where a.id = pg_temp.id('a')), 'R-32 own event group');
-- R-06: partner rename after linking does not change the snapshot
update public.partner set nama = 'KIT (renamed)' where id = 1;     -- SIMKS table (local stub)
select pg_temp.eq((select partner_name from realisasi.activity_partner_snapshot where activity_id = pg_temp.id('a')), 'Kyoto Institute of Technology', 'R-06 snapshot frozen');

-- R-05: out-of-scope warning does not block
:as_fbe
insert into _ids select 'oos', realisasi.save_activity_draft(null, pg_temp.payload('{"submitter_unit_id":20,"co_unit_ids":[],"agenda_id":35,"sks_recognized":2}'));
select pg_temp.eq(sks_recognized, null::numeric, 'SKS diakui only kept for mobility kegiatan') from realisasi.activities where id = pg_temp.id('oos');
select pg_temp.ok((select out_of_scope from realisasi.v_activity_list where id = pg_temp.id('oos')), 'R-05 out_of_scope flagged, not blocked');
select realisasi.save_activity_draft(pg_temp.id('oos'), '{"document_id":102}');
select pg_temp.eq((select array_agg(original_document_id) from realisasi.activity_documents where activity_id = pg_temp.id('oos')), array[102],
                  'changing the kerja sama replaces the single link');
select pg_temp.throws(format('select realisasi.save_activity_draft(%L, ''{"venue":"x"}'')', pg_temp.id('a')), 'NOT_FOUND', 'other unit cannot edit draft');
:as_inf
select pg_temp.throws(format('select realisasi.save_activity_draft(%L, ''{"venue":"x"}'')', pg_temp.id('a')), 'AUTH_FORBIDDEN', 'R-14 co-unit is read-only');
select pg_temp.throws(format('select realisasi.delete_draft(%L)', pg_temp.id('a')), 'AUTH_FORBIDDEN', 'co-unit cannot delete');

-- ---- checklist + submit -----------------------------------------------------------------------------------------
:as_fti
select pg_temp.eq((select string_agg(c ->> 'code', ',' order by o) from jsonb_array_elements(realisasi.submission_checklist(pg_temp.id('a'))) with ordinality x(c, o)),
  'R07_REQUIRED_FIELD,R07_AGREEMENT_REQUIRED,R04_AGREEMENT_NOT_VALID,R08_END_AFTER_TODAY,R09_NO_ACADEMIC_YEAR,R07_IA_REQUIRED,R07_IR_REQUIRED,R13_MOBILITY_BUNDLE_REQUIRED,R11_PARTICIPANTS_REQUIRED,R12_OUTBOUND_STUDENT_REQUIRED,R12_INBOUND_STUDENT_REQUIRED,R16_NRP_NOT_FOUND,R17_INBOUND_DATA_REQUIRED,R19_EMPLOYEE_NOT_FOUND,R21_NEW_VERSION_REQUIRED',
  'checklist codes in contract order');
select pg_temp.throws(format('select realisasi.submit_activity(%L)', pg_temp.id('a')), 'R07_IA_REQUIRED', 'R-07 IA required first');
select pg_temp.eq((select jsonb_agg(f ->> 'code') from jsonb_array_elements(pg_temp.err_detail(format('select realisasi.submit_activity(%L)', pg_temp.id('a'))) -> 'failures') f),
                  '["R07_IA_REQUIRED","R07_IR_REQUIRED","R13_MOBILITY_BUNDLE_REQUIRED","R11_PARTICIPANTS_REQUIRED","R12_OUTBOUND_STUDENT_REQUIRED"]'::jsonb, 'failures detail lists all');
select realisasi.save_activity_draft(pg_temp.id('a'), '{"venue":null}');
select pg_temp.throws(format('select realisasi.submit_activity(%L)', pg_temp.id('a')), 'R07_REQUIRED_FIELD', 'R-07 venue required at submit');
select realisasi.save_activity_draft(pg_temp.id('a'), '{"venue":"Kyoto Institute of Technology"}');

-- R-13 storage rules
select pg_temp.throws(format('select realisasi.storage_put(%L, %L, %L::bytea)', 'realisasi-files/' || pg_temp.id('a') || '/ia/x.txt', 'text/plain', '\x01'), 'R13_FILE_TYPE', 'R-13 type');
select pg_temp.throws(format('select realisasi.storage_put(%L, %L, %L::bytea)', 'realisasi-files/' || pg_temp.id('a') || '/ia/x.pdf', 'application/pdf', '\x0102'), 'R13_FILE_TYPE', 'R-13 PDF magic bytes');
select pg_temp.throws(format('select realisasi.storage_put(%L, %L, decode(repeat(''00'', 10485761), ''hex''))', 'realisasi-files/' || pg_temp.id('a') || '/ia/x.pdf', 'application/pdf'),
                      'R13_FILE_TOO_LARGE', 'R-13 size limit');
select pg_temp.throws(format('select realisasi.storage_put(%L, %L, %L::bytea)', 'other-bucket/' || pg_temp.id('a') || '/ia/x.pdf', 'application/pdf', '\x255044462d'), 'VALIDATION_INVALID', 'unknown bucket');
select pg_temp.throws(format('select realisasi.storage_put(%L, %L, %L::bytea)', 'realisasi-files/' || pg_temp.aid(17) || '/ia/x.pdf', 'application/pdf', '\x255044462d'), 'FILE_FORBIDDEN', 'other unit storage');
select pg_temp.throws(format('select realisasi.storage_put(%L, %L, %L::bytea)', 'realisasi-files/' || pg_temp.aid(13) || '/ia/x.pdf', 'application/pdf', '\x255044462d'), 'FILE_FORBIDDEN', 'verified activity files locked for unit');
select pg_temp.throws(format('select realisasi.register_activity_file(%L, ''ia'', %L, ''x'', 1, ''application/pdf'')', pg_temp.id('a'), 'realisasi-files/' || pg_temp.id('a') || '/ia/missing.pdf'),
                      'FILE_NOT_FOUND', 'register needs blob');
select pg_temp.eq((pg_temp.upload(pg_temp.id('a'), 'ia') ->> 'version')::int, 1, 'IA v1');
select pg_temp.eq((pg_temp.upload(pg_temp.id('a'), 'ia') ->> 'version')::int, 2, 'IA v2 replaces');
select pg_temp.eq((select count(*) from realisasi.activity_files where activity_id = pg_temp.id('a') and kind = 'ia' and is_current), 1::bigint, 'one current IA');
select pg_temp.upload(pg_temp.id('a'), 'ir');
-- mobility bundle (Revisi V.1 item 8): one PDF, personal-data bucket, versioned like IA/IR
select pg_temp.throws(format('select realisasi.storage_put(%L, ''image/png'', %L::bytea)', 'realisasi-transcripts/' || pg_temp.id('a') || '/mobility_bundle/x.png', '\x89504e47'),
                      'R13_FILE_TYPE', 'mobility bundle PDF only');
select pg_temp.throws(format('select realisasi.storage_put(%L, ''application/pdf'', %L::bytea)', 'realisasi-transcripts/' || pg_temp.id('a') || '/v1/x.pdf', '\x255044462d'),
                      'FILE_FORBIDDEN', 'no per-student transcript uploads any more');
select pg_temp.eq((pg_temp.upload(pg_temp.id('a'), 'mobility_bundle') ->> 'version')::int, 1, 'mobility bundle v1');
select pg_temp.eq((pg_temp.upload(pg_temp.id('a'), 'mobility_bundle') ->> 'version')::int, 2, 'mobility bundle v2 replaces');
select pg_temp.eq((select count(*) from realisasi.activity_files where activity_id = pg_temp.id('a') and kind = 'mobility_bundle' and is_current), 1::bigint, 'one current bundle');
select pg_temp.ok(realisasi.can_read_file((select storage_path from realisasi.activity_files where activity_id = pg_temp.id('a') and kind = 'mobility_bundle' and is_current)),
                  'unit reads its mobility bundle');
select pg_temp.throws(format('select realisasi.add_evidence_link(%L, ''ftp://x'', ''x'')', pg_temp.id('a')), 'VALIDATION_INVALID', 'evidence link must be http(s)');
select pg_temp.eq(realisasi.add_evidence_link(pg_temp.id('a'), 'https://petra.ac.id/berita/1', 'Berita') ->> 'href', 'https://petra.ac.id/berita/1', 'evidence link');
select pg_temp.throws(format('select realisasi.remove_activity_file(%s)', (select id from realisasi.activity_files where activity_id = pg_temp.id('a') and kind = 'ir')),
                      'STATE_INVALID', 'IA/IR cannot be removed');
select realisasi.remove_activity_file((select id from realisasi.activity_files where activity_id = pg_temp.id('a') and kind = 'evidence'));
select pg_temp.ok(not is_current, 'evidence removal = is_current false (no delete)') from realisasi.activity_files where activity_id = pg_temp.id('a') and kind = 'evidence';

-- participants: R-22, R-16 (AT-10), section rules, R-19, R-18 warnings
select pg_temp.throws(format($q$select realisasi.save_participants(%L, '[{"section":"internal","nrp":"D31240187"},{"section":"internal","nrp":"d31240187"}]', '[]')$q$, pg_temp.id('a')),
                      'R22_DUPLICATE_NRP', 'R-22 duplicate NRP');
select pg_temp.throws(format($q$select realisasi.save_participants(%L, '[]', '[{"employee_id":"PG204517"},{"employee_id":"PG204517"}]')$q$, pg_temp.id('a')),
                      'R22_DUPLICATE_EMPLOYEE', 'R-22 duplicate employee');
select pg_temp.throws(format($q$select realisasi.save_participants(%L, '[{"section":"internal","nrp":"D31240187"},{"section":"internal","nrp":"Z99999999"}]', '[]')$q$, pg_temp.id('a')),
                      'R16_NRP_NOT_FOUND', 'AT-10 unknown NRP rejected at entry');
select pg_temp.eq(pg_temp.err_detail(format($q$select realisasi.save_participants(%L, '[{"section":"internal","nrp":"D31240187"},{"section":"internal","nrp":"Z99999999"}]', '[]')$q$, pg_temp.id('a'))),
                  '{"rows":[{"section":"internal","index":1,"id":"Z99999999","code":"R16_NRP_NOT_FOUND"}]}'::jsonb, 'AT-10 row-level error detail');
select pg_temp.throws(format($q$select realisasi.save_participants(%L, '[{"section":"internal","nrp":"X01260012"}]', '[]')$q$, pg_temp.id('a')),
                      'R16_SECTION_MISMATCH', 'inbound NRP in internal section');
select pg_temp.throws(format($q$select realisasi.save_participants(%L, '[{"section":"inbound","nrp":"D31240187"}]', '[]')$q$, pg_temp.id('a')),
                      'R17_NOT_INBOUND', 'R-17 regular NRP in inbound section');
select pg_temp.throws(format($q$select realisasi.save_participants(%L, '[]', '[{"employee_id":"PG000000"}]')$q$, pg_temp.id('a')),
                      'R19_EMPLOYEE_NOT_FOUND', 'R-19 unknown employee');
select pg_temp.eq(realisasi.save_participants(pg_temp.id('a'),
   '[{"section":"internal","nrp":"D31240187","full_name":"ignored"},{"section":"internal","nrp":"B11200005"}]', '[{"employee_id":"PG803275"}]') -> 'warnings',
   '[{"id":"B11200005","status":"graduated","section":"internal"},{"id":"PG803275","status":"inactive","section":"staff"}]'::jsonb, 'R-18 warnings, not blocks');
select pg_temp.eq(full_name, 'Daniel Kurniawan', 'names copied from registry, client value ignored') from realisasi.participant_students where nrp = 'D31240187'
   and set_version_id = (select id from realisasi.participant_set_versions where activity_id = pg_temp.id('a'));

-- AT-10: an unknown NRP that slipped into the set blocks submit_activity
reset role;
insert into realisasi.participant_students (set_version_id, section, nrp, full_name)
select id, 'internal', 'Z99999999', 'Tidak Dikenal' from realisasi.participant_set_versions where activity_id = pg_temp.id('a');
:as_fti
select pg_temp.throws(format('select realisasi.submit_activity(%L)', pg_temp.id('a')), 'R16_NRP_NOT_FOUND', 'AT-10 unknown NRP blocks submit_activity');
select pg_temp.ok(pg_temp.err(format('select realisasi.submit_activity(%L)', pg_temp.id('a'))) like '%Z99999999%', 'AT-10 message names the NRP');
select pg_temp.eq(status::text, 'draft', 'still draft after blocked submit') from realisasi.activities where id = pg_temp.id('a');
select realisasi.save_participants(pg_temp.id('a'), '[{"section":"internal","nrp":"D31240187"},{"section":"internal","nrp":"B11200005"}]', '[{"employee_id":"PG803275"}]');

-- R-08 end date after today
select realisasi.save_activity_draft(pg_temp.id('a'), '{"end_date":"2026-12-20"}');
select pg_temp.throws(format('select realisasi.submit_activity(%L)', pg_temp.id('a')), 'R08_END_AFTER_TODAY', 'R-08');
select realisasi.save_activity_draft(pg_temp.id('a'), '{"end_date":"2026-09-05"}');

-- happy path
select pg_temp.eq(realisasi.submit_activity(pg_temp.id('a')) - 'id' - 'verified_at',
                  '{"status":"in_verification","mobility_status":"pending","is_late":false,"conflicts_found":0}'::jsonb,
                  'submit happy path result');
reset role;
select pg_temp.ok(submitted_at = realisasi.now_ts() and mobility_since = realisasi.now_ts(), 'submitted_at / since = now_ts') from realisasi.activities where id = pg_temp.id('a');
select pg_temp.eq(status::text, 'pending', 'participant v1 pending') from realisasi.participant_set_versions where activity_id = pg_temp.id('a');
select pg_temp.eq((select count(distinct recipient_id) from realisasi.notifications where kind = 'submission_received' and created_at = realisasi.now_ts()), 3::bigint,
                  'mobility team notified (perlu diproses)');
select pg_temp.ok(exists (select 1 from realisasi.email_outbox where to_email = 'io.mobility@demo.petra.ac.id' and created_at = realisasi.now_ts()), 'email_outbox row');
:as_fti
select pg_temp.throws(format('select realisasi.delete_draft(%L)', pg_temp.id('a')), 'R15_NOT_DRAFT', 'R-15 submitted cannot be deleted');
select pg_temp.throws(format('select realisasi.save_activity_draft(%L, ''{"venue":"x"}'')', pg_temp.id('a')), 'STATE_INVALID', 'no edit while in verification');

-- R-09 start outside configured years; R-11 mobility kegiatan without participants; R-12 inbound section; R-17
insert into _ids select 'b', realisasi.save_activity_draft(null, pg_temp.payload('{"start_date":"2025-07-20","end_date":"2025-07-25","direction":"inbound"}'));
select pg_temp.ok(academic_year_id is null and semester_id is null, 'draft outside calendar keeps NULL period') from realisasi.activities where id = pg_temp.id('b');
select pg_temp.eq((select c ->> 'ok' from jsonb_array_elements(realisasi.submission_checklist(pg_temp.id('b'))) c where c ->> 'code' = 'R09_NO_ACADEMIC_YEAR'), 'false', 'R-09 in checklist');
select pg_temp.eq((select c ->> 'ok' from jsonb_array_elements(realisasi.submission_checklist(pg_temp.id('b'))) c where c ->> 'code' = 'R11_PARTICIPANTS_REQUIRED'), 'false', 'R-11 mobility requires participants');
select realisasi.save_participants(pg_temp.id('b'), '[{"section":"internal","nrp":"B11227366"}]', '[]');
select pg_temp.eq((select c ->> 'ok' from jsonb_array_elements(realisasi.submission_checklist(pg_temp.id('b'))) c where c ->> 'code' = 'R12_INBOUND_STUDENT_REQUIRED'), 'false', 'R-12 inbound needs inbound student');
select realisasi.save_participants(pg_temp.id('b'), '[{"section":"inbound","nrp":"X01260012"}]', '[]');
select pg_temp.eq(home_institution || '/' || home_country_code, 'De La Salle University/PH', 'inbound defaults from BAAK') from realisasi.participant_students
 where set_version_id = (select id from realisasi.participant_set_versions where activity_id = pg_temp.id('b'));
select pg_temp.eq((select c ->> 'ok' from jsonb_array_elements(realisasi.submission_checklist(pg_temp.id('b'))) c where c ->> 'code' = 'R17_INBOUND_DATA_REQUIRED'), 'true', 'R-17 home institution present');
select realisasi.save_participants(pg_temp.id('b'), '[{"section":"inbound","nrp":"X01260012","home_institution":"  "}]', '[]');
select pg_temp.eq(home_institution, 'De La Salle University', 'blank home institution falls back to BAAK') from realisasi.participant_students
 where set_version_id = (select id from realisasi.participant_set_versions where activity_id = pg_temp.id('b'));
select pg_temp.upload(pg_temp.id('b'), 'mobility_bundle');

-- R-15 delete draft removes children and blobs
select realisasi.delete_draft(pg_temp.id('b'));
reset role;
select pg_temp.ok(not exists (select 1 from realisasi.activities where id = pg_temp.id('b'))
              and not exists (select 1 from realisasi.file_blobs where path like 'realisasi-transcripts/' || pg_temp.id('b') || '/%')
              and exists (select 1 from realisasi.file_blobs where path like 'realisasi-transcripts/' || pg_temp.id('a') || '/%')
              and not exists (select 1 from realisasi.participant_set_versions where activity_id = pg_temp.id('b')), 'R-15 draft hard-deleted with blobs');

-- R-10 late submission: S-23 draft (deadline 2026-09-13) -> LATE_NOTICE and is_late
:as_fsd
select pg_temp.ok((select (c ->> 'late')::boolean from jsonb_array_elements(realisasi.submission_checklist(pg_temp.aid(23))) c where c ->> 'code' = 'LATE_NOTICE'), 'LATE_NOTICE in checklist');
select pg_temp.ok((select c ->> 'message' from jsonb_array_elements(realisasi.submission_checklist(pg_temp.aid(23))) c where c ->> 'code' = 'LATE_NOTICE') like '%13 Sep 2026%', 'LATE_NOTICE date');
select pg_temp.throws($$select realisasi.submit_activity(pg_temp.aid(23))$$, 'R07_IR_REQUIRED', 'S-23 lacks IR');
select pg_temp.upload(pg_temp.aid(23), 'ir');
select pg_temp.eq((realisasi.submit_activity(pg_temp.aid(23)) ->> 'is_late')::boolean, true, 'R-10 late submission flagged');
select pg_temp.eq(mobility_status::text || '/' || status, 'not_required/verified', 'non-mobility (Kuliah Tamu) verified on submit') from realisasi.activities where id = pg_temp.aid(23);
rollback;
