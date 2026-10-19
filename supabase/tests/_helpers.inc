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
-- Since Revisi V.1 (2026-10-05) every KUI account is io_admin in the demo seed. The acceptance tests still cover the
-- io_staff role (Mobility team without admin rights): PART and MOB act as io_staff inside this rolled-back transaction.
update realisasi.account_roles set app_role = 'io_staff' where akun_id in (2, 3);
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
-- SIMKS fixture helpers (local stub tables; run as superuser). Proposal id = document no + 1000, as in seed/00_kerjasama.sql.
-- p_status is the SIMKS status ('Aktif' | 'Akan Berakhir' | 'Diarsipkan' | anything else = in process).
create function pg_temp.simks_doc(p_no int, p_number text, p_kind text, p_status text, p_start date, p_end date,
                                  p_prev_no int default null, p_alasan text default null, p_title text default null,
                                  p_auto_renewed boolean default null, p_terminated_at timestamptz default null,
                                  p_partners int[] default '{}', p_units int[] default '{}') returns void language plpgsql as $$
begin
  insert into public.proposal_dokumen (id, jenis_kerjasama, tujuan_kerjasama, id_dokumen_sebelumnya, sifat_periode_kerjasama)
  values (p_no + 1000, p_kind::public.jenis_kerjasama, p_title, p_prev_no + 1000, 'Kedua Belah Pihak');
  insert into public.dokumen_kerja_sama (no, id_proposal_dokumen, no_dokumen, tanggal_mulai, tanggal_berakhir, status, alasan_arsip)
  values (p_no, p_no + 1000, p_number, p_start, p_end, p_status, p_alasan);
  insert into public.partner_pengusul (id_proposal_dokumen, id_partner, is_lead)
  select p_no + 1000, x, o = 1 from unnest(p_partners) with ordinality u(x, o);
  insert into public.proposal_dokumen_unit (id_proposal_dokumen, id_unit) select p_no + 1000, x from unnest(p_units) x;
  if p_auto_renewed is not null or p_terminated_at is not null then
    insert into realisasi.document_overrides (document_id, auto_renewed, terminated_at)
    values (p_no, coalesce(p_auto_renewed, false), p_terminated_at);
  end if;
end $$;
-- make document p_no a renewal of p_prev_no (SIMKS links the predecessor's PROPOSAL id)
create function pg_temp.simks_set_prev(p_no int, p_prev_no int) returns void language sql as $$
  update public.proposal_dokumen p set id_dokumen_sebelumnya = (select id_proposal_dokumen from public.dokumen_kerja_sama where no = p_prev_no)
   where p.id = (select id_proposal_dokumen from public.dokumen_kerja_sama where no = p_no) $$;
grant execute on all functions in schema pg_temp to authenticated;
