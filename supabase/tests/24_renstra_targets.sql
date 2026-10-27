-- 24_renstra_targets: Target RENSTRA per unit / indicator / academic year (Pengaturan → Target RENSTRA).
\ir _helpers.inc

:as_admin
select pg_temp.eq(realisasi.set_renstra_targets(2, '1.1', '[{"unit_id": 0, "target": 120}, {"unit_id": 10, "target": 40}, {"unit_id": 11, "target": 15}]'), 3,
                  'admin sets three 1.1 targets');
select pg_temp.eq((select target from realisasi.renstra_targets where academic_year_id = 2 and renstra_key = '1.1' and unit_id = 10), 40::numeric,
                  'unit target stored');
select pg_temp.eq(realisasi.set_renstra_targets(2, '1.1', '[{"unit_id": 10, "target": 45}, {"unit_id": 11, "target": null}]'), 2,
                  'update one, clear one');
select pg_temp.eq((select jsonb_object_agg(unit_id, target) from realisasi.renstra_targets where academic_year_id = 2 and renstra_key = '1.1'),
                  '{"0": 120, "10": 45}'::jsonb, 'null target removes the row');
select pg_temp.eq(realisasi.set_renstra_targets(2, '1.19.S4', '[{"unit_id": 0, "target": 75.5}]'), 1, '1.19.S4 overall percentage');
select pg_temp.throws($$select realisasi.set_renstra_targets(2, '1.19.S4', '[{"unit_id": 10, "target": 50}]')$$, 'VALIDATION_INVALID',
                      '1.19.S4 has no per-unit target');
select pg_temp.throws($$select realisasi.set_renstra_targets(2, '1.19.S4', '[{"unit_id": 0, "target": 101}]')$$, 'VALIDATION_INVALID',
                      '1.19.S4 target is at most 100%');
select pg_temp.throws($$select realisasi.set_renstra_targets(2, '1.1', '[{"unit_id": 10, "target": -1}]')$$, 'VALIDATION_INVALID',
                      'negative target');
select pg_temp.throws($$select realisasi.set_renstra_targets(2, '1.1', '[{"unit_id": 10, "target": "abc"}]')$$, 'VALIDATION_INVALID',
                      'non-numeric target');
select pg_temp.throws($$select realisasi.set_renstra_targets(2, '1.1', '[{"unit_id": 999999, "target": 1}]')$$, 'VALIDATION_INVALID',
                      'unknown unit');
select pg_temp.throws($$select realisasi.set_renstra_targets(2, '1.19.S8', '[]')$$, 'VALIDATION_INVALID', 'unknown indicator');
select pg_temp.throws($$select realisasi.set_renstra_targets(9999, '1.1', '[]')$$, 'NOT_FOUND', 'unknown academic year');

-- everyone may read the targets (they appear in every role's report); only io_admin writes them
:as_view
select pg_temp.eq((select count(*) from realisasi.renstra_targets where academic_year_id = 2), 3::bigint, 'viewer reads targets');
select pg_temp.throws($$select realisasi.set_renstra_targets(2, '1.1', '[{"unit_id": 10, "target": 1}]')$$, 'AUTH_FORBIDDEN', 'viewer cannot set');
:as_mob
select pg_temp.throws($$select realisasi.set_renstra_targets(2, '1.1', '[{"unit_id": 10, "target": 1}]')$$, 'AUTH_FORBIDDEN', 'io_staff cannot set');
:as_fbe
select pg_temp.throws($$select realisasi.set_renstra_targets(2, '1.1', '[{"unit_id": 20, "target": 1}]')$$, 'AUTH_FORBIDDEN', 'submitter cannot set');
select pg_temp.ok(pg_temp.err($$insert into realisasi.renstra_targets (academic_year_id, renstra_key, unit_id, target) values (2, '1.1', 20, 1)$$) <> '',
                  'no direct insert');
rollback;
