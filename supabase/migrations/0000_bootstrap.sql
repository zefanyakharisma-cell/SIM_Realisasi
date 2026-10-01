-- 0000_bootstrap: extensions + preconditions. Creates nothing in schema public.
-- Realisasi is deployed INTO the SIM Kerjasama Supabase project (PRD D18). It expects what that project already has:
--   * roles anon / authenticated / service_role and auth.uid()   (Supabase; locally: supabase/local/00_simks_stub.sql)
--   * the SIMKS tables in public read by 0001_kerjasama_adapter (locally: the same stub file)
-- Fail fast with a clear message when they are missing instead of creating look-alikes.
create extension if not exists pgcrypto;
create extension if not exists pg_trgm;

do $$
declare r text; t text; missing text[] := '{}';
begin
  foreach r in array array['anon','authenticated','service_role'] loop
    if not exists (select from pg_roles where rolname = r) then missing := missing || ('role ' || r); end if;
  end loop;
  if to_regprocedure('auth.uid()') is null then missing := missing || 'function auth.uid()'::text; end if;
  foreach t in array array['unit','jenis_unit','negara','partner','proposal_dokumen','dokumen_kerja_sama',
                           'partner_pengusul','proposal_dokumen_unit','jabatan','akun'] loop
    if to_regclass('public.' || t) is null then missing := missing || ('table public.' || t); end if;
  end loop;
  if cardinality(missing) > 0 then
    raise exception 'SIM Realisasi needs the SIM Kerjasama (Supabase) database; missing: %', array_to_string(missing, ', ')
      using hint = 'Locally, apply supabase/local/*.sql first (scripts/db-reset.sh does this).';
  end if;
end $$;
