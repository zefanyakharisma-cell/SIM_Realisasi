-- 30_snapshots: AT-08, R-55..R-59, late additions, post-freeze changes, frozen read models.
\ir _helpers.inc

create temp table _s as select kind, id, values, frozen_at from realisasi.kpi_snapshots where academic_year_id = 1 and superseded_by is null;
create function pg_temp.sid(k text) returns uuid language sql as $$ select id from _s where kind::text = k $$;
grant select on _s to authenticated;
grant execute on all functions in schema pg_temp to authenticated;

select pg_temp.eq((select frozen_at from _s where kind = 'ganjil_ytd'), '2026-03-02 01:00+07'::timestamptz, 'Ganjil 25/26 frozen_at');
select pg_temp.eq((select frozen_at from _s where kind = 'genap_full_year'), '2026-08-30 01:00+07'::timestamptz, 'Genap 25/26 frozen_at');
select pg_temp.ok((select frozen_by is null from realisasi.kpi_snapshots where id = pg_temp.sid('ganjil_ytd')), 'scheduled freeze: frozen_by null');
select pg_temp.eq((select window_start || '..' || window_end || ' cut ' || cutoff_date from realisasi.kpi_snapshots where id = pg_temp.sid('ganjil_ytd')),
                  '2025-08-01..2026-01-31 cut 2026-03-02', 'Ganjil window (YTD)');
select pg_temp.eq((select window_start || '..' || window_end || ' cut ' || cutoff_date from realisasi.kpi_snapshots where id = pg_temp.sid('genap_full_year')),
                  '2025-08-01..2026-07-31 cut 2026-08-30', 'Genap window (full year)');

-- AT-08: S-19 (Ganjil 25/26, verified 2026-04-15) absent from Ganjil snapshot, present + late in Genap snapshot
select pg_temp.ok(not exists (select 1 from realisasi.kpi_snapshot_items where snapshot_id = pg_temp.sid('ganjil_ytd') and ref_id = pg_temp.aid(19)::text),
                  'AT-08 Ganjil snapshot has no S-19 item');
select pg_temp.eq((select string_agg(kpi_code || ':' || is_late_addition, ',' order by kpi_code) from realisasi.kpi_snapshot_items
                    where snapshot_id = pg_temp.sid('genap_full_year') and ref_id = pg_temp.aid(19)::text),
                  '1.19.S1:true,1.19.S8:true,base:true', 'AT-08 Genap snapshot S-19 items marked late');
select pg_temp.eq((select count(*) from realisasi.kpi_snapshot_items where snapshot_id = pg_temp.sid('genap_full_year') and is_late_addition and ref_type = 'activity'
                    and ref_id <> pg_temp.aid(19)::text), 0::bigint, 'only S-19 is a late activity');
select pg_temp.ok((select is_late_addition from realisasi.kpi_snapshot_items where snapshot_id = pg_temp.sid('genap_full_year') and kpi_code = '1.19.24'
                    and bucket = 'numerator' and ref_id = '106'), 'chain realized only through a late activity is late');
select pg_temp.ok(not (select is_late_addition from realisasi.kpi_snapshot_items where snapshot_id = pg_temp.sid('genap_full_year') and kpi_code = '1.19.24'
                    and bucket = 'numerator' and ref_id = '102'), 'chain already realized in Ganjil is not late');
select pg_temp.ok(realisasi.is_late_addition(pg_temp.aid(19)), 'is_late_addition(S-19)');
select pg_temp.eq((values -> 'kpi_1_19_s1')::text, '{"domestic": 1, "international": 3}', 'Ganjil 25/26 S1 values') from _s where kind = 'ganjil_ytd';
select pg_temp.eq((values -> 'kpi_1_1' ->> 'total')::int, 19, 'Genap 25/26 KPI 1.1 total') from _s where kind = 'genap_full_year';
-- items and values always agree
select pg_temp.eq((select count(*)::int from realisasi.kpi_snapshot_items where snapshot_id = s.id and kpi_code = '1.1'), (s.values #>> '{kpi_1_1,total}')::int,
                  'items = values (1.1) ' || s.kind) from _s s;
select pg_temp.eq((select count(*)::int from realisasi.kpi_snapshot_items where snapshot_id = s.id and kpi_code = '1.19.24' and bucket = 'denominator'),
                  (s.values #>> '{kpi_1_19_24,all,denominator}')::int, 'items = values (1.19.24) ' || s.kind) from _s s;
select pg_temp.ok((select settings_used ? 'grace_period_months' and not settings_used ? 'demo_today' from realisasi.kpi_snapshots where id = pg_temp.sid('ganjil_ytd')),
                  'R-56 settings_used stored (no demo_today)');

-- late additions / post-freeze change read models (viewer may read)
:as_view
select pg_temp.eq((select jsonb_agg(jsonb_build_object('code', r ->> 'code', 'counted', r -> 'counted_in_this_snapshot', 'prev', r ->> 'previous_snapshot_label')
                     order by r ->> 'code') from jsonb_array_elements(realisasi.snapshot_late_additions(pg_temp.sid('genap_full_year'))) r),
                  '[{"code":"RL-2026-0019","counted":true,"prev":"Ganjil 2025/2026 (YTD)"}]'::jsonb, 'AT-08 late additions of Genap snapshot');
select pg_temp.eq((select r -> 'kpi_codes' from jsonb_array_elements(realisasi.snapshot_late_additions(pg_temp.sid('genap_full_year'))) r),
                  '["1.19.24", "1.19.S1", "1.19.S8", "base"]'::jsonb, 'late addition KPI codes');
select pg_temp.eq(jsonb_array_length(realisasi.snapshot_late_additions(pg_temp.sid('ganjil_ytd'))), 0, 'first snapshot has no late additions');
select pg_temp.eq((select jsonb_agg(r ->> 'code' || '/' || (r ->> 'action') || '/' || (r -> 'diff' -> 'venue' ->> 1))
                     from jsonb_array_elements(realisasi.snapshot_post_freeze_changes(pg_temp.sid('genap_full_year'))) r),
                  '["RL-2026-0005/edit/Auditorium Gedung W PCU"]'::jsonb, 'S-05 edit listed as post-freeze change of Genap snapshot');
select pg_temp.eq(jsonb_array_length(realisasi.snapshot_post_freeze_changes(pg_temp.sid('ganjil_ytd'))), 0, 'none before the Ganjil freeze');
select pg_temp.eq((select jsonb_agg(r ->> 'label' order by r ->> 'frozen_at' desc) from jsonb_array_elements(realisasi.snapshot_list(1)) r),
                  '["Genap 2025/2026 (Setahun)", "Ganjil 2025/2026 (YTD)"]'::jsonb, 'snapshot_list newest first');
select pg_temp.eq((select r -> 'summary' from jsonb_array_elements(realisasi.snapshot_list(1)) r where r ->> 'kind' = 'genap_full_year'),
                  '{"kpi_1_1_total": 19, "kpi_1_19_s8_pct": 100.0, "kpi_1_19_24_pct": 63.2, "kpi_1_19_s1_international": 13}'::jsonb, 'snapshot summary');
select pg_temp.eq((select (r ->> 'late_additions') || '/' || (r ->> 'post_freeze_changes') || '/' || (r ->> 'frozen_by_name')
                     from jsonb_array_elements(realisasi.snapshot_list(1)) r where r ->> 'kind' = 'genap_full_year'), '1/1/Job terjadwal', 'archive counters');
select pg_temp.eq(realisasi.snapshot_detail(pg_temp.sid('genap_full_year')) -> 'values', (select values from _s where kind = 'genap_full_year'), 'snapshot_detail values');
-- frozen period reads come from the snapshot
select pg_temp.eq((realisasi.period_info(1, 'ganjil') ->> 'frozen')::boolean, true, 'period_info frozen');
select pg_temp.eq(realisasi.period_info(1, 'full') ->> 'label', 'Setahun 2025/2026', 'period label');
select pg_temp.eq(realisasi.dashboard(1, 'full') -> 'values', (select values from _s where kind = 'genap_full_year'), 'frozen dashboard = snapshot values');
select pg_temp.eq((realisasi.dashboard(1, 'full') ->> 'late_additions')::int, 1, 'frozen dashboard late additions');
select pg_temp.eq(realisasi.dashboard(2, 'full') #>> '{previous,ay_label}', '2025/2026', 'previous AY comparison');
select pg_temp.eq((realisasi.dashboard(2, 'full') #>> '{previous,kpi_1_1,total}')::int, 19, 'previous comes from the frozen Genap snapshot');
select pg_temp.eq((select count(*) from jsonb_array_elements(realisasi.kpi_drilldown(null, null, 'base', null, null, pg_temp.sid('ganjil_ytd')) -> 'rows')), 
                  (select count(*) from realisasi.kpi_snapshot_items where snapshot_id = pg_temp.sid('ganjil_ytd') and kpi_code = 'base'), 'drilldown by snapshot id');
select pg_temp.throws($$select realisasi.freeze_snapshot(2, 'ganjil_ytd')$$, 'AUTH_FORBIDDEN', 'viewer cannot freeze');
:as_fti
select pg_temp.throws(format('select realisasi.snapshot_detail(%L)', pg_temp.sid('ganjil_ytd')), 'AUTH_FORBIDDEN', 'submitter cannot open snapshot detail');
select pg_temp.eq((select count(*) from realisasi.kpi_snapshots), 0::bigint, 'RLS: submitter cannot select snapshots');
select pg_temp.eq((select r #>> '{summary,kpi_1_1_total}' from jsonb_array_elements(realisasi.snapshot_list(1)) r where r ->> 'kind' = 'genap_full_year'), '0',
                  'submitter snapshot_list summary scoped to own unit (FTI: no outbound/inbound in AY1? -> inbound S-02 counted)')
 where false;
select pg_temp.eq((select (r #>> '{summary,kpi_1_1_total}')::int from jsonb_array_elements(realisasi.snapshot_list(1)) r where r ->> 'kind' = 'genap_full_year'), 3,
                  'submitter snapshot summary = own unit (FTI: 3 inbound of S-02)');

-- R-55 already frozen; R-58 refreeze keeps the old snapshot (superseded) unchanged
:as_admin
select pg_temp.throws($$select realisasi.freeze_snapshot(1, 'ganjil_ytd')$$, 'R55_ALREADY_FROZEN', 'R-55 one live snapshot per period');
select pg_temp.throws(format('select realisasi.refreeze_snapshot(%L, %L)', pg_temp.sid('ganjil_ytd'), ' '), 'R58_REASON_REQUIRED', 'R-58 reason required');
:as_part
select pg_temp.throws(format('select realisasi.refreeze_snapshot(%L, %L)', pg_temp.sid('ganjil_ytd'), 'x'), 'AUTH_FORBIDDEN', 'only io_admin refreezes');
-- R-56: a settings change does not alter existing snapshots
:as_admin
select realisasi.update_settings('{"grace_period_months": 0}');
create temp table _new as select realisasi.refreeze_snapshot(pg_temp.sid('ganjil_ytd'), 'Koreksi data S-19') as id;
reset role;
select pg_temp.eq((select superseded_by from realisasi.kpi_snapshots where id = pg_temp.sid('ganjil_ytd')), (select id from _new), 'R-58 old snapshot superseded');
select pg_temp.eq((select values from realisasi.kpi_snapshots where id = pg_temp.sid('ganjil_ytd')), (select values from _s where kind = 'ganjil_ytd'),
                  'R-58/R-59 old values unchanged (AT-08 Ganjil values unchanged)');
select pg_temp.eq((select count(*) from realisasi.kpi_snapshot_items where snapshot_id = pg_temp.sid('ganjil_ytd') and ref_id = pg_temp.aid(19)::text), 0::bigint, 'old items unchanged');
select pg_temp.ok((select refreeze_reason = 'Koreksi data S-19' and frozen_by = :'ADMIN'::uuid and superseded_by is null from realisasi.kpi_snapshots where id = (select id from _new)),
                  'new live snapshot with reason');
select pg_temp.ok(exists (select 1 from realisasi.kpi_snapshot_items where snapshot_id = (select id from _new) and ref_id = pg_temp.aid(19)::text), 'refreeze includes S-19');
select pg_temp.eq((select (settings_used ->> 'grace_period_months')::int from realisasi.kpi_snapshots where id = (select id from _new)), 0, 'new snapshot records settings used');
select pg_temp.eq((select (settings_used ->> 'grace_period_months')::int from realisasi.kpi_snapshots where id = pg_temp.sid('genap_full_year')), 6, 'R-56 old settings_used unchanged');
:as_admin
select pg_temp.throws(format('select realisasi.refreeze_snapshot(%L, %L)', pg_temp.sid('ganjil_ytd'), 'again'), 'R58_NOT_LIVE', 'superseded snapshot cannot be refrozen');
select pg_temp.eq(jsonb_array_length(realisasi.snapshot_list(1)), 3, 'R-59 superseded snapshots stay listed');
select pg_temp.throws($$select realisasi.freeze_snapshot(9, 'ganjil_ytd')$$, 'NOT_FOUND', 'unknown AY');
reset role;
insert into realisasi.academic_years (id, label, start_date, end_date) values (9, '2030/2031', '2030-08-01', '2031-07-31');
:as_admin
select pg_temp.throws($$select realisasi.freeze_snapshot(9, 'ganjil_ytd')$$, 'R55_NO_SEMESTER', 'R55_NO_SEMESTER');
select pg_temp.throws($$select realisasi.period_info(9, 'full')$$, 'R55_NO_SEMESTER', 'period_info without semesters');

-- R-31 a post-freeze edit is flagged and appears as a post-freeze change of the next snapshot
:as_part
select realisasi.edit_verified_activity(pg_temp.aid(7), '{"venue":"Gedung Q PCU"}', 'Koreksi ruang');
reset role;
select pg_temp.ok(in_frozen_period, 'edit in frozen Genap window flagged') from realisasi.activity_log where activity_id = pg_temp.aid(7) and action = 'edit';
select pg_temp.eq((select values from realisasi.kpi_snapshots where id = pg_temp.sid('genap_full_year')), (select values from _s where kind = 'genap_full_year'),
                  'frozen values never change after edits');
rollback;
