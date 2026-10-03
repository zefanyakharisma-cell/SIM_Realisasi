-- seed-supabase/06_participants (simks-partnership): realistic Jumlah Peserta for the seeded mobility kegiatan, so
-- RENSTRA 1.1 (Jumlah mahasiswa Inbound & Outbound, R-38) and the International Awards boards have real numbers.
-- Written only into realisasi.*. Idempotent: every kegiatan is
-- filled UP TO a target size (a re-run adds nothing), snapshots are re-frozen only when stale.
--
-- 1. The student pool comes from 02b_registry_more.sql (mock BAAK + 735 PETRA / + 378 inbound students).
-- 2. Participants: each seeded mobility kegiatan (04: b5…, 05: c5…) gets students added to its CURRENT participant set
--    version until it reaches its target. Outbound kegiatan take PETRA students (section internal) from the submitting
--    unit's prodi, enrolled and at most in their 4th year (2nd for Magister) on the start date; inbound kegiatan take
--    exchange students (section inbound) whose home institution is the kegiatan's partner, same intake year. Staff and
--    external persons are not counted in RENSTRA 1.1 (R-19, R-20), so only a few staff companions are added.
--    A student is never picked when another unit claims them on overlapping dates (rule 2.1); the only conflict stays
--    the deliberate one from 04 (RL-2026-0006 / RL-2026-0013). Kegiatan not created by the seeds are never touched.
-- 3. Snapshots: AY 2024/2025 is frozen like the scheduled job would have (2025-03-02, 2025-08-30); any live system
--    snapshot that no longer matches what the job would have frozen (missing kegiatan or participants) is superseded by
--    a system re-freeze at its as-of time (+1 s so it is the latest). On a fresh deploy 90_freeze runs afterwards.

\ir lib/activity_helpers.inc

-- 2. Participants ------------------------------------------------------------------------------------------------------
-- targets: counted students (outbound PETRA / inbound exchange) and staff companions per seeded mobility kegiatan,
-- in start-date order so earlier kegiatan choose first
select pg_temp.h_fill(t.id::uuid, t.target, t.staff)
  from (values
    -- AY 2024/2025
    ('c5000000-0000-4000-8000-000000000201',  4, 0),   -- Student Exchange Kyoto Sangyo (IBM)
    ('c5000000-0000-4000-8000-000000000204', 15, 2),   -- Cultural Exchange Youth Festival (DKV)
    ('c5000000-0000-4000-8000-000000000207', 20, 2),   -- Spring Japanese Short Program (SBM)
    ('c5000000-0000-4000-8000-000000000212',  3, 0),   -- Credit Transfer Kyoto Sangyo (IBM)
    ('c5000000-0000-4000-8000-000000000251',  9, 0),   -- Inbound Exchange from Kyoto Sangyo, Genap (SBM)
    ('c5000000-0000-4000-8000-000000000209',  6, 1),   -- Magang Kyoto (Informatika)
    ('c5000000-0000-4000-8000-000000000252', 14, 1),   -- Inbound Summer Program from Kyoto Sangyo (Hotel Management)
    -- AY 2025/2026
    ('b5000000-0000-4000-8000-000000000001',  6, 0),   -- RL-2026-0001 Student Exchange Kyoto Sangyo (SBM)
    ('c5000000-0000-4000-8000-000000000216', 10, 0),   -- Inbound Exchange from Kyoto Sangyo (SBM)
    ('c5000000-0000-4000-8000-000000000218',  4, 0),   -- Student Exchange Yonsei (Manajemen)
    ('c5000000-0000-4000-8000-000000000220', 16, 1),   -- Thai Hospitality Immersion (Hotel Management)
    ('c5000000-0000-4000-8000-000000000221',  8, 1),   -- Magang Astra (Teknik Industri)
    ('c5000000-0000-4000-8000-000000000225',  3, 0),   -- Double Degree NTU (Magister Manajemen)
    ('c5000000-0000-4000-8000-000000000228',  4, 0),   -- Student Exchange NUS (Informatika)
    ('c5000000-0000-4000-8000-000000000230', 24, 2),   -- Studi Ekskursi Kyoto-Osaka (Arsitektur)
    ('c5000000-0000-4000-8000-000000000231', 14, 1),   -- Bangkok Summer Business Camp (IBM)
    ('b5000000-0000-4000-8000-000000000006', 18, 2),   -- RL-2026-0006 Summer Program Chulalongkorn (SBM)
    ('b5000000-0000-4000-8000-000000000013',  6, 0),   -- RL-2026-0013 same program (Manajemen), in the queue
    -- AY 2026/2027
    ('c5000000-0000-4000-8000-000000000243',  5, 1),   -- Magang Astra (Teknik Elektro)
    ('b5000000-0000-4000-8000-000000000007',  8, 0),   -- RL-2026-0007 Inbound Exchange NUS (Manajemen)
    ('c5000000-0000-4000-8000-000000000248',  9, 0),   -- Inbound Exchange Chulalongkorn (SBM), in the queue
    ('c5000000-0000-4000-8000-000000000236',  8, 0),   -- Inbound Exchange Yonsei (Manajemen), draft
    ('c5000000-0000-4000-8000-000000000238', 20, 2),   -- Short Program NUS Smart City (FTI), in the queue
    ('c5000000-0000-4000-8000-000000000242',  6, 1),   -- Academic Exchange Ateneo (FKIP), revision requested
    ('b5000000-0000-4000-8000-000000000011',  5, 0)    -- RL-2026-0011 Student Exchange NUS (SBM), in the queue
  ) t(id, target, staff)
 where exists (select 1 from realisasi.activities a where a.id = t.id::uuid);

-- the only student conflicts are the ones the seeds create on purpose (04: RL-2026-0006 / RL-2026-0013)
select pg_temp.h_assert_no_conflicts();

-- 3. Snapshots ---------------------------------------------------------------------------------------------------------
select realisasi.freeze_snapshot(3, 'ganjil_ytd', '2025-03-02 01:00+07')
 where exists (select 1 from realisasi.academic_years where id = 3)
   and not exists (select 1 from realisasi.kpi_snapshots where academic_year_id = 3 and kind = 'ganjil_ytd' and superseded_by is null);
select realisasi.freeze_snapshot(3, 'genap_full_year', '2025-08-30 01:00+07')
 where exists (select 1 from realisasi.academic_years where id = 3)
   and not exists (select 1 from realisasi.kpi_snapshots where academic_year_id = 3 and kind = 'genap_full_year' and superseded_by is null);

-- supersede system snapshots whose items differ from what the scheduled job would freeze now
select pg_temp.h_refreeze_stale('Data historis kegiatan dan peserta ditambahkan (seed).');
select pg_temp.h_date_freeze_notifications();
