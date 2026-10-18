-- LIVE PATCH for simks-partnership (2026-10-18), same text as the migrations of this commit:
--   0002_tables.sql   realisasi.renstra_targets (Target RENSTRA per unit / indicator / academic year),
--   0006_rls.sql      its select policy, 0011_rpc_admin.sql realisasi.set_renstra_targets, 0016_grants.sql grants.
-- Only for an install made before this commit; a fresh install/reset already has it. Additive only (no drop, no data
-- change), one transaction, safe to run through the Supabase connector or the SQL Editor.
begin;
create table realisasi.renstra_targets (
  academic_year_id int not null references realisasi.academic_years(id),
  renstra_key      text not null check (renstra_key in ('1.1','1.1.a','1.1.b','1.19.S1','1.19.S4')),
  unit_id          int not null default 0,  -- kerjasama.units.id (no FK: adapter view); 0 = Universitas
  target           numeric not null check (target >= 0),
  updated_by       uuid,  -- kerjasama.profiles.id (no FK: adapter view)
  updated_at       timestamptz default now(),
  primary key (academic_year_id, renstra_key, unit_id),
  check (renstra_key <> '1.19.S4' or (unit_id = 0 and target <= 100))
);
alter table realisasi.renstra_targets enable row level security;
create policy renstra_targets_select on realisasi.renstra_targets for select to authenticated using (true);

-- RENSTRA targets for one academic year and indicator. p_rows: [{unit_id: int (0 = Universitas), target: number|null}];
-- a null target removes that unit's target. 1.19.S4 takes only the Universitas row, as a percentage (0..100).
create function realisasi.set_renstra_targets(p_ay int, p_key text, p_rows jsonb) returns int
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_uid uuid := realisasi._require_admin(); e jsonb; v_unit int; v_target numeric; n int := 0;
begin
  if p_key is null or p_key not in ('1.1','1.1.a','1.1.b','1.19.S1','1.19.S4') then perform realisasi._invalid('renstra_key'); end if;
  if not exists (select 1 from realisasi.academic_years where id = p_ay) then perform realisasi._not_found(); end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then perform realisasi._invalid('rows'); end if;
  for e in select * from jsonb_array_elements(p_rows) loop
    begin
      v_unit := (e ->> 'unit_id')::int;
      v_target := (e ->> 'target')::numeric;
    exception when others then
      perform realisasi._invalid('target');
    end;
    if v_unit is null or (v_unit <> 0 and not exists (select 1 from kerjasama.units where id = v_unit)) then
      perform realisasi._invalid('unit_id');
    end if;
    if p_key = '1.19.S4' and v_unit <> 0 then perform realisasi._invalid('unit_id'); end if;
    if v_target is null then
      delete from realisasi.renstra_targets where academic_year_id = p_ay and renstra_key = p_key and unit_id = v_unit;
    else
      if v_target < 0 or (p_key = '1.19.S4' and v_target > 100) then perform realisasi._invalid('target'); end if;
      insert into realisasi.renstra_targets (academic_year_id, renstra_key, unit_id, target, updated_by, updated_at)
      values (p_ay, p_key, v_unit, v_target, v_uid, realisasi.now_ts())
      on conflict (academic_year_id, renstra_key, unit_id) do update set target = excluded.target,
         updated_by = excluded.updated_by, updated_at = excluded.updated_at;
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;

revoke execute on function realisasi.set_renstra_targets(int, text, jsonb) from public;
grant select on realisasi.renstra_targets to authenticated;
grant execute on function realisasi.set_renstra_targets(int, text, jsonb) to authenticated;
commit;
