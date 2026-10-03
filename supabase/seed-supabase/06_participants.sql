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

-- 2. Participants ------------------------------------------------------------------------------------------------------
-- which prodi a unit's outbound students come from (nearest mapped unit up the tree; a faculty takes all its prodi)
drop table if exists pg_temp.h6_unit_prodi;
create temp table h6_unit_prodi (unit_id int, prodi text);
insert into h6_unit_prodi values
  (4, 'Manajemen'), (4, 'Akuntansi'), (4, 'International Business Management'), (4, 'Hotel Management'),
  (5, 'Manajemen'), (6, 'Akuntansi'), (7, 'International Business Management'), (8, 'Hotel Management'),
  (48, 'Magister Manajemen'), (51, 'Magister Manajemen'),
  (28, 'Informatika'), (28, 'Teknik Elektro'), (28, 'Teknik Industri'),
  (65, 'Teknik Elektro'), (67, 'Teknik Industri'), (68, 'Informatika'),
  (32, 'Desain Komunikasi Visual'), (32, 'Sastra Inggris'), (32, 'Ilmu Komunikasi'),
  (57, 'Ilmu Komunikasi'), (61, 'Sastra Inggris'), (63, 'Desain Komunikasi Visual'),
  (35, 'Arsitektur'), (35, 'Teknik Sipil'), (54, 'Arsitektur'), (55, 'Teknik Sipil'),
  (36, 'Pendidikan Guru Sekolah Dasar'), (73, 'Pendidikan Guru Sekolah Dasar'),
  (30, 'Kedokteran'), (76, 'Kedokteran');

create or replace function pg_temp.h6_prodi_of(p_unit int) returns text[] language sql stable as $$
  with recursive up(id, parent_id, depth) as (
    select u.id, u.parent_id, 0 from kerjasama.units u where u.id = p_unit
    union all select u.id, u.parent_id, up.depth + 1 from kerjasama.units u join up on u.id = up.parent_id where up.depth < 5)
  select array_agg(m.prodi) from h6_unit_prodi m
   where m.unit_id = (select up.id from up where exists (select 1 from h6_unit_prodi x where x.unit_id = up.id)
                       order by up.depth limit 1) $$;

-- Add students to an activity's current participant set until it holds p_target counted students (+ staff up to
-- p_staff). Returns how many students were added.
create or replace function pg_temp.h6_fill(p_activity uuid, p_target int, p_staff int default 0) returns int
language plpgsql as $$
declare a realisasi.activities; v_set uuid; v_section text; v_have int; v_need int; v_added int := 0;
        v_prodi text[]; v_partner text; v_ref int; v_years int;
begin
  select * into a from realisasi.activities where id = p_activity;
  if not found then return 0; end if;
  select id into v_set from realisasi.participant_set_versions where activity_id = p_activity order by version desc limit 1;
  if v_set is null then raise exception 'activity %: no participant set', a.code; end if;
  v_section := case when a.direction = 'outbound' then 'internal' else 'inbound' end;
  select count(*) into v_have from realisasi.participant_students where set_version_id = v_set and section::text = v_section;
  v_need := p_target - v_have;

  -- academic intake that is enrolled on the start date (the AY starting in August)
  v_ref := extract(year from a.start_date)::int - case when extract(month from a.start_date) < 8 then 1 else 0 end;
  if v_section = 'internal' then
    v_prodi := pg_temp.h6_prodi_of(a.submitter_unit_id);
    if v_prodi is null then raise exception 'activity %: no prodi mapping for unit %', a.code, a.submitter_unit_id; end if;
  else
    select p.name into v_partner from realisasi.activity_documents ad
      join kerjasama.document_partners dp on dp.document_id = ad.original_document_id and dp.is_lead
      join kerjasama.partners p on p.id = dp.partner_id
     where ad.activity_id = p_activity limit 1;
  end if;

  if v_need > 0 then
    with taken as (   -- students another unit claims on overlapping dates (any version, drafts included)
      select ps.nrp from realisasi.participant_students ps
        join realisasi.participant_set_versions v on v.id = ps.set_version_id
        join realisasi.activities o on o.id = v.activity_id
       where o.id <> a.id and o.submitter_unit_id <> a.submitter_unit_id
         and o.start_date <= a.end_date and a.start_date <= o.end_date),
    pick as (
      select s.* from mock_baak.students s
       where s.status <> 'inactive'
         and not exists (select 1 from realisasi.participant_students x where x.set_version_id = v_set and x.nrp = s.nrp)
         and s.nrp not in (select nrp from taken)
         and case when v_section = 'internal' then
                s.category = 'regular' and s.prodi_name = any(v_prodi)
                and s.intake_year <= v_ref
                and s.intake_year > v_ref - case when s.prodi_name = 'Magister Manajemen' then 2 else 4 end
                and s.intake_year < v_ref   -- no first-semester students abroad
              else
                s.category = 'inbound_exchange' and s.home_institution = v_partner
                and s.intake_year = extract(year from a.start_date)::int
              end
       order by exists (select 1 from realisasi.participant_students u where u.nrp = s.nrp), md5(s.nrp || a.code)
       limit v_need)
    insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
                home_institution, home_student_number, home_country_code)
    select v_set, v_section::realisasi.student_section, p.nrp, p.full_name, p.faculty_name, p.prodi_name,
           p.home_institution, case when v_section = 'inbound' then 'HS-' || right(p.nrp, 4) end, p.home_country_code
      from pick p;
    get diagnostics v_added = row_count;
    if v_added < v_need then
      raise exception 'activity %: only % of % eligible students available', a.code, v_added, v_need;
    end if;
  end if;

  if p_staff > (select count(*) from realisasi.participant_staff where set_version_id = v_set) then
    insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
    select v_set, e.employee_id, e.full_name, e.unit_name from mock_hr.employees e
     where e.status = 'active'
       and not exists (select 1 from realisasi.participant_staff x where x.set_version_id = v_set and x.employee_id = e.employee_id)
     order by md5(e.employee_id || a.code)
     limit p_staff - (select count(*) from realisasi.participant_staff where set_version_id = v_set);
  end if;
  return v_added;
end $$;

-- targets: counted students (outbound PETRA / inbound exchange) and staff companions per seeded mobility kegiatan,
-- in start-date order so earlier kegiatan choose first
select pg_temp.h6_fill(t.id::uuid, t.target, t.staff)
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
do $$
declare v text;
begin
  select string_agg(distinct x.nrp || ' (' || a.code || ' / ' || o.code || ')', ', ') into v
    from realisasi.activities a
    join realisasi.activities o on o.id > a.id and o.status <> 'draft' and o.submitter_unit_id <> a.submitter_unit_id
                               and o.start_date <= a.end_date and a.start_date <= o.end_date
    cross join lateral (select realisasi._claimed_nrps(a.id) as nrp) x
   where a.status <> 'draft' and x.nrp in (select realisasi._claimed_nrps(o.id))
     and not exists (select 1 from realisasi.participant_conflicts c
                      where c.nrp = x.nrp and c.activity_a = least(a.id, o.id) and c.activity_b = greatest(a.id, o.id));
  if v is not null then raise exception 'unintended student conflicts: %', v; end if;
end $$;

-- 3. Snapshots ---------------------------------------------------------------------------------------------------------
select realisasi.freeze_snapshot(3, 'ganjil_ytd', '2025-03-02 01:00+07')
 where exists (select 1 from realisasi.academic_years where id = 3)
   and not exists (select 1 from realisasi.kpi_snapshots where academic_year_id = 3 and kind = 'ganjil_ytd' and superseded_by is null);
select realisasi.freeze_snapshot(3, 'genap_full_year', '2025-08-30 01:00+07')
 where exists (select 1 from realisasi.academic_years where id = 3)
   and not exists (select 1 from realisasi.kpi_snapshots where academic_year_id = 3 and kind = 'genap_full_year' and superseded_by is null);

-- supersede system snapshots whose items differ from what the scheduled job would freeze now (oldest period first, so
-- later snapshots see the re-frozen previous period as their late-addition baseline)
do $$
declare s realisasi.kpi_snapshots;
begin
  for s in select k.* from realisasi.kpi_snapshots k where k.superseded_by is null and k.frozen_by is null order by k.frozen_at loop
    if exists ((select distinct i.kpi_code, i.bucket, i.ref_type, i.ref_id
                  from realisasi.kpi_items(s.window_start, s.window_end, s.cutoff_date, s.academic_year_id, s.frozen_at, null) i
                except
                select i.kpi_code, i.bucket, i.ref_type, i.ref_id from realisasi.kpi_snapshot_items i where i.snapshot_id = s.id)
               union all
               (select i.kpi_code, i.bucket, i.ref_type, i.ref_id from realisasi.kpi_snapshot_items i where i.snapshot_id = s.id
                except
                select distinct i.kpi_code, i.bucket, i.ref_type, i.ref_id
                  from realisasi.kpi_items(s.window_start, s.window_end, s.cutoff_date, s.academic_year_id, s.frozen_at, null) i)) then
      perform realisasi._freeze(s.academic_year_id, s.kind, s.frozen_at + interval '1 second', null,
                                'Data historis kegiatan dan peserta ditambahkan (seed).', s.id);
    end if;
  end loop;
end $$;

-- date system freezes' notifications (and outbox rows) at the snapshot's frozen_at, read for io_admin (as 90_freeze)
update realisasi.notifications n
   set created_at = k.frozen_at,
       read_at = case when p.app_role = 'io_admin' then k.frozen_at + interval '1 day' end
  from realisasi.kpi_snapshots k, kerjasama.profiles p
 where n.kind = 'snapshot_frozen' and n.link = '/realisasi/laporan?report=arsip&snapshot=' || k.id
   and p.id = n.recipient_id and k.frozen_by is null and n.created_at is distinct from k.frozen_at;
update realisasi.email_outbox o set created_at = k.frozen_at
  from realisasi.kpi_snapshots k
 where k.frozen_by is null and o.body like '%/realisasi/laporan?report=arsip&snapshot=' || k.id
   and o.created_at is distinct from k.frozen_at;
