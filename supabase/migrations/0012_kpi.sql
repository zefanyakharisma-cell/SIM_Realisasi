-- 0012_kpi: single source of KPI truth (CONTRACTS §4.2/§4.3, Rules §6).

-- Item engine for one or many scopes in ONE pass (H6). p_scope:
--   'university' -> rows with su = null; 'unit' -> rows with su = p_unit_id; 'all' -> university rows + rows for every unit.
-- Dedupe is by event group within each scope (R-38/R-39, H1): a unit on two linked activities counts the event once,
-- and two units of one linked event each count it. is_intl carries the chain's international flag for 1.19.24 rows.
create function realisasi._kpi_items_scoped(p_from date, p_to date, p_cutoff date, p_as_of timestamptz,
                                            p_scope text, p_unit_id int, p_grace_months int)
returns table(su int, kpi_code text, bucket text, ref_type text, ref_id text, activity_id uuid, is_intl boolean)
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
with prm as (
  select coalesce(p_as_of, realisasi.now_ts()) as as_of
), qa0 as (             -- qualifying activities (verified as of as_of)
  select a.id, a.code, a.start_date, a.verified_at, a.event_group_id,
         t.direction as t_direction, t.counts_as_mobility, t.counts_for_s1,
         exists (select 1 from realisasi.activity_partner_snapshot ps
                  where ps.activity_id = a.id and ps.country_code <> 'ID') as intl
    from realisasi.activities a join realisasi.activity_types t on t.id = a.type_id
   where a.status = 'verified' and a.verified_at <= (select as_of from prm)
), qa as (              -- one row per (scope, activity)
  select null::int as su, q.* from qa0 q where p_scope in ('university','all')
  union all
  select au.unit_id, q.* from qa0 q join realisasi.activity_units au on au.activity_id = q.id
   where p_scope = 'all' or (p_scope = 'unit' and au.unit_id = p_unit_id)
), win as (
  select * from qa where start_date between p_from and p_to
), pv as (              -- participant version that counted as of as_of (M2): latest approved by then, else current approved
  select x.id, coalesce(
           (select v.id from realisasi.participant_set_versions v
             where v.activity_id = x.id and v.status in ('approved','superseded')
               and v.reviewed_at is not null and v.reviewed_at <= (select as_of from prm)
             order by v.version desc limit 1),
           (select v.id from realisasi.participant_set_versions v where v.activity_id = x.id and v.status = 'approved')) as vid
    from (select distinct id from win where counts_as_mobility) x
), stud as (
  select w.su, w.id, w.code, w.verified_at, w.event_group_id, w.t_direction::text as bucket, s.nrp
    from win w
    join pv on pv.id = w.id
    join realisasi.participant_students s on s.set_version_id = pv.vid
         and ((w.t_direction = 'outbound' and s.section = 'internal') or (w.t_direction = 'inbound' and s.section = 'inbound'))
   where w.counts_as_mobility
), k11 as (
  select distinct on (su, bucket, nrp, event_group_id) su, '1.1'::text, bucket, 'participant'::text, id::text || ':' || nrp, id, null::boolean
    from stud order by su, bucket, nrp, event_group_id, verified_at, code
), s1grp as (
  select su, event_group_id, bool_or(intl) as gintl from win where counts_for_s1 group by su, event_group_id
), ks1 as (
  select distinct on (w.su, w.event_group_id) w.su, '1.19.S1'::text,
         case when g.gintl then 'international' else 'domestic' end, 'activity'::text, w.id::text, w.id, null::boolean
    from win w join s1grp g on g.su is not distinct from w.su and g.event_group_id = w.event_group_id
   where w.counts_for_s1 and w.intl = g.gintl
   order by w.su, w.event_group_id, w.verified_at, w.code
), ks8 as (
  select distinct on (su, event_group_id) su, '1.19.S8'::text, 'reported'::text, 'activity'::text, id::text, id, null::boolean
    from win where intl order by su, event_group_id, verified_at, code
), kknown as (          -- R-49/R-50 (H3): a known entry is a gap unless matched to a qualifying international activity
  select ks.su, '1.19.S8'::text, 'unmatched_known'::text, 'known_activity'::text, k.id::text, null::uuid, null::boolean
    from realisasi.known_activities k
    cross join lateral (select null::int as su where p_scope in ('university','all')
                        union all
                        select k.unit_id where k.unit_id is not null and (p_scope = 'all' or (p_scope = 'unit' and k.unit_id = p_unit_id))) ks
   where k.is_international and k.activity_date between p_from and p_to
     and k.created_at <= (select as_of from prm)
     and (k.status = 'unmatched'
          or (k.status = 'matched' and not exists (select 1 from qa0 q where q.id = k.matched_activity_id and q.intl)))
), kbase as (
  select su, 'base'::text, 'verified_activity'::text, 'activity'::text, id::text, id, null::boolean from win
), ch0 as (             -- R-42/R-43 (H2): open-ended only while the current document is auto-renewed and not terminated
  select c.chain_id, c.is_international, c.document_ids,
         (not c.auto_renewed and c.chain_start > (p_cutoff - make_interval(months => p_grace_months))::date) as in_grace
    from realisasi.v_chains c
   where c.chain_start <= p_cutoff and ((c.auto_renewed and c.terminated_at is null) or c.chain_end >= p_from)
), ch as (
  select null::int as su, ch0.* from ch0 where p_scope in ('university','all')
  union all
  select x.unit_id, ch0.* from ch0
   cross join lateral (select distinct su.unit_id from public.document_scope_units su
                        where su.document_id = any(ch0.document_ids)
                          and (p_scope = 'all' or (p_scope = 'unit' and su.unit_id = p_unit_id))) x
   where p_scope in ('unit','all')
), realized as (        -- chain resolved at query time from the original document (L8), not the stored chain_id
  select distinct q.su, m.root_id as chain_id
    from realisasi.activity_documents ad
    join realisasi._chain_map() m on m.doc_id = ad.original_document_id
    join qa q on q.id = ad.activity_id
   where q.start_date between p_from and p_cutoff
), k24 as (
  select su, '1.19.24'::text, 'denominator'::text, 'chain'::text, chain_id::text, null::uuid, is_international from ch where not in_grace
  union all
  select ch.su, '1.19.24', 'numerator', 'chain', ch.chain_id::text, null::uuid, ch.is_international
    from ch join realized r on r.chain_id = ch.chain_id and r.su is not distinct from ch.su where not ch.in_grace
  union all
  select su, '1.19.24', 'grace_excluded', 'chain', chain_id::text, null::uuid, is_international from ch where in_grace
)
select * from k11 union all select * from ks1 union all select * from k24
union all select * from ks8 union all select * from kknown union all select * from kbase
$$;

create function realisasi._kpi_items(p_from date, p_to date, p_cutoff date, p_ay_id int,
                                     p_as_of timestamptz, p_unit_id int, p_grace_months int)
returns table(kpi_code text, bucket text, ref_type text, ref_id text, activity_id uuid)
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select i.kpi_code, i.bucket, i.ref_type, i.ref_id, i.activity_id
    from realisasi._kpi_items_scoped(p_from, p_to, p_cutoff, p_as_of,
                                     case when p_unit_id is null then 'university' else 'unit' end, p_unit_id, p_grace_months) i
$$;

create function realisasi.kpi_items(p_from date, p_to date, p_cutoff date, p_ay_id int,
                                    p_as_of timestamptz default null, p_unit_id int default null)
returns table(kpi_code text, bucket text, ref_type text, ref_id text, activity_id uuid)
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select * from realisasi._kpi_items(p_from, p_to, p_cutoff, p_ay_id, p_as_of, p_unit_id,
                                     coalesce(realisasi.setting_int('grace_period_months'), 6))
$$;

create function realisasi._pct(n numeric, d numeric) returns numeric
language sql immutable set search_path = realisasi, extensions, public, pg_temp as $$
  select round(100.0 * n / nullif(d, 0), 1)
$$;

-- KPI values from a set of items (internal; p_items = jsonb array of kpi_items rows)
create function realisasi._kpi_values(p_items jsonb, p_from date, p_to date, p_ay_id int, p_unit_id int) returns jsonb
language plpgsql volatile security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_sem jsonb; v_24 jsonb; v_s8r int; v_s8u int; v_base uuid[]; v_charts jsonb; v_univ boolean := p_unit_id is null;
begin
  if to_regclass('pg_temp._kv_items') is null then
    create temp table _kv_items (kpi_code text, bucket text, ref_type text, ref_id text, activity_id uuid, is_intl boolean) on commit drop;
  end if;
  truncate _kv_items;
  insert into _kv_items select * from jsonb_to_recordset(coalesce(p_items, '[]'::jsonb))
    as i(kpi_code text, bucket text, ref_type text, ref_id text, activity_id uuid, is_intl boolean);

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
            left join (select i.* from _kv_items i where i.kpi_code = '1.19.24') i
                   on s.scope = 'all' or (s.scope = 'international') = coalesce(i.is_intl, false)
           group by s.scope) sc;

  select count(*) filter (where bucket = 'reported'), count(*) filter (where bucket = 'unmatched_known')
    into v_s8r, v_s8u from _kv_items where kpi_code = '1.19.S8';
  select coalesce(array_agg(activity_id), '{}') into v_base from _kv_items where kpi_code = 'base';

  v_charts := jsonb_build_object(
    'mobility_by_semester', v_sem,
    'by_country', coalesce((select jsonb_agg(jsonb_build_object('country_code', x.cc, 'country_name', co.name, 'activities', x.n)
                                             order by x.n desc, x.cc)
        from (select ps.country_code cc,
                     count(distinct a.event_group_id) n
                from realisasi.activities a join realisasi.activity_partner_snapshot ps on ps.activity_id = a.id
               where a.id = any(v_base) group by ps.country_code order by 2 desc, 1 limit 10) x
        left join public.countries co on co.code = x.cc), '[]'::jsonb),
    'by_unit', case when v_univ then coalesce((select jsonb_agg(jsonb_build_object('unit_id', x.uid, 'unit_name', u.name, 'activities', x.n)
                                             order by x.n desc, u.name)
        from (select au.unit_id uid, count(distinct au.activity_id) n from realisasi.activity_units au
               where au.activity_id = any(v_base) group by au.unit_id) x join public.units u on u.id = x.uid), '[]'::jsonb)
               else '[]'::jsonb end,
    'by_sdg', (select jsonb_agg(jsonb_build_object('sdg_id', g.id, 'name', g.name, 'activities',
                 (select count(distinct a.event_group_id)
                    from realisasi.activity_sdgs x join realisasi.activities a on a.id = x.activity_id
                   where x.sdg_id = g.id and a.id = any(v_base))) order by g.id) from realisasi.sdgs g),
    'realization_by_unit', '[]'::jsonb,
    'top_partners', coalesce((select jsonb_agg(jsonb_build_object('partner_id', x.pid, 'partner_name', x.pname,
                                               'country_code', x.cc, 'activities', x.n) order by x.n desc, x.pname)
        from (select ps.partner_id pid, min(ps.partner_name) pname, min(ps.country_code) cc,
                     count(distinct a.event_group_id) n
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
language plpgsql volatile security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_as_of timestamptz := coalesce(p_as_of, realisasi.now_ts()); v_grace int := coalesce(realisasi.setting_int('grace_period_months'), 6);
        v_vals jsonb; v_by_unit jsonb := '[]'::jsonb; u record;
begin
  -- one item pass for the university and every unit (H6); by_unit[i] = compute_kpis(…, unit) by construction
  if to_regclass('pg_temp._kc_items') is null then
    create temp table _kc_items (su int, kpi_code text, bucket text, ref_type text, ref_id text, activity_id uuid, is_intl boolean) on commit drop;
  end if;
  truncate _kc_items;
  insert into _kc_items
  select * from realisasi._kpi_items_scoped(p_from, p_to, p_cutoff, v_as_of,
                                            case when p_unit_id is null then 'all' else 'unit' end, p_unit_id, v_grace);

  v_vals := realisasi._kpi_values((select coalesce(jsonb_agg(to_jsonb(i) - 'su'), '[]'::jsonb) from _kc_items i
                                    where i.su is not distinct from p_unit_id), p_from, p_to, p_ay_id, p_unit_id);

  if p_unit_id is null then
    for u in select un.id, un.name,
                    (select coalesce(jsonb_agg(to_jsonb(i) - 'su'), '[]'::jsonb) from _kc_items i where i.su = un.id) as items
               from public.units un
              where un.id in (select su from _kc_items
                               where su is not null and (kpi_code = 'base' or (kpi_code = '1.19.24' and bucket in ('denominator','grace_excluded'))))
              order by un.name loop
      v_by_unit := v_by_unit || jsonb_build_array(jsonb_build_object('unit_id', u.id, 'unit_name', u.name)
                                                  || realisasi._kpi_values(u.items, p_from, p_to, p_ay_id, u.id));
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
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select d.dir::realisasi.direction, count(i.ref_id)
    from (values ('inbound'), ('outbound')) d(dir)
    left join realisasi.kpi_items(p_from, p_to, p_to, null) i on i.kpi_code = '1.1' and i.bucket = d.dir
   group by d.dir
$$;

create function realisasi.kpi_1_19_s1(p_from date, p_to date) returns bigint
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select count(*) from realisasi.kpi_items(p_from, p_to, p_to, null) i where i.kpi_code = '1.19.S1' and i.bucket = 'international'
$$;

create function realisasi.kpi_1_19_24(p_ay_start date, p_cutoff date, p_grace_months int)
returns table(scope text, numerator bigint, denominator bigint, grace_excluded bigint)
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select s.scope,
         count(*) filter (where i.bucket = 'numerator'),
         count(*) filter (where i.bucket = 'denominator'),
         count(*) filter (where i.bucket = 'grace_excluded')
    from (values ('all'), ('international'), ('domestic')) s(scope)
    left join (select i.*
                 from realisasi._kpi_items_scoped(p_ay_start, p_cutoff, p_cutoff, null, 'university', null, p_grace_months) i
                where i.kpi_code = '1.19.24') i
           on s.scope = 'all' or (s.scope = 'international') = coalesce(i.is_intl, false)
   group by s.scope
$$;

create function realisasi.kpi_1_19_s8(p_from date, p_to date)
returns table(reported bigint, unmatched_known bigint, pct numeric)
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select r, u, realisasi._pct(r, r + u)
    from (select count(*) filter (where i.bucket = 'reported') r, count(*) filter (where i.bucket = 'unmatched_known') u
            from realisasi.kpi_items(p_from, p_to, p_to, null) i where i.kpi_code = '1.19.S8') x
$$;
