-- 90_freeze: historical snapshots of AY 2025/2026 (run by the "scheduled job": auth.uid() is null, frozen_by null).
select realisasi.freeze_snapshot(1, 'ganjil_ytd', '2026-03-02 01:00+07')
 where not exists (select 1 from realisasi.kpi_snapshots where academic_year_id = 1 and kind = 'ganjil_ytd' and superseded_by is null);
select realisasi.freeze_snapshot(1, 'genap_full_year', '2026-08-30 01:00+07')
 where not exists (select 1 from realisasi.kpi_snapshots where academic_year_id = 1 and kind = 'genap_full_year' and superseded_by is null);

-- The seeded freezes notify at reset time; date those notifications (and their outbox rows) at the snapshot's frozen_at
-- and mark them read for io_admin, so the demo shows one notification per snapshot (requirements-review L-6). Idempotent.
update realisasi.notifications n
   set created_at = k.frozen_at,
       read_at = case when p.app_role = 'io_admin' then k.frozen_at + interval '1 day' end
  from realisasi.kpi_snapshots k, kerjasama.profiles p
 where n.kind = 'snapshot_frozen' and n.link = '/realisasi/laporan?report=arsip&snapshot=' || k.id
   and p.id = n.recipient_id and k.academic_year_id = 1 and n.created_at is distinct from k.frozen_at;
update realisasi.email_outbox o set created_at = k.frozen_at
  from realisasi.kpi_snapshots k
 where k.academic_year_id = 1 and o.body like '%/realisasi/laporan?report=arsip&snapshot=' || k.id
   and o.created_at is distinct from k.frozen_at;
