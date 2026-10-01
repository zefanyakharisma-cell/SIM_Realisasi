-- 80_perf: H6/M10 regression timing on a scaled copy (+50 units, +1,500 documents, +6,200 verified activities), rolled back.
\ir _helpers.inc
-- deterministic scale-up: +50 units, +1500 docs (chains of 3), +6200 cloned verified activities
-- written into the SIMKS-shaped local stub tables (proposal id = no + 1000), read through the kerjasama.* adapter views
insert into public.unit (id, nama, id_jenis_unit) select 1000+i, 'Unit Uji '||i, 1 from generate_series(0,49) i;
insert into public.proposal_dokumen (id, jenis_kerjasama, tujuan_kerjasama, id_dokumen_sebelumnya)
select 11000+i, (case when i%5=0 then 'MoA' else 'MoU' end)::public.jenis_kerjasama, 'Dok '||i,
       case when i%3<>1 then 11000+i-1 end
  from generate_series(1,1500) i order by i;
insert into public.dokumen_kerja_sama (no, id_proposal_dokumen, no_dokumen, tanggal_mulai, tanggal_berakhir, status)
select 10000+i, 11000+i, 'DOC-'||i,
       date '2018-01-01' + ((i%3)*900 + (i/3)%400), date '2018-01-01' + ((i%3)*900 + (i/3)%400) + 899,
       case when i%3=0 then 'Aktif' else 'Diarsipkan' end
  from generate_series(1,1500) i order by i;
insert into realisasi.document_overrides (document_id, auto_renewed) select 10000+i, true from generate_series(1,1500) i where i%37=0;
insert into public.partner_pengusul (id_proposal_dokumen, id_partner, is_lead) select 11000+i, 1 + i%20, true from generate_series(1,1500) i;
insert into public.proposal_dokumen_unit select 11000+i, 1000 + i%50 from generate_series(1,1500) i;
insert into public.proposal_dokumen_unit select 11000+i, 10 from generate_series(1,1500) i where i%7=0;
create temp table _src as select row_number() over (order by code) rn, * from realisasi.activities where status='verified';
create temp table _map as
select gen_random_uuid() as nid, gen_random_uuid() as ngrp, s.id as sid, k, s.rn
  from _src s cross join generate_series(1, (6200 / (select count(*) from _src))::int + 1) k
 limit 6200;
insert into realisasi.event_groups (id) select ngrp from _map;
insert into realisasi.activities (id, code, name, type_id, start_date, end_date, mode, venue, city, country_code, description,
       submitter_unit_id, created_by, submitted_at, verified_at, partnership_status, mobility_status, event_group_id, partnership_since, mobility_since)
select m.nid, 'X-'||m.k||'-'||m.rn, a.name||' '||m.k, a.type_id, a.start_date, a.end_date, a.mode, a.venue, a.city, a.country_code, a.description,
       1000 + (m.k*7+m.rn)%50, a.created_by, a.submitted_at, a.verified_at, 'approved', a.mobility_status, m.ngrp, a.partnership_since, a.mobility_since
  from _map m join realisasi.activities a on a.id = m.sid;
insert into realisasi.activity_units select m.nid, 1000 + (m.k*7+m.rn)%50, true from _map m;
insert into realisasi.activity_documents (activity_id, original_document_id)
select m.nid, 10000 + 1 + ((m.k*13+m.rn*7)%1500) from _map m;
insert into realisasi.participant_set_versions (id, activity_id, version, status, reviewed_at)
select gen_random_uuid(), m.nid, 1, 'approved', a.verified_at from _map m join realisasi.activities a on a.id = m.sid
 where exists (select 1 from realisasi.participant_set_versions v where v.activity_id = m.sid and v.status='approved');
insert into realisasi.participant_students (set_version_id, section, nrp, full_name, home_institution)
select nv.id, s.section, s.nrp, s.full_name, s.home_institution
  from _map m join realisasi.participant_set_versions nv on nv.activity_id = m.nid
  join realisasi.participant_set_versions ov on ov.activity_id = m.sid and ov.status='approved'
  join realisasi.participant_students s on s.set_version_id = ov.id;
analyze;
create function pg_temp.ms(p_sql text) returns numeric language plpgsql as $$
declare t timestamptz := clock_timestamp();
begin
  execute p_sql;
  return round(extract(epoch from clock_timestamp() - t) * 1000, 1);
end $$;
grant execute on all functions in schema pg_temp to authenticated;

-- H6: by_unit (set-based) equals one compute_kpis per unit
create temp table _all as select realisasi.compute_kpis('2025-08-01', '2026-07-31', '2026-08-30', 1) as v;
select pg_temp.eq((select count(*) from jsonb_array_elements((select v -> 'by_unit' from _all))), 57::bigint, 'H6 by_unit covers seed + scaled units');
select pg_temp.ok(not exists (
  select 1 from jsonb_array_elements((select v -> 'by_unit' from _all)) b
   where (b - 'unit_id' - 'unit_name') <> (realisasi.compute_kpis('2025-08-01', '2026-07-31', '2026-08-30', 1, null, (b ->> 'unit_id')::int) - 'params')),
  'H6 every by_unit entry = compute_kpis(unit)');

-- H6 timings (scaled: baseline was ~6 s for the dashboard, ~3 s for compute_kpis)
:as_admin
select pg_temp.ok(pg_temp.ms($$select realisasi.dashboard(2, 'live', null)$$) < 2500, 'H6 admin dashboard < 2.5 s on the scaled copy (was ~6 s)');
select pg_temp.ok(pg_temp.ms($$select realisasi.agreement_flags(1)$$) < 100, 'H6 agreement_flags < 100 ms');
reset role;
select pg_temp.ok(pg_temp.ms($$select realisasi.compute_kpis('2025-08-01', '2026-07-31', '2026-08-30', 1)$$) < 1500, 'H6 compute_kpis (full year, all units) < 1.5 s (was ~3 s)');
-- M10: RLS-filtered list reads
:as_fti
select pg_temp.ok(pg_temp.ms($$select count(*) from realisasi.v_activity_list$$) < 250, 'M10 v_activity_list as FTI < 250 ms');
select pg_temp.ok(pg_temp.ms($$select count(*) from realisasi.participant_students$$) < 100, 'M10 participant_students as FTI < 100 ms');
:as_view
select pg_temp.ok(pg_temp.ms($$select count(*) from realisasi.v_activity_list$$) < 250, 'M10 v_activity_list as viewer < 250 ms');
rollback;
