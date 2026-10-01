-- shared test helpers (included with \ir; not a test file itself)
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on
\pset format unaligned
\o /dev/null
\set ADMIN '00000000-0000-4000-8000-000000000001'
\set PART  '00000000-0000-4000-8000-000000000002'
\set MOB   '00000000-0000-4000-8000-000000000003'
\set FTI   '00000000-0000-4000-8000-000000000004'
\set FBE   '00000000-0000-4000-8000-000000000005'
\set INF   '00000000-0000-4000-8000-000000000006'
\set FSD   '00000000-0000-4000-8000-000000000007'
\set VIEW  '00000000-0000-4000-8000-000000000008'
-- act as a user exactly like lib/db.ts withUser(): claims + role switch inside the transaction
\set as_admin 'reset role; select set_config(''request.jwt.claims'', json_build_object(''sub'', ''00000000-0000-4000-8000-000000000001'', ''role'', ''authenticated'')::text, true); set local role authenticated;'
\set as_part  'reset role; select set_config(''request.jwt.claims'', json_build_object(''sub'', ''00000000-0000-4000-8000-000000000002'', ''role'', ''authenticated'')::text, true); set local role authenticated;'
\set as_mob   'reset role; select set_config(''request.jwt.claims'', json_build_object(''sub'', ''00000000-0000-4000-8000-000000000003'', ''role'', ''authenticated'')::text, true); set local role authenticated;'
\set as_fti   'reset role; select set_config(''request.jwt.claims'', json_build_object(''sub'', ''00000000-0000-4000-8000-000000000004'', ''role'', ''authenticated'')::text, true); set local role authenticated;'
\set as_fbe   'reset role; select set_config(''request.jwt.claims'', json_build_object(''sub'', ''00000000-0000-4000-8000-000000000005'', ''role'', ''authenticated'')::text, true); set local role authenticated;'
\set as_inf   'reset role; select set_config(''request.jwt.claims'', json_build_object(''sub'', ''00000000-0000-4000-8000-000000000006'', ''role'', ''authenticated'')::text, true); set local role authenticated;'
\set as_fsd   'reset role; select set_config(''request.jwt.claims'', json_build_object(''sub'', ''00000000-0000-4000-8000-000000000007'', ''role'', ''authenticated'')::text, true); set local role authenticated;'
\set as_view  'reset role; select set_config(''request.jwt.claims'', json_build_object(''sub'', ''00000000-0000-4000-8000-000000000008'', ''role'', ''authenticated'')::text, true); set local role authenticated;'
\set as_system 'reset role; select set_config(''request.jwt.claims'', '''', true);'

begin;
-- assertion: raises on failure, NOTICE 'ok - <name>' on success (counted by scripts/db-test.sh)
create function pg_temp.ok(p_cond boolean, p_name text) returns void language plpgsql as $$
begin
  if p_cond is not true then raise exception 'FAILED: % (got %)', p_name, coalesce(p_cond::text, 'null'); end if;
  raise notice 'ok - %', p_name;
end $$;
create function pg_temp.eq(p_got anyelement, p_want anyelement, p_name text) returns void language plpgsql as $$
begin
  if p_got is distinct from p_want then raise exception 'FAILED: % (got %, want %)', p_name, p_got, p_want; end if;
  raise notice 'ok - %', p_name;
end $$;
-- run SQL in a subtransaction; return the error message ('' when it succeeded). Effects of a failing call are rolled back.
create function pg_temp.err(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return '';
exception when others then
  return sqlerrm;
end $$;
-- run SQL expecting an error whose message starts with '<code>:'
create function pg_temp.throws(p_sql text, p_code text, p_name text) returns void language plpgsql as $$
declare v text := pg_temp.err(p_sql);
begin
  if v not like p_code || ':%' then raise exception 'FAILED: % (expected %, got "%")', p_name, p_code, v; end if;
  raise notice 'ok - % (%)', p_name, p_code;
end $$;
-- error detail (json) of a failing call
create function pg_temp.err_detail(p_sql text) returns jsonb language plpgsql as $$
declare v_detail text;
begin
  execute p_sql;
  return null;
exception when others then
  get stacked diagnostics v_detail = pg_exception_detail;
  return nullif(v_detail, '')::jsonb;
end $$;
create function pg_temp.aid(n int) returns uuid language sql immutable as $$
  select ('a0000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
grant execute on all functions in schema pg_temp to authenticated;
