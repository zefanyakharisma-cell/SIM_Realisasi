-- LIVE PATCH for simks-partnership (2026-10-03), same text as the migrations of this commit:
--   0001_kerjasama_adapter.sql kerjasama.units (Fakultas -> Prodi -> Program by depth) and
--   0014_reads.sql International Awards (prodi list computed once per call).
-- Only for an install made before this commit; a fresh install/reset already has it. One transaction.
begin;
create or replace view kerjasama.units as
select u.id,
       -- display form: SIMKS short names "Prodi X" read as "Program Studi X" (SIMKS itself unchanged)
       regexp_replace(u.nama::text, '^\s*Prodi\s+', 'Program Studi ', 'i') as name,
       u.id_parent_unit as parent_id,
       case
         when u.id_jenis_unit is distinct from 1 then 'up'
         when u.id_parent_unit is null and exists (
                select 1 from public.unit c join public.unit g on g.id_parent_unit = c.id
                 where c.id_parent_unit = u.id and c.id_jenis_unit = 1 and g.id_jenis_unit = 1) then 'up'
         when lv.parent_academic and lv.grandparent_academic then 'program'
         when lv.parent_academic then 'prodi'
         else 'faculty'
       end as kind,
       coalesce(u.is_active, true) as is_active,
       (u.id_jenis_unit = 1) is true as is_academic   -- jenis_unit 1 = Unit Akademik (Revisi V.1: only these submit)
  from public.unit u
  left join public.unit pu on pu.id = u.id_parent_unit
  left join public.unit gpu on gpu.id = pu.id_parent_unit
  -- an academic ancestor counts as a level unless it is the academic university root (see the 'up' rule above)
  cross join lateral (
    select coalesce(pu.id_jenis_unit = 1 and not rt.pu_root, false) as parent_academic,
           coalesce(gpu.id_jenis_unit = 1 and not rt.gpu_root, false) as grandparent_academic
      from (select
              (pu.id_parent_unit is null and exists (
                 select 1 from public.unit c join public.unit g on g.id_parent_unit = c.id
                  where c.id_parent_unit = pu.id and c.id_jenis_unit = 1 and g.id_jenis_unit = 1)) as pu_root,
              (gpu.id_parent_unit is null and exists (
                 select 1 from public.unit c join public.unit g on g.id_parent_unit = c.id
                  where c.id_parent_unit = gpu.id and c.id_jenis_unit = 1 and g.id_jenis_unit = 1)) as gpu_root
           ) rt
  ) lv;

create or replace function realisasi._prodi_norm(p_name text) returns text
language sql immutable set search_path = realisasi, extensions, public, pg_temp as $$
  select lower(regexp_replace(btrim(p_name), '^(prodi|program studi)\s+', '', 'i'))
$$;
revoke all on function realisasi._prodi_norm(text) from public;

create or replace function realisasi._awards_students(p_direction text, p_intl boolean) returns jsonb
language plpgsql volatile security definer set search_path = realisasi, extensions, public, pg_temp as $$
begin
  return (select coalesce(jsonb_agg(to_jsonb(x) order by x.total desc, x.unit_name), '[]'::jsonb) from (
    select unit_id, unit_name, jd_dd, student_exchange, short_summer, short_international,
           jd_dd + student_exchange + short_summer + short_international as total
      from (
        select u.id as unit_id, u.name as unit_name,
               count(*) filter (where r.mobility_category = 'jd_dd')::int as jd_dd,
               count(*) filter (where r.mobility_category = 'student_exchange')::int as student_exchange,
               count(*) filter (where r.mobility_category = 'short_summer')::int as short_summer,
               count(*) filter (where r.mobility_category = 'other_mobility' and a.end_date - a.start_date + 1 < 14)::int
                 as short_international
          from _aw_items i
          join realisasi.activities a on a.id = i.activity_id
          join realisasi.agenda_rules r on r.agenda_id = a.agenda_id
          left join lateral (select s.prodi_name from realisasi.participant_students s
                              where s.set_version_id = realisasi._counts_version(a.id) and s.nrp = split_part(i.ref_id, ':', 2)
                              order by s.id limit 1) st on true
          join _aw_prodi u on u.id = coalesce((select p.id from _aw_prodi p where p.norm = realisasi._prodi_norm(st.prodi_name)
                                                order by p.id limit 1),
                                               (select p.id from _aw_prodi p where p.id = a.submitter_unit_id))
         where i.kpi_code = '1.1' and i.bucket = p_direction and u.in_scope
           and (p_intl is null
                or p_intl = coalesce(a.country_code <> 'ID',
                                     exists (select 1 from realisasi.activity_partner_snapshot ps
                                              where ps.activity_id = a.id and ps.country_code <> 'ID')))
         group by u.id, u.name) y
     where jd_dd + student_exchange + short_summer + short_international > 0) x);
end $$;
revoke all on function realisasi._awards_students(text, boolean) from public;

create or replace function realisasi.international_awards(p_ay_id int default null, p_period text default 'ytd', p_unit_id int default null)
returns jsonb
language plpgsql volatile security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare c realisasi.period_ctx; v_unit int;
begin
  perform realisasi._require_uid();
  v_unit := realisasi._forced_unit(p_unit_id);
  c := realisasi._period_ctx(p_ay_id, coalesce(p_period, 'ytd'));
  if to_regclass('pg_temp._aw_items') is null then
    create temp table _aw_items (su int, kpi_code text, bucket text, ref_type text, ref_id text, activity_id uuid, is_intl boolean) on commit drop;
    create temp table _aw_prodi (id int primary key, name text, norm text, in_scope boolean) on commit drop;
  end if;
  truncate _aw_items, _aw_prodi;
  insert into _aw_items
  select * from realisasi._kpi_items_scoped(c.window_start, c.window_end, c.cutoff, c.frozen_at, 'university', null, c.grace_months) i
   where i.kpi_code in ('1.1','base');
  -- the rankable units: Program Studi only; a unit scope keeps that prodi or the prodis of that faculty
  insert into _aw_prodi
  select u.id, u.name, realisasi._prodi_norm(u.name), v_unit is null or u.id = v_unit or u.parent_id = v_unit
    from kerjasama.units u where u.kind = 'prodi';

  return jsonb_build_object('period', realisasi._period_json(c), 'scope', realisasi._scope_json(v_unit),
    'inbound', realisasi._awards_students('inbound', null),
    'outbound_domestic', realisasi._awards_students('outbound', false),
    'outbound_international', realisasi._awards_students('outbound', true),
    'initiatives', coalesce((select jsonb_agg(to_jsonb(x) order by x.total desc, x.unit_name) from (
        select a.submitter_unit_id as unit_id, u.name as unit_name,
               count(*) filter (where a.direction = 'inbound' and r.mobility_category is not null)::int as inbound,
               count(*) filter (where a.direction = 'outbound' and r.mobility_category is not null)::int as outbound,
               count(*) filter (where r.mobility_category is null)::int as activities,
               count(*)::int as total
          from _aw_items i
          join realisasi.activities a on a.id = i.activity_id
          join _aw_prodi u on u.id = a.submitter_unit_id and u.in_scope
          left join realisasi.agenda_rules r on r.agenda_id = a.agenda_id
         where i.kpi_code = 'base'
           and (coalesce(a.country_code <> 'ID', false)
                or exists (select 1 from realisasi.activity_partner_snapshot ps where ps.activity_id = a.id and ps.country_code <> 'ID'))
         group by a.submitter_unit_id, u.name) x), '[]'::jsonb));
end $$;

drop function if exists realisasi._prodi_unit(text, int), realisasi._awards_in_scope(int, int),
                          realisasi._awards_students(int, text, boolean);
commit;
