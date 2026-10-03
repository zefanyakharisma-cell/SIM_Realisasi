-- SIM Realisasi Supabase install, PART 4 OF 5 (commit b8a514a).
-- Run parts 1..5 in order in Supabase Dashboard -> SQL Editor. If any part fails, start again from part 1.
begin;

-- >>> supabase/migrations/0012_kpi.sql
-- 0012_kpi: single source of KPI truth (CONTRACTS §4.2/§4.3, Rules §6).

-- Item engine for one or many scopes in ONE pass (H6). p_scope:
--   'university' -> rows with su = null; 'unit' -> rows with su = p_unit_id; 'all' -> university rows + rows for every unit.
-- Revisi V.1: every activity is its own event group, so KPI 1.1 counts (NRP, activity) pairs: the same student in two
-- activities of one unit counts twice (rule 2.2). A student claimed by two units' overlapping activities (a
-- participant_conflicts row) counts only on the activity Mobility kept; while the conflict is open, on neither
-- (rule 2.1). is_intl carries the chain's international flag for 1.19.24 rows.
create function realisasi._kpi_items_scoped(p_from date, p_to date, p_cutoff date, p_as_of timestamptz,
                                            p_scope text, p_unit_id int, p_grace_months int)
returns table(su int, kpi_code text, bucket text, ref_type text, ref_id text, activity_id uuid, is_intl boolean)
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
with prm as (
  select coalesce(p_as_of, realisasi.now_ts()) as as_of
), qa0 as (             -- qualifying activities (verified as of as_of)
  select a.id, a.code, a.start_date, a.verified_at, a.event_group_id,
         a.direction as t_direction, (r.mobility_category is not null) as counts_as_mobility,
         coalesce(r.counts_for_s1, true) as counts_for_s1,
         exists (select 1 from realisasi.activity_partner_snapshot ps
                  where ps.activity_id = a.id and ps.country_code <> 'ID') as intl
    from realisasi.activities a left join realisasi.agenda_rules r on r.agenda_id = a.agenda_id
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
     and not exists (select 1 from realisasi.participant_conflicts c          -- rule 2.1
                      where c.nrp = s.nrp and w.id in (c.activity_a, c.activity_b)
                        and (c.status = 'open' or c.kept_activity_id <> w.id))
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
   cross join lateral (select distinct su.unit_id from kerjasama.document_scope_units su
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
union all select * from kbase
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
declare v_sem jsonb; v_24 jsonb; v_base uuid[]; v_charts jsonb; v_univ boolean := p_unit_id is null;
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

  select coalesce(array_agg(activity_id), '{}') into v_base from _kv_items where kpi_code = 'base';

  v_charts := jsonb_build_object(
    'mobility_by_semester', v_sem,
    'by_country', coalesce((select jsonb_agg(jsonb_build_object('country_code', x.cc, 'country_name', co.name, 'activities', x.n)
                                             order by x.n desc, x.cc)
        from (select ps.country_code cc,
                     count(distinct a.event_group_id) n
                from realisasi.activities a join realisasi.activity_partner_snapshot ps on ps.activity_id = a.id
               where a.id = any(v_base) group by ps.country_code order by 2 desc, 1 limit 10) x
        left join kerjasama.countries co on co.code = x.cc), '[]'::jsonb),
    'by_unit', case when v_univ then coalesce((select jsonb_agg(jsonb_build_object('unit_id', x.uid, 'unit_name', u.name, 'activities', x.n)
                                             order by x.n desc, u.name)
        from (select au.unit_id uid, count(distinct au.activity_id) n from realisasi.activity_units au
               where au.activity_id = any(v_base) group by au.unit_id) x join kerjasama.units u on u.id = x.uid), '[]'::jsonb)
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
               from kerjasama.units un
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

-- >>> supabase/migrations/0013_snapshots.sql
-- 0013_snapshots: freeze / refreeze (R-55..R-59), late additions and post-freeze changes.

-- previous snapshot P of snapshot S (M3): the snapshot of the immediately preceding PERIOD
-- ((AY, ganjil) -> (previous AY, genap); (AY, genap) -> (AY, ganjil)) that was live at S's frozen_at,
-- i.e. the latest one of that period with frozen_at < p_before. Re-freezing an unrelated (older) period no longer moves P.
create function realisasi._prev_snapshot(p_ay int, p_kind realisasi.snapshot_kind, p_before timestamptz) returns realisasi.kpi_snapshots
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select k.* from realisasi.kpi_snapshots k
   where k.frozen_at < p_before
     and case when p_kind = 'genap_full_year' then k.academic_year_id = p_ay and k.kind = 'ganjil_ytd'
              else k.kind = 'genap_full_year'
                   and k.academic_year_id = (select py.id from realisasi.academic_years py, realisasi.academic_years cy
                                               where cy.id = p_ay and py.start_date < cy.start_date
                                               order by py.start_date desc limit 1) end
   order by k.frozen_at desc limit 1
$$;

create function realisasi._snapshot_window(p_ay int, p_kind realisasi.snapshot_kind,
                                           out window_start date, out window_end date, out cutoff_date date)
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare ay realisasi.academic_years; s realisasi.semesters;
begin
  select * into ay from realisasi.academic_years where id = p_ay;
  if not found then perform realisasi._not_found(); end if;
  select * into s from realisasi.semesters where academic_year_id = p_ay
     and term = case when p_kind = 'ganjil_ytd' then 'ganjil' else 'genap' end::realisasi.semester_term;
  if not found then perform realisasi._raise('R55_NO_SEMESTER', 'Kalender semester untuk periode ini belum diatur.'); end if;
  window_start := ay.start_date;
  window_end := case when p_kind = 'ganjil_ytd' then s.end_date else ay.end_date end;
  cutoff_date := s.cutoff_date;
end $$;

create function realisasi._freeze(p_ay int, p_kind realisasi.snapshot_kind, p_as_of timestamptz, p_actor uuid,
                                  p_reason text, p_old uuid) returns uuid
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare w record; v_id uuid := gen_random_uuid(); v_vals jsonb; p realisasi.kpi_snapshots; v_label text;
begin
  select * into w from realisasi._snapshot_window(p_ay, p_kind);
  if p_old is not null then
    update realisasi.kpi_snapshots set superseded_by = v_id where id = p_old;   -- deferred FK
  elsif exists (select 1 from realisasi.kpi_snapshots where academic_year_id = p_ay and kind = p_kind and superseded_by is null) then
    perform realisasi._raise('R55_ALREADY_FROZEN', 'Snapshot untuk periode ini sudah dibekukan. Gunakan "Bekukan ulang".');
  end if;

  v_vals := realisasi.compute_kpis(w.window_start, w.window_end, w.cutoff_date, p_ay, p_as_of, null);
  insert into realisasi.kpi_snapshots (id, academic_year_id, kind, window_start, window_end, cutoff_date, values,
                                       settings_used, frozen_at, frozen_by, refreeze_reason)
  values (v_id, p_ay, p_kind, w.window_start, w.window_end, w.cutoff_date, v_vals,
          realisasi.settings_json(), p_as_of, p_actor, p_reason);

  p := realisasi._prev_snapshot(p_ay, p_kind, p_as_of);
  insert into realisasi.kpi_snapshot_items (snapshot_id, kpi_code, bucket, ref_type, ref_id, is_late_addition)
  select distinct on (i.kpi_code, i.bucket, i.ref_type, i.ref_id) v_id, i.kpi_code, i.bucket, i.ref_type, i.ref_id,
         case
           when p.id is null then false
           when i.activity_id is not null then exists (
             select 1 from realisasi.activities a where a.id = i.activity_id
                and a.verified_at > p.frozen_at and a.start_date between p.window_start and p.window_end)
           when i.kpi_code = '1.19.24' and i.bucket = 'numerator' then
             not exists (select 1 from realisasi.kpi_snapshot_items pi where pi.snapshot_id = p.id and pi.kpi_code = '1.19.24'
                            and pi.bucket = 'numerator' and pi.ref_id = i.ref_id)
             and exists (select 1 from realisasi.activity_documents ad join realisasi.activities a on a.id = ad.activity_id
                          where ad.chain_id = i.ref_id::int and a.status = 'verified' and a.verified_at <= p_as_of
                            and a.start_date between w.window_start and w.cutoff_date
                            and a.verified_at > p.frozen_at and a.start_date between p.window_start and p.window_end)
           else false end
    from realisasi.kpi_items(w.window_start, w.window_end, w.cutoff_date, p_ay, p_as_of, null) i
   order by i.kpi_code, i.bucket, i.ref_type, i.ref_id;

  select realisasi._snapshot_label(p_kind, label) into v_label from realisasi.academic_years where id = p_ay;
  perform realisasi._notify_admins('snapshot_frozen', 'Snapshot dibekukan: ' || v_label,
    'Snapshot capaian Renstra ' || v_label || ' telah dibekukan.', '/realisasi/laporan?report=arsip&snapshot=' || v_id);
  perform realisasi._notify_viewers('snapshot_frozen', 'Snapshot dibekukan: ' || v_label,
    'Snapshot capaian Renstra ' || v_label || ' telah dibekukan.', '/realisasi/laporan?report=arsip&snapshot=' || v_id);
  return v_id;
end $$;

-- p_as_of / p_actor are honoured only for the system caller (scheduled job, seeds). A user freeze is stamped
-- now_ts() / auth.uid() and only allowed once the period's cutoff has passed (M4).
create function realisasi.freeze_snapshot(p_ay int, p_kind realisasi.snapshot_kind, p_as_of timestamptz default null,
                                          p_actor uuid default null) returns uuid
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare w record;
begin
  if p_kind is null then perform realisasi._invalid('kind'); end if;
  if realisasi._is_system_caller() then
    return realisasi._freeze(p_ay, p_kind, coalesce(p_as_of, realisasi.now_ts()), p_actor, null, null);
  end if;
  perform realisasi._require_admin();
  select * into w from realisasi._snapshot_window(p_ay, p_kind);
  if w.cutoff_date > realisasi.today() then
    perform realisasi._raise('R55_BEFORE_CUTOFF',
      format('Periode ini baru dapat dibekukan setelah batas %s.', realisasi._fmt_date(w.cutoff_date)),
      jsonb_build_object('cutoff_date', w.cutoff_date));
  end if;
  return realisasi._freeze(p_ay, p_kind, realisasi.now_ts(), auth.uid(), null, null);
end $$;

create function realisasi.refreeze_snapshot(p_snapshot uuid, p_reason text) returns uuid
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_admin(); s realisasi.kpi_snapshots;
begin
  if nullif(btrim(p_reason), '') is null then perform realisasi._raise('R58_REASON_REQUIRED', 'Alasan pembekuan ulang wajib diisi.'); end if;
  select * into s from realisasi.kpi_snapshots where id = p_snapshot for update;
  if not found then perform realisasi._not_found(); end if;
  if s.superseded_by is not null then perform realisasi._raise('R58_NOT_LIVE', 'Snapshot ini sudah digantikan.'); end if;
  return realisasi._freeze(s.academic_year_id, s.kind, realisasi.now_ts(), v_uid, btrim(p_reason), s.id);
end $$;

-- Late additions (internal; no permission check) -------------------------------
create function realisasi._snapshot_late_additions(p_snapshot uuid) returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare s realisasi.kpi_snapshots; p realisasi.kpi_snapshots; v_plabel text;
begin
  select * into s from realisasi.kpi_snapshots where id = p_snapshot;
  if not found then return '[]'::jsonb; end if;
  p := realisasi._prev_snapshot(s.academic_year_id, s.kind, s.frozen_at);
  if p.id is null then return '[]'::jsonb; end if;
  select realisasi._snapshot_label(p.kind, label) into v_plabel from realisasi.academic_years where id = p.academic_year_id;

  return coalesce((select jsonb_agg(jsonb_build_object(
      'activity_id', a.id, 'code', a.code, 'name', a.name,
      'unit_names', coalesce((select jsonb_agg(u.name order by au.is_submitter desc, u.name) from realisasi.activity_units au
                               join kerjasama.units u on u.id = au.unit_id where au.activity_id = a.id), '[]'::jsonb),
      'start_date', a.start_date, 'verified_at', a.verified_at,
      'previous_snapshot_id', p.id, 'previous_snapshot_label', v_plabel,
      'counted_in_this_snapshot', x.counted, 'kpi_codes', to_jsonb(x.codes)) order by a.start_date, a.code)
    from (
      select act_id, bool_or(counted) as counted, array_remove(array_agg(distinct code order by code), null) as codes
        from (
          -- (a) items of this snapshot marked late
          select case when i.ref_type = 'participant' then split_part(i.ref_id, ':', 1)::uuid else i.ref_id::uuid end as act_id,
                 true as counted, i.kpi_code as code
            from realisasi.kpi_snapshot_items i
           where i.snapshot_id = s.id and i.is_late_addition and i.ref_type in ('activity','participant')
          union all
          select a.id, true, '1.19.24'
            from realisasi.kpi_snapshot_items i
            join realisasi.activity_documents ad on ad.chain_id = i.ref_id::int
            join realisasi.activities a on a.id = ad.activity_id
           where i.snapshot_id = s.id and i.is_late_addition and i.kpi_code = '1.19.24' and i.bucket = 'numerator'
             and a.status = 'verified' and a.verified_at <= s.frozen_at and a.start_date between s.window_start and s.cutoff_date
             and a.verified_at > p.frozen_at and a.start_date between p.window_start and p.window_end
          union all
          -- (b) late for P's window but outside this snapshot's window
          select a.id, false, null
            from realisasi.activities a
           where a.status = 'verified' and a.verified_at > p.frozen_at and a.verified_at <= s.frozen_at
             and a.start_date between p.window_start and p.window_end
             and a.start_date not between s.window_start and s.window_end) q
       group by act_id) x
    join realisasi.activities a on a.id = x.act_id), '[]'::jsonb);
end $$;

create function realisasi._snapshot_post_freeze_changes(p_snapshot uuid) returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare s realisasi.kpi_snapshots; p realisasi.kpi_snapshots;
begin
  select * into s from realisasi.kpi_snapshots where id = p_snapshot;
  if not found then return '[]'::jsonb; end if;
  p := realisasi._prev_snapshot(s.academic_year_id, s.kind, s.frozen_at);
  return coalesce((select jsonb_agg(jsonb_build_object(
      'log_id', l.id, 'activity_id', a.id, 'code', a.code, 'name', a.name, 'kind', l.kind, 'track', l.track,
      'action', l.action, 'actor_name', pr.display_name, 'note', l.note,
      'diff', case when realisasi.sees_participant_identifiers() then l.diff else realisasi._mask_log_diff(l.diff) end,   -- M6
      'created_at', l.created_at)
      order by l.created_at, l.id)
    from realisasi.activity_log l
    join realisasi.activities a on a.id = l.activity_id
    left join kerjasama.profiles pr on pr.id = l.actor_id
   where l.in_frozen_period and l.created_at <= s.frozen_at
     and (p.id is null or l.created_at > p.frozen_at)), '[]'::jsonb);
end $$;

create function realisasi._require_report_reader() returns void
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
begin
  perform realisasi._require_uid();
  if realisasi.my_role() not in ('io_staff','io_admin','viewer') then perform realisasi._forbidden(); end if;
end $$;

create function realisasi.snapshot_late_additions(p_snapshot uuid) returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
begin
  perform realisasi._require_report_reader();
  if not exists (select 1 from realisasi.kpi_snapshots where id = p_snapshot) then perform realisasi._not_found(); end if;
  return realisasi._snapshot_late_additions(p_snapshot);
end $$;

create function realisasi.snapshot_post_freeze_changes(p_snapshot uuid) returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
begin
  perform realisasi._require_report_reader();
  if not exists (select 1 from realisasi.kpi_snapshots where id = p_snapshot) then perform realisasi._not_found(); end if;
  return realisasi._snapshot_post_freeze_changes(p_snapshot);
end $$;

-- >>> supabase/migrations/0014_reads.sql
-- 0014_reads: read RPCs returning the JSON shapes of CONTRACTS §4.

-- Period context ---------------------------------------------------------------------
create function realisasi._resolve_ay(p_ay_id int) returns int
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce(
    (select id from realisasi.academic_years where id = p_ay_id),
    case when p_ay_id is null then
      coalesce((select id from realisasi.academic_years where realisasi.today() between start_date and end_date limit 1),
               (select id from realisasi.academic_years where start_date <= realisasi.today() order by start_date desc limit 1),
               (select id from realisasi.academic_years order by start_date limit 1)) end)
$$;

create type realisasi.period_ctx as (ay_id int, ay_label text, period text, kind realisasi.snapshot_kind, label text,
  window_start date, window_end date, cutoff date, frozen boolean, snapshot_id uuid,
  frozen_at timestamptz, frozen_by_name text, grace_months int);

-- Revisi V.1 cut-offs: ganjil = Ganjil only; genap = Genap only; full = whole academic year (cumulative);
-- ytd = academic-year start -> today. Ganjil and full read their frozen snapshot when one exists. Genap has no
-- snapshot of its own: once the full-year snapshot is frozen it is computed as of that freeze (frozen, snapshot_id
-- null), so it never drifts afterwards. YTD is always live.
create function realisasi._period_ctx(p_ay_id int, p_period text, p_snapshot uuid default null) returns realisasi.period_ctx
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare ay realisasi.academic_years; s realisasi.kpi_snapshots; w record; r realisasi.period_ctx; g realisasi.semesters;
begin
  if p_snapshot is not null then
    select * into s from realisasi.kpi_snapshots where id = p_snapshot;
    if not found then perform realisasi._not_found(); end if;
    select * into ay from realisasi.academic_years where id = s.academic_year_id;
    r.period := case when s.kind = 'ganjil_ytd' then 'ganjil' else 'full' end;
  else
    if p_period is null or p_period not in ('ganjil','genap','full','ytd') then perform realisasi._invalid('period'); end if;
    select * into ay from realisasi.academic_years where id = realisasi._resolve_ay(p_ay_id);
    if not found then perform realisasi._not_found(); end if;
    r.period := p_period;
  end if;
  r.ay_id := ay.id; r.ay_label := ay.label; r.frozen := false;
  r.grace_months := coalesce(realisasi.setting_int('grace_period_months'), 6);
  if r.period = 'ytd' then
    r.kind := null; r.label := 'YTD ' || ay.label;
    r.window_start := ay.start_date; r.window_end := least(ay.end_date, realisasi.today()); r.cutoff := r.window_end;
    return r;
  end if;
  if r.period = 'genap' then
    select * into g from realisasi.semesters where academic_year_id = ay.id and term = 'genap';
    if not found then perform realisasi._raise('R55_NO_SEMESTER', 'Kalender semester untuk periode ini belum diatur.'); end if;
    r.kind := null; r.label := 'Genap ' || ay.label;
    r.window_start := g.start_date; r.window_end := least(g.end_date, realisasi.today());
    r.cutoff := least(g.cutoff_date, realisasi.today());
    select * into s from realisasi.kpi_snapshots where academic_year_id = ay.id and kind = 'genap_full_year'
       and superseded_by is null;
    if s.id is not null then
      r.frozen := true; r.frozen_at := s.frozen_at;
      r.frozen_by_name := coalesce(realisasi._profile_name(s.frozen_by), 'Job terjadwal');
      r.window_end := g.end_date; r.cutoff := s.cutoff_date;
      r.grace_months := coalesce((s.settings_used ->> 'grace_period_months')::int, r.grace_months);
    end if;
    return r;
  end if;
  r.kind := case when r.period = 'ganjil' then 'ganjil_ytd' else 'genap_full_year' end;
  r.label := realisasi._snapshot_label(r.kind, ay.label);
  if s.id is null then
    select * into s from realisasi.kpi_snapshots where academic_year_id = ay.id and kpi_snapshots.kind = r.kind
       and superseded_by is null;
  end if;
  if s.id is not null then
    r.frozen := true; r.snapshot_id := s.id; r.frozen_at := s.frozen_at;
    r.frozen_by_name := coalesce(realisasi._profile_name(s.frozen_by), 'Job terjadwal');
    r.window_start := s.window_start; r.window_end := s.window_end; r.cutoff := s.cutoff_date;
    r.grace_months := coalesce((s.settings_used ->> 'grace_period_months')::int, r.grace_months);
  else
    select * into w from realisasi._snapshot_window(ay.id, r.kind);
    r.window_start := w.window_start;
    r.window_end := least(w.window_end, realisasi.today());
    r.cutoff := least(w.cutoff_date, realisasi.today());
  end if;
  return r;
end $$;

create function realisasi._period_json(c realisasi.period_ctx) returns jsonb
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select jsonb_build_object('ay_id', c.ay_id, 'ay_label', c.ay_label, 'period', c.period, 'kind', c.kind, 'label', c.label,
    'window_start', c.window_start, 'window_end', c.window_end, 'cutoff', c.cutoff, 'frozen', c.frozen,
    'snapshot_id', c.snapshot_id, 'frozen_at', c.frozen_at, 'frozen_by_name', c.frozen_by_name, 'today', realisasi.today(),
    'academic_years', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'label', label) order by start_date)
                                  from realisasi.academic_years), '[]'::jsonb))
$$;

create function realisasi.period_info(p_ay_id int, p_period text) returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare c realisasi.period_ctx;
begin
  perform realisasi._require_uid();
  c := realisasi._period_ctx(p_ay_id, p_period);
  return realisasi._period_json(c);
end $$;

-- KPI values for a context (frozen -> snapshot, else live) ------------------------
create function realisasi._ctx_values(c realisasi.period_ctx, p_unit_id int) returns jsonb
language plpgsql volatile security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v jsonb; e jsonb;
begin
  if c.frozen and c.snapshot_id is null then        -- genap after the full-year freeze: as of that freeze
    return realisasi.compute_kpis(c.window_start, c.window_end, c.cutoff, c.ay_id, c.frozen_at, p_unit_id);
  elsif c.frozen then
    select values into v from realisasi.kpi_snapshots where id = c.snapshot_id;
    if p_unit_id is null then return v; end if;
    select x into e from jsonb_array_elements(v -> 'by_unit') x where (x ->> 'unit_id')::int = p_unit_id;
    if e is null then
      e := realisasi._kpi_values('[]'::jsonb, c.window_start, c.window_end, c.ay_id, p_unit_id);
    end if;
    return jsonb_build_object('params', (v -> 'params') || jsonb_build_object('unit_id', p_unit_id))
           || (e - 'unit_id' - 'unit_name');
  end if;
  return realisasi.compute_kpis(c.window_start, c.window_end, c.cutoff, c.ay_id, null, p_unit_id);
end $$;

create function realisasi._scope_json(p_unit_id int) returns jsonb
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select jsonb_build_object('level', case when p_unit_id is null then 'university' else 'unit' end,
                            'unit_id', p_unit_id, 'unit_name', (select name from kerjasama.units where id = p_unit_id))
$$;

create function realisasi._forced_unit(p_unit_id int) returns int
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select case when realisasi.my_role() = 'submitter' then realisasi.my_unit() else p_unit_id end
$$;

-- "Perlu diproses" (Revisi V.1, replaces SLA): what the mobility team still has to handle. null for other roles.
create function realisasi._work_queue() returns jsonb
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select case when realisasi.in_team('mobility') then jsonb_build_object(
    'mobility_pending', (select count(*) from realisasi.activities where mobility_status = 'pending' and status <> 'draft'),
    'conflicts_open', (select count(*) from realisasi.participant_conflicts where status = 'open'),
    'waiting_unit_revision', (select count(*) from realisasi.activities where status = 'revision_requested'),
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name', a.name,
                         'unit_name', u.name, 'submitted_at', a.mobility_since,
                         'open_conflicts', realisasi.activity_open_conflicts(a.id)) order by a.mobility_since, a.code)
                        from (select * from realisasi.activities where mobility_status = 'pending' and status <> 'draft'
                               order by mobility_since, code limit 5) a
                        left join kerjasama.units u on u.id = a.submitter_unit_id), '[]'::jsonb)) end
$$;

create function realisasi.dashboard(p_ay_id int default null, p_period text default 'ytd', p_unit_id int default null) returns jsonb
language plpgsql volatile security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare c realisasi.period_ctx; pc realisasi.period_ctx; v_unit int; v_vals jsonb; v_prev jsonb := null; v_prev_ay realisasi.academic_years;
        v_pvals jsonb; v_late int; v_drafts jsonb := '[]'::jsonb; v_today date := realisasi.today();
begin
  perform realisasi._require_uid();
  v_unit := realisasi._forced_unit(p_unit_id);
  c := realisasi._period_ctx(p_ay_id, coalesce(p_period, 'ytd'));
  v_vals := realisasi._ctx_values(c, v_unit);

  select ay.* into v_prev_ay from realisasi.academic_years ay
    join realisasi.academic_years cur on cur.id = c.ay_id
   where ay.start_date < cur.start_date order by ay.start_date desc limit 1;
  if v_prev_ay.id is not null then
    if c.period = 'ytd' then
      v_pvals := realisasi.compute_kpis(v_prev_ay.start_date, least(v_prev_ay.end_date, (v_today - interval '1 year')::date),
                                        least(v_prev_ay.end_date, (v_today - interval '1 year')::date), v_prev_ay.id, null, v_unit);
    else
      begin
        pc := realisasi._period_ctx(v_prev_ay.id, c.period);
        v_pvals := realisasi._ctx_values(pc, v_unit);
      exception when others then v_pvals := null;
      end;
    end if;
    if v_pvals is not null then
      v_prev := jsonb_build_object('ay_label', v_prev_ay.label,
        'kpi_1_1', jsonb_build_object('total', v_pvals #> '{kpi_1_1,total}', 'inbound', v_pvals #> '{kpi_1_1,inbound}',
                                      'outbound', v_pvals #> '{kpi_1_1,outbound}'),
        'kpi_1_19_s1', jsonb_build_object('international', v_pvals #> '{kpi_1_19_s1,international}'),
        'kpi_1_19_24', jsonb_build_object('pct', v_pvals #> '{kpi_1_19_24,all,pct}'));
    end if;
  end if;

  if c.snapshot_id is not null then
    select count(*) into v_late from jsonb_array_elements(realisasi._snapshot_late_additions(c.snapshot_id)) x
     where v_unit is null or exists (select 1 from realisasi.activity_units au
                                      where au.activity_id = (x ->> 'activity_id')::uuid and au.unit_id = v_unit);
  else
    select count(*) into v_late from realisasi.activities a
     where a.status = 'verified' and a.start_date between c.window_start and c.window_end
       and (v_unit is null or exists (select 1 from realisasi.activity_units au where au.activity_id = a.id and au.unit_id = v_unit))
       and realisasi.is_late_addition(a.id);
  end if;

  if v_unit is not null then
    select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name', a.name, 'end_date', a.end_date,
             'reporting_deadline', a.reporting_deadline, 'days_left', a.reporting_deadline - v_today)
             order by a.reporting_deadline, a.code), '[]'::jsonb)
      into v_drafts
      from realisasi.activities a
     where a.status = 'draft' and a.submitter_unit_id = v_unit and a.reporting_deadline <= v_today + 14;
  end if;

  return jsonb_build_object('period', realisasi._period_json(c), 'scope', realisasi._scope_json(v_unit),
    'values', v_vals, 'previous', v_prev, 'late_additions', v_late, 'drafts_near_deadline', v_drafts,
    'work_queue', realisasi._work_queue());
end $$;

-- Drill-down -------------------------------------------------------------------------
create function realisasi._drill_items(c realisasi.period_ctx, p_unit_id int)
returns table(kpi_code text, bucket text, ref_type text, ref_id text, activity_id uuid, is_late boolean)
language plpgsql volatile security definer set search_path = realisasi, extensions, public, pg_temp as $$
begin
  if c.frozen and c.snapshot_id is null then          -- genap after the full-year freeze
    return query
      select i.kpi_code, i.bucket, i.ref_type, i.ref_id, i.activity_id,
             coalesce(i.activity_id is not null and realisasi.is_late_addition(i.activity_id), false)
        from realisasi._kpi_items(c.window_start, c.window_end, c.cutoff, c.ay_id, c.frozen_at, p_unit_id, c.grace_months) i;
  elsif c.frozen and p_unit_id is null then
    return query
      select i.kpi_code, i.bucket, i.ref_type, i.ref_id,
             case when i.ref_type = 'activity' then i.ref_id::uuid
                  when i.ref_type = 'participant' then split_part(i.ref_id, ':', 1)::uuid end,
             i.is_late_addition
        from realisasi.kpi_snapshot_items i where i.snapshot_id = c.snapshot_id;
  elsif c.frozen then
    return query
      select i.kpi_code, i.bucket, i.ref_type, i.ref_id, i.activity_id,
             coalesce(i.activity_id is not null and realisasi.is_late_addition(i.activity_id), false)
        from realisasi._kpi_items(c.window_start, c.window_end, c.cutoff, c.ay_id, c.frozen_at, p_unit_id, c.grace_months) i
       where i.activity_id is null
          or i.activity_id::text in (select b.ref_id from realisasi.kpi_snapshot_items b
                                      where b.snapshot_id = c.snapshot_id and b.kpi_code = 'base');
  else
    return query
      select i.kpi_code, i.bucket, i.ref_type, i.ref_id, i.activity_id,
             coalesce(i.activity_id is not null and realisasi.is_late_addition(i.activity_id), false)
        from realisasi._kpi_items(c.window_start, c.window_end, c.cutoff, c.ay_id, null, p_unit_id, c.grace_months) i;
  end if;
end $$;

create function realisasi._activity_kpi_row(p_activity uuid, p_bucket text, p_students int, p_late boolean) returns jsonb
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select jsonb_build_object('row_type', 'activity', 'activity_id', a.id, 'code', a.code, 'name', a.name,
    'agenda_name', g.name, 'direction', a.direction, 'mobility_category', r.mobility_category,
    'unit_names', coalesce((select jsonb_agg(u.name order by au.is_submitter desc, u.name) from realisasi.activity_units au
                             join kerjasama.units u on u.id = au.unit_id where au.activity_id = a.id), '[]'::jsonb),
    'partner_names', coalesce((select jsonb_agg(distinct ps.partner_name) from realisasi.activity_partner_snapshot ps where ps.activity_id = a.id), '[]'::jsonb),
    'country_codes', coalesce((select jsonb_agg(distinct ps.country_code) from realisasi.activity_partner_snapshot ps where ps.activity_id = a.id), '[]'::jsonb),
    'start_date', a.start_date, 'semester_label', realisasi.semester_label(a.semester_id),
    'bucket', p_bucket, 'students', p_students, 'is_late_addition', coalesce(p_late, false))
  from realisasi.activities a
  left join kerjasama.agendas g on g.id = a.agenda_id
  left join realisasi.agenda_rules r on r.agenda_id = a.agenda_id
 where a.id = p_activity
$$;

create function realisasi.kpi_drilldown(p_ay_id int, p_period text, p_kpi text, p_bucket text default null,
                                        p_unit_id int default null, p_snapshot_id uuid default null) returns jsonb
language plpgsql volatile security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare c realisasi.period_ctx; v_unit int; v_rows jsonb; v_io boolean := realisasi.is_io();
begin
  perform realisasi._require_uid();
  if p_kpi is null or p_kpi not in ('1.1','1.19.S1','1.19.24','base') then perform realisasi._invalid('kpi'); end if;
  v_unit := realisasi._forced_unit(p_unit_id);
  c := realisasi._period_ctx(p_ay_id, coalesce(p_period, 'ytd'), p_snapshot_id);
  if to_regclass('pg_temp._dd_items') is null then
    create temp table _dd_items (kpi_code text, bucket text, ref_type text, ref_id text, activity_id uuid, is_late boolean) on commit drop;
  end if;
  truncate _dd_items;
  insert into _dd_items select * from realisasi._drill_items(c, v_unit);

  if p_kpi = '1.1' then
    select coalesce(jsonb_agg(r order by r ->> 'start_date', r ->> 'code', r ->> 'bucket'), '[]'::jsonb) into v_rows from (
      select realisasi._activity_kpi_row(activity_id, bucket, count(*)::int, bool_or(is_late)) r
        from _dd_items where kpi_code = '1.1' and (p_bucket is null or bucket = p_bucket)
       group by activity_id, bucket) q;
  elsif p_kpi in ('1.19.S1','base') then
    select coalesce(jsonb_agg(r order by r ->> 'start_date', r ->> 'code'), '[]'::jsonb) into v_rows from (
      select realisasi._activity_kpi_row(activity_id, bucket, null, is_late) r
        from _dd_items where kpi_code = p_kpi and (p_bucket is null or bucket = p_bucket)) q;
  else
    select coalesce(jsonb_agg(r order by r ->> 'chain_start', (r ->> 'chain_id')::int), '[]'::jsonb) into v_rows from (
      select jsonb_build_object('row_type', 'chain', 'chain_id', ch.chain_id, 'current_document_id', ch.current_document_id,
               'current_doc_number', ch.current_doc_number, 'doc_numbers', to_jsonb(ch.doc_numbers), 'kind', ch.kind,
               'title', ch.title, 'partner_names', to_jsonb(ch.partner_names), 'country_codes', to_jsonb(ch.country_codes),
               'is_international', ch.is_international, 'chain_start', ch.chain_start, 'chain_end', ch.chain_end,
               'auto_renewed', ch.auto_renewed, 'bucket', x.b,
               'grace_until', case when x.b = 'grace_excluded' then (ch.chain_start + make_interval(months => c.grace_months))::date end,
               'activities', case when x.b = 'realized' then coalesce((
                    select jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name', a.name, 'start_date', a.start_date,
                                     'original_doc_number', d.doc_number) order by a.start_date, a.code)
                      from realisasi.activity_documents ad join realisasi.activities a on a.id = ad.activity_id
                      join kerjasama.documents d on d.id = ad.original_document_id
                     where ad.chain_id = ch.chain_id and a.status = 'verified'
                       and a.verified_at <= coalesce(c.frozen_at, realisasi.now_ts())
                       and a.start_date between c.window_start and c.cutoff
                       and (v_unit is null or exists (select 1 from realisasi.activity_units au where au.activity_id = a.id and au.unit_id = v_unit))),
                    '[]'::jsonb) else '[]'::jsonb end,
               'is_late_addition', x.late) r
        from (select ref_id::int chain_id,
                     case when bool_or(bucket = 'grace_excluded') then 'grace_excluded'
                          when bool_or(bucket = 'numerator') then 'realized' else 'not_realized' end b,
                     bool_or(is_late) late
                from _dd_items where kpi_code = '1.19.24' group by ref_id) x
        join realisasi.v_chains ch on ch.chain_id = x.chain_id
       where p_bucket is null
          or (p_bucket = 'numerator' and x.b = 'realized')
          or (p_bucket = 'denominator' and x.b in ('realized','not_realized'))
          or (p_bucket in ('realized','not_realized','grace_excluded') and x.b = p_bucket)) q;
  end if;

  return jsonb_build_object('period', realisasi._period_json(c), 'scope', realisasi._scope_json(v_unit),
                            'kpi', p_kpi, 'bucket', p_bucket, 'rows', v_rows);
end $$;

create function realisasi.kpi_participant_rows(p_ay_id int, p_period text, p_unit_id int default null,
                                               p_snapshot_id uuid default null) returns jsonb
language plpgsql volatile security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare c realisasi.period_ctx; v_unit int;
begin
  perform realisasi._require_uid();
  if realisasi.my_role() = 'submitter' then
    v_unit := realisasi.my_unit();
  elsif realisasi.in_team('mobility') then
    v_unit := p_unit_id;
  else
    perform realisasi._forbidden();
  end if;
  c := realisasi._period_ctx(p_ay_id, coalesce(p_period, 'ytd'), p_snapshot_id);
  return coalesce((select jsonb_agg(jsonb_build_object(
      'activity_id', a.id, 'code', a.code, 'name', a.name, 'direction', a.direction,
      'section', s.section, 'nrp', s.nrp, 'full_name', s.full_name, 'faculty_name', s.faculty_name, 'prodi_name', s.prodi_name,
      'home_institution', s.home_institution, 'home_country_code', s.home_country_code,
      'start_date', a.start_date, 'semester_label', realisasi.semester_label(a.semester_id))
      order by a.start_date, a.code, s.section, s.nrp)
    from realisasi._drill_items(c, v_unit) i
    join realisasi.activities a on a.id = i.activity_id
    -- M2: the version that counted at the snapshot's as-of (frozen) or the current approved one (live)
    join realisasi.participant_students s on s.set_version_id = realisasi._pset_as_of(a.id, c.frozen_at)
                                         and s.nrp = split_part(i.ref_id, ':', 2)
   where i.kpi_code = '1.1'), '[]'::jsonb);
end $$;

-- Activity detail ------------------------------------------------------------------
create function realisasi._pset_counts(p_version uuid) returns jsonb
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select jsonb_build_object('version', v.version, 'status', v.status,
    'internal_students', (select count(*) from realisasi.participant_students s where s.set_version_id = v.id and s.section = 'internal'),
    'inbound_students', (select count(*) from realisasi.participant_students s where s.set_version_id = v.id and s.section = 'inbound'),
    'staff', (select count(*) from realisasi.participant_staff s where s.set_version_id = v.id))
  from realisasi.participant_set_versions v where v.id = p_version
$$;

create function realisasi._counts_version(p_activity uuid) returns uuid
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce((select id from realisasi.participant_set_versions where activity_id = p_activity and status = 'approved'),
                  (select id from realisasi.participant_set_versions where activity_id = p_activity and status <> 'draft'
                    order by version desc limit 1))
$$;

create function realisasi.participant_counts(p_activity uuid) returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
begin
  perform realisasi._require_uid();
  if not exists (select 1 from realisasi.activities where id = p_activity) or not realisasi.can_view_activity(p_activity) then
    perform realisasi._not_found();
  end if;
  return realisasi._pset_counts(realisasi._counts_version(p_activity));
end $$;

create function realisasi._sees_draft_versions(p_activity uuid) returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select realisasi._is_unit_editor(p_activity) or realisasi.in_team('mobility')
$$;

create function realisasi.activity_detail(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare a realisasi.activities; v_role text; v_editor boolean; v_perm jsonb; v_mob boolean;
        v_m_team boolean; v_rev jsonb; v_cat realisasi.mobility_category; v_s1 boolean;
begin
  perform realisasi._require_uid();
  select * into a from realisasi.activities where id = p_id;
  if not found or not realisasi.can_view_activity(p_id) then perform realisasi._not_found(); end if;
  select mobility_category, counts_for_s1 into v_cat, v_s1 from realisasi.agenda_rules where agenda_id = a.agenda_id;
  v_mob := v_cat is not null;
  v_role := realisasi.my_role(); v_editor := realisasi._is_unit_editor(p_id);
  v_m_team := realisasi.in_team('mobility');

  v_perm := jsonb_build_object(
    'can_edit_draft', v_editor and a.status = 'draft',
    'can_delete_draft', v_editor and a.status = 'draft',
    'can_edit_detail', v_editor and (a.status = 'draft' or a.mobility_status = 'revision_requested'),
    'can_edit_files', v_editor and (a.status = 'draft' or a.mobility_status = 'revision_requested'),
    'can_edit_participants', realisasi._can_edit_participants(p_id, false),
    'can_submit', v_editor and (a.status = 'draft' or a.mobility_status = 'revision_requested'),
    'can_mobility_verify', v_m_team and a.mobility_status = 'pending' and a.status <> 'draft',
    'can_edit_verified_detail', a.status = 'verified' and v_role = 'io_admin',
    'can_edit_verified_participants', a.status = 'verified' and v_m_team and v_mob,
    'can_view_participants', realisasi.can_view_participants(p_id),
    'can_view_log', v_role <> 'viewer');

  v_rev := jsonb_build_object(
    'mobility', case when a.mobility_status = 'revision_requested' then (
        select jsonb_build_object('note', l.note, 'requested_by_name', realisasi._profile_name(l.actor_id), 'requested_at', l.created_at)
          from realisasi.activity_log l where l.activity_id = p_id and l.track = 'mobility' and l.action = 'request_revision'
         order by l.created_at desc, l.id desc limit 1) end);

  return jsonb_build_object(
    'id', a.id, 'code', a.code, 'name', a.name,
    'agenda', jsonb_build_object('id', a.agenda_id, 'name', (select name from kerjasama.agendas where id = a.agenda_id),
                                 'mobility_category', v_cat, 'is_mobility', v_mob, 'counts_for_s1', coalesce(v_s1, true)),
    'direction', a.direction,
    'start_date', a.start_date, 'end_date', a.end_date, 'duration_days', a.end_date - a.start_date + 1,
    'academic_year', (select jsonb_build_object('id', id, 'label', label) from realisasi.academic_years where id = a.academic_year_id),
    'semester', (select jsonb_build_object('id', id, 'term', term, 'label', realisasi.semester_label(id)) from realisasi.semesters where id = a.semester_id),
    'mode', a.mode, 'venue', a.venue, 'country_code', a.country_code,
    'country_name', (select name from kerjasama.countries where code = a.country_code),
    'sks_recognized', a.sks_recognized, 'description', a.description,
    'submitter_unit', (select jsonb_build_object('id', id, 'name', name) from kerjasama.units where id = a.submitter_unit_id),
    'units', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'name', u.name, 'is_submitter', au.is_submitter)
                                        order by au.is_submitter desc, u.name)
                         from realisasi.activity_units au join kerjasama.units u on u.id = au.unit_id where au.activity_id = p_id), '[]'::jsonb),
    'status', a.status, 'mobility_status', a.mobility_status, 'mobility_since', a.mobility_since,
    'submitted_at', a.submitted_at, 'verified_at', a.verified_at,
    'reporting_deadline', a.reporting_deadline, 'is_late', a.is_late,
    'documents', coalesce((select jsonb_agg(jsonb_build_object(
        'original_document_id', od.id, 'original_doc_number', od.doc_number,
        'current_document_id', cd.id, 'current_doc_number', cd.doc_number, 'kind', od.kind, 'title', od.title,
        'chain_id', ad.chain_id, 'start_date', od.start_date, 'end_date', od.end_date, 'is_archived', od.status = 'archived',
        'out_of_scope_warning', ad.out_of_scope_warning,
        'partners', coalesce((select jsonb_agg(jsonb_build_object('partner_id', p.id, 'name', p.name, 'country_code', p.country_code,
                                'country_name', co.name) order by dp.is_lead desc, p.name)
                               from kerjasama.document_partners dp join kerjasama.partners p on p.id = dp.partner_id
                               left join kerjasama.countries co on co.code = p.country_code where dp.document_id = od.id), '[]'::jsonb))
        order by od.doc_number)
      from realisasi.activity_documents ad join kerjasama.documents od on od.id = ad.original_document_id
      left join kerjasama.documents cd on cd.id = realisasi.chain_current(ad.original_document_id)
     where ad.activity_id = p_id), '[]'::jsonb),
    'partners', coalesce((select jsonb_agg(jsonb_build_object('document_id', ps.document_id, 'partner_id', ps.partner_id,
                            'partner_name', ps.partner_name, 'country_code', ps.country_code, 'country_name', co.name) order by ps.id)
                           from realisasi.activity_partner_snapshot ps left join kerjasama.countries co on co.code = ps.country_code
                          where ps.activity_id = p_id), '[]'::jsonb),
    'is_international', exists (select 1 from realisasi.activity_partner_snapshot ps where ps.activity_id = p_id and ps.country_code <> 'ID'),
    'sdg_ids', coalesce((select jsonb_agg(sdg_id order by sdg_id) from realisasi.activity_sdgs where activity_id = p_id), '[]'::jsonb),
    'external_persons', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'full_name', e.full_name, 'institution', e.institution,
                                    'country_code', e.country_code, 'role', e.role, 'notes', e.notes) order by e.id)
                                   from realisasi.activity_external_persons e where e.activity_id = p_id), '[]'::jsonb),
    -- the mobility bundle is personal data (participant readers only)
    'files', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'kind', f.kind, 'version', f.version, 'storage_path', f.storage_path,
                         'url', f.url, 'filename', f.filename, 'size_bytes', f.size_bytes, 'mime', f.mime, 'is_current', f.is_current,
                         'uploaded_by_name', realisasi._profile_name(f.uploaded_by), 'uploaded_at', f.uploaded_at,
                         'href', coalesce(case when f.storage_path is not null then realisasi._file_href(f.storage_path) end, f.url))
                         order by f.kind, f.version desc, f.id desc)
                        from realisasi.activity_files f where f.activity_id = p_id
                         and (f.kind <> 'mobility_bundle' or realisasi.can_view_participants(p_id))), '[]'::jsonb),
    'participants', jsonb_build_object(
        'can_view_rows', realisasi.can_view_participants(p_id),
        'counts', realisasi._pset_counts(realisasi._counts_version(p_id)),
        'versions', coalesce((select jsonb_agg(realisasi._pset_counts(v.id) - 'version' - 'status' || jsonb_build_object(
                         'id', v.id, 'version', v.version, 'status', v.status, 'submitted_at', v.submitted_at,
                         'submitted_by_name', realisasi._profile_name(v.submitted_by), 'reviewed_at', v.reviewed_at,
                         'reviewed_by_name', realisasi._profile_name(v.reviewed_by), 'review_note', v.review_note) order by v.version)
                       from realisasi.participant_set_versions v
                      where v.activity_id = p_id and (v.status <> 'draft' or realisasi._sees_draft_versions(p_id))), '[]'::jsonb)),
    'revision', v_rev,
    'log', case when v_role = 'viewer' then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object(
              'id', l.id, 'kind', l.kind, 'track', l.track, 'action', l.action, 'actor_name', realisasi._profile_name(l.actor_id),
              'note', l.note,
              'diff', case when realisasi.can_view_participants(p_id) then l.diff else realisasi._mask_log_diff(l.diff) end,   -- M6
              'in_frozen_period', l.in_frozen_period, 'created_at', l.created_at)
              order by l.created_at desc, l.id desc) from realisasi.activity_log l where l.activity_id = p_id), '[]'::jsonb) end,
    'conflicts', case when v_m_team then realisasi.conflict_list(p_id, null) else '[]'::jsonb end,
    'flags', jsonb_build_object('late', a.is_late,
              'out_of_scope', exists (select 1 from realisasi.activity_documents where activity_id = p_id and out_of_scope_warning),
              'conflicts_open', case when v_m_team then realisasi.activity_open_conflicts(p_id) else 0 end,
              'late_addition', realisasi.is_late_addition(p_id)),
    'checklist', case when (v_perm ->> 'can_submit')::boolean then realisasi._checklist(p_id) end,
    'permissions', v_perm);
end $$;

create function realisasi.participant_version(p_activity uuid, p_version int default null) returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v realisasi.participant_set_versions; v_drafts boolean;
begin
  perform realisasi._require_uid();
  if not exists (select 1 from realisasi.activities where id = p_activity) or not realisasi.can_view_participants(p_activity) then
    perform realisasi._forbidden();
  end if;
  v_drafts := realisasi._sees_draft_versions(p_activity);
  select * into v from realisasi.participant_set_versions
   where activity_id = p_activity and (p_version is null or version = p_version) and (status <> 'draft' or v_drafts)
   order by version desc limit 1;
  if not found then
    if p_version is not null then perform realisasi._not_found(); end if;
    return null;
  end if;
  return jsonb_build_object('id', v.id, 'activity_id', v.activity_id, 'version', v.version, 'status', v.status,
    'submitted_at', v.submitted_at, 'submitted_by_name', realisasi._profile_name(v.submitted_by),
    'reviewed_at', v.reviewed_at, 'reviewed_by_name', realisasi._profile_name(v.reviewed_by), 'review_note', v.review_note,
    'students', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'section', s.section, 'nrp', s.nrp, 'full_name', s.full_name,
                  'faculty_name', s.faculty_name, 'prodi_name', s.prodi_name, 'home_institution', s.home_institution,
                  'home_student_number', s.home_student_number, 'home_country_code', s.home_country_code,
                  'registry_status', coalesce(b.status, 'inactive'))
                  order by s.section, s.id)
                 from realisasi.participant_students s left join mock_baak.students b on b.nrp = s.nrp
                where s.set_version_id = v.id), '[]'::jsonb),
    'staff', coalesce((select jsonb_agg(jsonb_build_object('id', st.id, 'employee_id', st.employee_id, 'full_name', st.full_name,
                  'unit_name', st.unit_name, 'registry_status', coalesce(e.status, 'inactive')) order by st.id)
                 from realisasi.participant_staff st left join mock_hr.employees e on e.employee_id = st.employee_id
                where st.set_version_id = v.id), '[]'::jsonb));
end $$;

create function realisasi.nav_counts() returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_uid();
begin
  return jsonb_build_object(
    'mobility_queue', case when realisasi.in_team('mobility') then
        (select count(*) from realisasi.activities where mobility_status = 'pending' and status <> 'draft') else 0 end,
    'conflicts_open', case when realisasi.in_team('mobility') then
        (select count(*) from realisasi.participant_conflicts where status = 'open') else 0 end,
    'revision_inbox', case when realisasi.my_role() = 'submitter' then
        (select count(*) from realisasi.activities where status = 'revision_requested' and submitter_unit_id = realisasi.my_unit()) else 0 end,
    'unread_notifications', (select count(*) from realisasi.notifications where recipient_id = v_uid and read_at is null));
end $$;

-- Agreements -----------------------------------------------------------------------
create function realisasi.agreement_realization(p_document_id int) returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare d kerjasama.documents; v_chain int; ch record; ay realisasi.academic_years; v_io boolean; v_grace int;
        v_acts uuid[]; v_in_grace boolean;
begin
  perform realisasi._require_uid();
  select * into d from kerjasama.documents where id = p_document_id;
  if not found then perform realisasi._not_found(); end if;
  v_io := realisasi.is_io();
  v_chain := realisasi.chain_root(d.id);
  select * into ch from realisasi.v_chains where chain_id = v_chain;
  select * into ay from realisasi.academic_years where id = realisasi._resolve_ay(null);
  v_grace := coalesce(realisasi.setting_int('grace_period_months'), 6);
  select coalesce(array_agg(distinct a.id), '{}') into v_acts
    from realisasi.activity_documents ad join realisasi.activities a on a.id = ad.activity_id
   where ad.chain_id = v_chain and (case when v_io then a.status <> 'draft' else a.status = 'verified' end);
  v_in_grace := ch.chain_id is not null and not ch.auto_renewed
                and ch.chain_start > (realisasi.today() - make_interval(months => v_grace))::date;

  return jsonb_build_object(
    'document', jsonb_build_object('id', d.id, 'doc_number', d.doc_number, 'title', d.title, 'kind', d.kind, 'status', d.status,
                                   'start_date', d.start_date, 'end_date', d.end_date, 'auto_renewed', d.auto_renewed),
    'chain', jsonb_build_object('chain_id', v_chain, 'chain_start', ch.chain_start, 'chain_end', ch.chain_end,
               'auto_renewed', coalesce(ch.auto_renewed, d.auto_renewed), 'is_international', coalesce(ch.is_international, false),
               'documents', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'doc_number', x.doc_number, 'kind', x.kind,
                               'status', x.status, 'start_date', x.start_date, 'end_date', x.end_date, 'predecessor_id', x.predecessor_id)
                               order by x.start_date nulls last, x.id)
                              from kerjasama.documents x join realisasi._chain_map() m on m.doc_id = x.id and m.root_id = v_chain), '[]'::jsonb)),
    'current_ay', case when ay.id is not null then jsonb_build_object('id', ay.id, 'label', ay.label) end,
    'summary', jsonb_build_object(
        'total_activities', cardinality(v_acts),
        'activities_this_ay', (select count(*) from realisasi.activities a where a.id = any(v_acts)
                                and a.start_date between ay.start_date and ay.end_date),
        'students_inbound', (select count(distinct (s.nrp, a.id)) from realisasi.activities a
                               join realisasi.agenda_rules t on t.agenda_id = a.agenda_id and t.mobility_category is not null
                               join realisasi.participant_set_versions v on v.activity_id = a.id and v.status = 'approved'
                               join realisasi.participant_students s on s.set_version_id = v.id and s.section = 'inbound'
                              where a.id = any(v_acts) and a.status = 'verified' and a.direction = 'inbound'),
        'students_outbound', (select count(distinct (s.nrp, a.id)) from realisasi.activities a
                               join realisasi.agenda_rules t on t.agenda_id = a.agenda_id and t.mobility_category is not null
                               join realisasi.participant_set_versions v on v.activity_id = a.id and v.status = 'approved'
                               join realisasi.participant_students s on s.set_version_id = v.id and s.section = 'internal'
                              where a.id = any(v_acts) and a.status = 'verified' and a.direction = 'outbound'),
        'last_activity_date', (select max(a.start_date) from realisasi.activities a where a.id = any(v_acts) and a.status = 'verified')),
    'grace', jsonb_build_object('in_grace', v_in_grace,
               'grace_until', case when v_in_grace then (ch.chain_start + make_interval(months => v_grace))::date end),
    'activities', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name', a.name, 'agenda_name', g.name,
                     'start_date', a.start_date, 'end_date', a.end_date, 'status', a.status,
                     'unit_names', coalesce((select jsonb_agg(u.name order by au.is_submitter desc, u.name) from realisasi.activity_units au
                                              join kerjasama.units u on u.id = au.unit_id where au.activity_id = a.id), '[]'::jsonb),
                     'original_doc_number', od.doc_number,
                     'current_doc_number', (select doc_number from kerjasama.documents where id = realisasi.chain_current(od.id)))
                     order by a.start_date, a.code)
                    from realisasi.activities a left join kerjasama.agendas g on g.id = a.agenda_id
                    join realisasi.activity_documents ad on ad.activity_id = a.id and ad.chain_id = v_chain
                    join kerjasama.documents od on od.id = ad.original_document_id
                   where a.id = any(v_acts) and (v_io or realisasi.can_view_activity(a.id))), '[]'::jsonb));   -- M7: list only visible ones
end $$;

create function realisasi.agreement_flags(p_ay_id int default null) returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare ay realisasi.academic_years; v_cut date; v_grace int := coalesce(realisasi.setting_int('grace_period_months'), 6);
begin
  perform realisasi._require_uid();
  select * into ay from realisasi.academic_years where id = realisasi._resolve_ay(p_ay_id);
  if not found then perform realisasi._not_found(); end if;
  v_cut := least(ay.end_date, realisasi.today());
  return coalesce((select jsonb_agg(jsonb_build_object('document_id', d.id, 'chain_id', x.chain_id,
      'flag', case when ch.chain_id is null or d.status in ('in_process','rejected')
                     or not (ch.chain_start <= v_cut and ((ch.auto_renewed and ch.terminated_at is null) or ch.chain_end >= ay.start_date)) then 'inactive'
                   when not ch.auto_renewed and ch.chain_start > (v_cut - make_interval(months => v_grace))::date then 'grace'
                   when x.n_win > 0 then 'realized' else 'not_realized' end,
      'grace_until', case when ch.chain_id is not null and not ch.auto_renewed
                           and ch.chain_start > (v_cut - make_interval(months => v_grace))::date
                          then (ch.chain_start + make_interval(months => v_grace))::date end,
      'activities_this_ay', x.n_ay, 'last_activity_date', x.last_date) order by d.id)
    -- H6: chain roots and per-chain activity stats computed once (set-based), not per document
    from kerjasama.documents d
    left join realisasi._chain_map() r on r.doc_id = d.id
    left join (
      select ad.chain_id,
             count(distinct a.id) filter (where a.start_date between ay.start_date and v_cut) as n_win,
             count(distinct a.id) filter (where a.start_date between ay.start_date and ay.end_date) as n_ay,
             max(a.start_date) as last_date
        from realisasi.activity_documents ad join realisasi.activities a on a.id = ad.activity_id and a.status = 'verified'
       group by ad.chain_id) st on st.chain_id = r.root_id
    cross join lateral (select r.root_id as chain_id, coalesce(st.n_win, 0) as n_win, coalesce(st.n_ay, 0) as n_ay, st.last_date) x
    left join realisasi.v_chains ch on ch.chain_id = x.chain_id), '[]'::jsonb);
end $$;

-- Snapshot archive -----------------------------------------------------------------
create function realisasi._snapshot_row(p_snapshot uuid, p_unit_id int) returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare s realisasi.kpi_snapshots; ay realisasi.academic_years; v jsonb; e jsonb;
begin
  select * into s from realisasi.kpi_snapshots where id = p_snapshot;
  select * into ay from realisasi.academic_years where id = s.academic_year_id;
  v := s.values;
  if p_unit_id is not null then
    select x into e from jsonb_array_elements(v -> 'by_unit') x where (x ->> 'unit_id')::int = p_unit_id;
    v := coalesce(e, '{}'::jsonb);
  end if;
  return jsonb_build_object('id', s.id, 'ay_id', ay.id, 'ay_label', ay.label, 'kind', s.kind,
    'label', realisasi._snapshot_label(s.kind, ay.label),
    'window_start', s.window_start, 'window_end', s.window_end, 'cutoff_date', s.cutoff_date,
    'frozen_at', s.frozen_at, 'frozen_by_name', coalesce(realisasi._profile_name(s.frozen_by), 'Job terjadwal'),
    'is_live', s.superseded_by is null, 'superseded_by', s.superseded_by, 'refreeze_reason', s.refreeze_reason,
    'summary', jsonb_build_object('kpi_1_1_total', coalesce((v #>> '{kpi_1_1,total}')::int, 0),
                                  'kpi_1_19_s1_international', coalesce((v #>> '{kpi_1_19_s1,international}')::int, 0),
                                  'kpi_1_19_24_pct', v #> '{kpi_1_19_24,all,pct}'),
    'late_additions', jsonb_array_length(realisasi._snapshot_late_additions(s.id)),
    'post_freeze_changes', jsonb_array_length(realisasi._snapshot_post_freeze_changes(s.id)));
end $$;

create function realisasi.snapshot_list(p_ay_id int default null) returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_unit int;
begin
  perform realisasi._require_uid();
  v_unit := case when realisasi.my_role() = 'submitter' then realisasi.my_unit() end;
  return coalesce((select jsonb_agg(realisasi._snapshot_row(s.id, v_unit) order by s.frozen_at desc, s.id)
                     from realisasi.kpi_snapshots s where p_ay_id is null or s.academic_year_id = p_ay_id), '[]'::jsonb);
end $$;

create function realisasi.snapshot_detail(p_snapshot uuid) returns jsonb
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare s realisasi.kpi_snapshots;
begin
  perform realisasi._require_report_reader();
  select * into s from realisasi.kpi_snapshots where id = p_snapshot;
  if not found then perform realisasi._not_found(); end if;
  return jsonb_build_object('snapshot', realisasi._snapshot_row(s.id, null), 'values', s.values, 'settings_used', s.settings_used,
    'late_additions', realisasi._snapshot_late_additions(s.id), 'post_freeze_changes', realisasi._snapshot_post_freeze_changes(s.id));
end $$;

-- International Awards (Revisi V.1) -----------------------------------------------------------------------------
-- Four leaderboards per SUBMITTING unit for a period context, built on the same verified items as KPI 1.1 (so the
-- conflict decisions of rule 2.1 apply): students by mobility category for inbound, outbound domestic (activity country
-- Indonesia) and outbound international, plus international initiatives (activities with a foreign partner or held
-- abroad). "Kegiatan Internasional (<14 hari)" = students of a mobility kegiatan lasting under 14 days whose category is
-- none of JD/DD, Student Exchange, Short/Summer, so every student is in one column only. total = sum of the columns.
create function realisasi.international_awards(p_ay_id int default null, p_period text default 'ytd', p_unit_id int default null)
returns jsonb
language plpgsql volatile security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare c realisasi.period_ctx; v_unit int;
begin
  perform realisasi._require_uid();
  v_unit := realisasi._forced_unit(p_unit_id);
  c := realisasi._period_ctx(p_ay_id, coalesce(p_period, 'ytd'));
  if to_regclass('pg_temp._aw_items') is null then
    create temp table _aw_items (su int, kpi_code text, bucket text, ref_type text, ref_id text, activity_id uuid, is_intl boolean) on commit drop;
  end if;
  truncate _aw_items;
  insert into _aw_items
  select * from realisasi._kpi_items_scoped(c.window_start, c.window_end, c.cutoff, c.frozen_at, 'all', null, c.grace_months) i
   where i.su is not null and i.kpi_code in ('1.1','base');

  return jsonb_build_object('period', realisasi._period_json(c), 'scope', realisasi._scope_json(v_unit),
    'inbound', realisasi._awards_students(v_unit, 'inbound', null),
    'outbound_domestic', realisasi._awards_students(v_unit, 'outbound', false),
    'outbound_international', realisasi._awards_students(v_unit, 'outbound', true),
    'initiatives', coalesce((select jsonb_agg(to_jsonb(x) order by x.total desc, x.unit_name) from (
        select a.submitter_unit_id as unit_id, u.name as unit_name,
               count(*) filter (where a.direction = 'inbound' and r.mobility_category is not null)::int as inbound,
               count(*) filter (where a.direction = 'outbound' and r.mobility_category is not null)::int as outbound,
               count(*) filter (where r.mobility_category is null)::int as activities,
               count(*)::int as total
          from _aw_items i
          join realisasi.activities a on a.id = i.activity_id and a.submitter_unit_id = i.su
          left join realisasi.agenda_rules r on r.agenda_id = a.agenda_id
          left join kerjasama.units u on u.id = a.submitter_unit_id
         where i.kpi_code = 'base' and (v_unit is null or i.su = v_unit)
           and (coalesce(a.country_code <> 'ID', false)
                or exists (select 1 from realisasi.activity_partner_snapshot ps where ps.activity_id = a.id and ps.country_code <> 'ID'))
         group by a.submitter_unit_id, u.name) x), '[]'::jsonb));
end $$;

-- one student leaderboard from _aw_items (internal; p_intl null = any country)
create function realisasi._awards_students(p_unit int, p_direction text, p_intl boolean) returns jsonb
language plpgsql volatile security definer set search_path = realisasi, extensions, public, pg_temp as $$
begin
  return (select coalesce(jsonb_agg(to_jsonb(x) order by x.total desc, x.unit_name), '[]'::jsonb) from (
    select unit_id, unit_name, jd_dd, student_exchange, short_summer, short_international,
           jd_dd + student_exchange + short_summer + short_international as total
      from (
        select a.submitter_unit_id as unit_id, u.name as unit_name,
               count(*) filter (where r.mobility_category = 'jd_dd')::int as jd_dd,
               count(*) filter (where r.mobility_category = 'student_exchange')::int as student_exchange,
               count(*) filter (where r.mobility_category = 'short_summer')::int as short_summer,
               count(*) filter (where r.mobility_category = 'other_mobility' and a.end_date - a.start_date + 1 < 14)::int
                 as short_international
          from _aw_items i
          join realisasi.activities a on a.id = i.activity_id and a.submitter_unit_id = i.su
          join realisasi.agenda_rules r on r.agenda_id = a.agenda_id
          left join kerjasama.units u on u.id = a.submitter_unit_id
         where i.kpi_code = '1.1' and i.bucket = p_direction and (p_unit is null or i.su = p_unit)
           and (p_intl is null
                or p_intl = coalesce(a.country_code <> 'ID',
                                     exists (select 1 from realisasi.activity_partner_snapshot ps
                                              where ps.activity_id = a.id and ps.country_code <> 'ID')))
         group by a.submitter_unit_id, u.name) y
     where jd_dd + student_exchange + short_summer + short_international > 0) x);
end $$;

commit;
select 'part 4 of 5 OK - now run part 5' as status;
