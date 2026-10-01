-- 0012_kpi: single source of KPI truth (CONTRACTS §4.2/§4.3, Rules §6).

create function realisasi._kpi_items(p_from date, p_to date, p_cutoff date, p_ay_id int,
                                     p_as_of timestamptz, p_unit_id int, p_grace_months int)
returns table(kpi_code text, bucket text, ref_type text, ref_id text, activity_id uuid)
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
with qa as (            -- qualifying activities (verified as of p_as_of, unit scope)
  select a.id, a.code, a.start_date, a.verified_at, a.event_group_id,
         t.direction as t_direction, t.counts_as_mobility, t.counts_for_s1,
         exists (select 1 from realisasi.activity_partner_snapshot ps
                  where ps.activity_id = a.id and ps.country_code <> 'ID') as intl
    from realisasi.activities a join realisasi.activity_types t on t.id = a.type_id
   where a.status = 'verified' and a.verified_at <= coalesce(p_as_of, realisasi.now_ts())
     and (p_unit_id is null or exists (select 1 from realisasi.activity_units au
                                        where au.activity_id = a.id and au.unit_id = p_unit_id))
), win as (
  select *, case when p_unit_id is null then event_group_id else id end as dedupe_key
    from qa where start_date between p_from and p_to
), stud as (
  select w.id, w.code, w.verified_at, w.dedupe_key, w.t_direction::text as bucket, s.nrp
    from win w
    join realisasi.participant_set_versions v on v.activity_id = w.id and v.status = 'approved'
    join realisasi.participant_students s on s.set_version_id = v.id
         and ((w.t_direction = 'outbound' and s.section = 'internal') or (w.t_direction = 'inbound' and s.section = 'inbound'))
   where w.counts_as_mobility
), k11 as (
  select distinct on (bucket, nrp, dedupe_key) '1.1'::text, bucket, 'participant'::text, id::text || ':' || nrp, id
    from stud order by bucket, nrp, dedupe_key, verified_at, code
), s1grp as (
  select dedupe_key, bool_or(intl) as gintl from win where counts_for_s1 group by dedupe_key
), ks1 as (
  select distinct on (w.dedupe_key) '1.19.S1'::text,
         case when g.gintl then 'international' else 'domestic' end, 'activity'::text, w.id::text, w.id
    from win w join s1grp g on g.dedupe_key = w.dedupe_key
   where w.counts_for_s1 and w.intl = g.gintl
   order by w.dedupe_key, w.verified_at, w.code
), ks8 as (
  select distinct on (dedupe_key) '1.19.S8'::text, 'reported'::text, 'activity'::text, id::text, id
    from win where intl order by dedupe_key, verified_at, code
), kknown as (
  select '1.19.S8'::text, 'unmatched_known'::text, 'known_activity'::text, k.id::text, null::uuid
    from realisasi.known_activities k
   where k.status = 'unmatched' and k.is_international and k.activity_date between p_from and p_to
     and k.created_at <= coalesce(p_as_of, realisasi.now_ts())
     and (p_unit_id is null or k.unit_id = p_unit_id)
), kbase as (
  select 'base'::text, 'verified_activity'::text, 'activity'::text, id::text, id from win
), ch as (
  select c.chain_id,
         (not c.auto_renewed and c.chain_start > (p_cutoff - make_interval(months => p_grace_months))::date) as in_grace
    from realisasi.v_chains c
   where c.chain_start <= p_cutoff and (c.auto_renewed or c.chain_end >= p_from)
     and (p_unit_id is null or exists (select 1 from public.document_scope_units su
                                        where su.document_id = any(c.document_ids) and su.unit_id = p_unit_id))
), realized as (
  select distinct ad.chain_id from realisasi.activity_documents ad join qa on qa.id = ad.activity_id
   where qa.start_date between p_from and p_cutoff
), k24 as (
  select '1.19.24'::text, 'denominator'::text, 'chain'::text, chain_id::text, null::uuid from ch where not in_grace
  union all
  select '1.19.24', 'numerator', 'chain', ch.chain_id::text, null::uuid from ch join realized r using (chain_id) where not ch.in_grace
  union all
  select '1.19.24', 'grace_excluded', 'chain', chain_id::text, null::uuid from ch where in_grace
)
select * from k11 union all select * from ks1 union all select * from k24
union all select * from ks8 union all select * from kknown union all select * from kbase
$$;

create function realisasi.kpi_items(p_from date, p_to date, p_cutoff date, p_ay_id int,
                                    p_as_of timestamptz default null, p_unit_id int default null)
returns table(kpi_code text, bucket text, ref_type text, ref_id text, activity_id uuid)
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select * from realisasi._kpi_items(p_from, p_to, p_cutoff, p_ay_id, p_as_of, p_unit_id,
                                     coalesce(realisasi.setting_int('grace_period_months'), 6))
$$;

create function realisasi._pct(n numeric, d numeric) returns numeric
language sql immutable set search_path = realisasi, public, extensions, pg_temp as $$
  select round(100.0 * n / nullif(d, 0), 1)
$$;

-- KPI values from a set of items (internal; p_items = jsonb array of kpi_items rows)
create function realisasi._kpi_values(p_items jsonb, p_from date, p_to date, p_ay_id int, p_unit_id int) returns jsonb
language plpgsql volatile security definer set search_path = realisasi, public, extensions, pg_temp as $$
declare v_sem jsonb; v_24 jsonb; v_s8r int; v_s8u int; v_base uuid[]; v_charts jsonb; v_univ boolean := p_unit_id is null;
begin
  if to_regclass('pg_temp._kv_items') is null then
    create temp table _kv_items (kpi_code text, bucket text, ref_type text, ref_id text, activity_id uuid) on commit drop;
  end if;
  truncate _kv_items;
  insert into _kv_items select * from jsonb_to_recordset(coalesce(p_items, '[]'::jsonb))
    as i(kpi_code text, bucket text, ref_type text, ref_id text, activity_id uuid);

  select coalesce(jsonb_agg(jsonb_build_object('semester_id', s.id, 'term', s.term,
           'label', initcap(s.term::text) || ' ' || ay.label,
           'inbound', (select count(*) from _kv_items i join realisasi.activities a on a.id = i.activity_id
                        where i.kpi_code = '1.1' and i.bucket = 'inbound' and a.start_date between s.start_date and s.end_date),
           'outbound', (select count(*) from _kv_items i join realisasi.activities a on a.id = i.activity_id
                        where i.kpi_code = '1.1' and i.bucket = 'outbound' and a.start_date between s.start_date and s.end_date))
           order by s.start_date), '[]'::jsonb)
    into v_sem
    from realisasi.semesters s join realisasi.academic_years ay on ay.id = s.academic_year_id
   where (p_ay_id is null or s.academic_year_id = p_ay_id) and s.start_date <= p_to and s.end_date >= p_from;

  select jsonb_object_agg(sc.scope, jsonb_build_object(
           'numerator', sc.n, 'denominator', sc.d, 'grace_excluded', sc.g, 'pct', realisasi._pct(sc.n, sc.d)))
    into v_24
    from (select s.scope,
                 count(*) filter (where i.bucket = 'numerator') as n,
                 count(*) filter (where i.bucket = 'denominator') as d,
                 count(*) filter (where i.bucket = 'grace_excluded') as g
            from (values ('all'), ('international'), ('domestic')) s(scope)
            left join (select i.*, c.is_international from _kv_items i
                         left join realisasi.v_chains c on c.chain_id = i.ref_id::int
                        where i.kpi_code = '1.19.24') i
                   on s.scope = 'all' or (s.scope = 'international') = coalesce(i.is_international, false)
           group by s.scope) sc;

  select count(*) filter (where bucket = 'reported'), count(*) filter (where bucket = 'unmatched_known')
    into v_s8r, v_s8u from _kv_items where kpi_code = '1.19.S8';
  select coalesce(array_agg(activity_id), '{}') into v_base from _kv_items where kpi_code = 'base';

  v_charts := jsonb_build_object(
    'mobility_by_semester', v_sem,
    'by_country', coalesce((select jsonb_agg(jsonb_build_object('country_code', x.cc, 'country_name', co.name, 'activities', x.n)
                                             order by x.n desc, x.cc)
        from (select ps.country_code cc,
                     count(distinct case when v_univ then a.event_group_id::text else a.id::text end) n
                from realisasi.activities a join realisasi.activity_partner_snapshot ps on ps.activity_id = a.id
               where a.id = any(v_base) group by ps.country_code order by 2 desc, 1 limit 10) x
        left join public.countries co on co.code = x.cc), '[]'::jsonb),
    'by_unit', case when v_univ then coalesce((select jsonb_agg(jsonb_build_object('unit_id', x.uid, 'unit_name', u.name, 'activities', x.n)
                                             order by x.n desc, u.name)
        from (select au.unit_id uid, count(distinct au.activity_id) n from realisasi.activity_units au
               where au.activity_id = any(v_base) group by au.unit_id) x join public.units u on u.id = x.uid), '[]'::jsonb)
               else '[]'::jsonb end,
    'by_sdg', (select jsonb_agg(jsonb_build_object('sdg_id', g.id, 'name', g.name, 'activities',
                 (select count(distinct case when v_univ then a.event_group_id::text else a.id::text end)
                    from realisasi.activity_sdgs x join realisasi.activities a on a.id = x.activity_id
                   where x.sdg_id = g.id and a.id = any(v_base))) order by g.id) from realisasi.sdgs g),
    'realization_by_unit', '[]'::jsonb,
    'top_partners', coalesce((select jsonb_agg(jsonb_build_object('partner_id', x.pid, 'partner_name', x.pname,
                                               'country_code', x.cc, 'activities', x.n) order by x.n desc, x.pname)
        from (select ps.partner_id pid, min(ps.partner_name) pname, min(ps.country_code) cc,
                     count(distinct case when v_univ then a.event_group_id::text else a.id::text end) n
                from realisasi.activities a join realisasi.activity_partner_snapshot ps on ps.activity_id = a.id
               where a.id = any(v_base) group by ps.partner_id order by 4 desc, 2 limit 10) x), '[]'::jsonb));

  return jsonb_build_object(
    'kpi_1_1', jsonb_build_object(
        'inbound', (select count(*) from _kv_items where kpi_code = '1.1' and bucket = 'inbound'),
        'outbound', (select count(*) from _kv_items where kpi_code = '1.1' and bucket = 'outbound'),
        'total', (select count(*) from _kv_items where kpi_code = '1.1'),
        'by_semester', v_sem),
    'kpi_1_19_s1', jsonb_build_object(
        'international', (select count(*) from _kv_items where kpi_code = '1.19.S1' and bucket = 'international'),
        'domestic', (select count(*) from _kv_items where kpi_code = '1.19.S1' and bucket = 'domestic')),
    'kpi_1_19_24', v_24,
    'kpi_1_19_s8', jsonb_build_object('reported', v_s8r, 'unmatched_known', v_s8u, 'pct', realisasi._pct(v_s8r, v_s8r + v_s8u)),
    'charts', v_charts);
end $$;

create function realisasi.compute_kpis(p_from date, p_to date, p_cutoff date, p_ay_id int,
                                       p_as_of timestamptz default null, p_unit_id int default null) returns jsonb
language plpgsql volatile security definer set search_path = realisasi, public, extensions, pg_temp as $$
declare v_as_of timestamptz := coalesce(p_as_of, realisasi.now_ts()); v_grace int := coalesce(realisasi.setting_int('grace_period_months'), 6);
        v_items jsonb; v_vals jsonb; v_units int[]; v_by_unit jsonb := '[]'::jsonb; u record; v_u jsonb;
begin
  select coalesce(jsonb_agg(to_jsonb(i)), '[]'::jsonb) into v_items
    from realisasi._kpi_items(p_from, p_to, p_cutoff, p_ay_id, v_as_of, p_unit_id, v_grace) i;
  v_vals := realisasi._kpi_values(v_items, p_from, p_to, p_ay_id, p_unit_id);

  if p_unit_id is null then
    select coalesce(array_agg(distinct x), '{}') into v_units from (
      select au.unit_id x from realisasi.activity_units au
       where au.activity_id in (select (e ->> 'activity_id')::uuid from jsonb_array_elements(v_items) e where e ->> 'kpi_code' = 'base')
      union
      select su.unit_id from jsonb_array_elements(v_items) e
        join realisasi.v_chains c on c.chain_id = (e ->> 'ref_id')::int
        join public.document_scope_units su on su.document_id = any(c.document_ids)
       where e ->> 'kpi_code' = '1.19.24' and e ->> 'bucket' in ('denominator','grace_excluded')) q;
    for u in select un.id, un.name from public.units un where un.id = any(v_units) order by un.name loop
      v_u := realisasi.compute_kpis(p_from, p_to, p_cutoff, p_ay_id, v_as_of, u.id) - 'params' - 'by_unit';
      v_by_unit := v_by_unit || jsonb_build_array(jsonb_build_object('unit_id', u.id, 'unit_name', u.name) || v_u);
    end loop;
    v_vals := jsonb_set(v_vals, '{charts,realization_by_unit}', coalesce((
      select jsonb_agg(jsonb_build_object('unit_id', (b ->> 'unit_id')::int, 'unit_name', b ->> 'unit_name',
                         'numerator', (b #> '{kpi_1_19_24,all,numerator}')::int, 'denominator', (b #> '{kpi_1_19_24,all,denominator}')::int,
                         'pct', b #> '{kpi_1_19_24,all,pct}') order by b ->> 'unit_name')
        from jsonb_array_elements(v_by_unit) b where (b #> '{kpi_1_19_24,all,denominator}')::int > 0), '[]'::jsonb));
  end if;

  return jsonb_build_object('params', jsonb_build_object('from', p_from, 'to', p_to, 'cutoff', p_cutoff, 'ay_id', p_ay_id,
                                                         'as_of', v_as_of, 'unit_id', p_unit_id, 'grace_period_months', v_grace))
         || v_vals
         || case when p_unit_id is null then jsonb_build_object('by_unit', v_by_unit) else '{}'::jsonb end;
end $$;

-- Schema §5.2 wrappers (thin aggregations over kpi_items) ----------------------------
create function realisasi.kpi_1_1(p_from date, p_to date)
returns table(direction realisasi.direction, students bigint)
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select d.dir::realisasi.direction, count(i.ref_id)
    from (values ('inbound'), ('outbound')) d(dir)
    left join realisasi.kpi_items(p_from, p_to, p_to, null) i on i.kpi_code = '1.1' and i.bucket = d.dir
   group by d.dir
$$;

create function realisasi.kpi_1_19_s1(p_from date, p_to date) returns bigint
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select count(*) from realisasi.kpi_items(p_from, p_to, p_to, null) i where i.kpi_code = '1.19.S1' and i.bucket = 'international'
$$;

create function realisasi.kpi_1_19_24(p_ay_start date, p_cutoff date, p_grace_months int)
returns table(scope text, numerator bigint, denominator bigint, grace_excluded bigint)
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select s.scope,
         count(*) filter (where i.bucket = 'numerator'),
         count(*) filter (where i.bucket = 'denominator'),
         count(*) filter (where i.bucket = 'grace_excluded')
    from (values ('all'), ('international'), ('domestic')) s(scope)
    left join (select i.*, c.is_international
                 from realisasi._kpi_items(p_ay_start, p_cutoff, p_cutoff, null, null, null, p_grace_months) i
                 left join realisasi.v_chains c on c.chain_id = i.ref_id::int
                where i.kpi_code = '1.19.24') i
           on s.scope = 'all' or (s.scope = 'international') = coalesce(i.is_international, false)
   group by s.scope
$$;

create function realisasi.kpi_1_19_s8(p_from date, p_to date)
returns table(reported bigint, unmatched_known bigint, pct numeric)
language sql stable security definer set search_path = realisasi, public, extensions, pg_temp as $$
  select r, u, realisasi._pct(r, r + u)
    from (select count(*) filter (where i.bucket = 'reported') r, count(*) filter (where i.bucket = 'unmatched_known') u
            from realisasi.kpi_items(p_from, p_to, p_to, null) i where i.kpi_code = '1.19.S8') x
$$;
