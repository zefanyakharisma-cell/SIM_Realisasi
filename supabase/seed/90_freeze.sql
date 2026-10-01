-- 90_freeze: historical snapshots of AY 2025/2026 (run by the "scheduled job": auth.uid() is null, frozen_by null).
select realisasi.freeze_snapshot(1, 'ganjil_ytd', '2026-03-02 01:00+07')
 where not exists (select 1 from realisasi.kpi_snapshots where academic_year_id = 1 and kind = 'ganjil_ytd' and superseded_by is null);
select realisasi.freeze_snapshot(1, 'genap_full_year', '2026-08-30 01:00+07')
 where not exists (select 1 from realisasi.kpi_snapshots where academic_year_id = 1 and kind = 'genap_full_year' and superseded_by is null);
