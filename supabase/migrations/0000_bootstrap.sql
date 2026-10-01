-- 0000_bootstrap: extensions, Supabase-compatible roles, auth.uid() stub, SIM Kerjasama public stubs.
-- Safe on a real Supabase project: every object is created only when absent.
create extension if not exists pgcrypto;
create extension if not exists pg_trgm;

do $$
begin
  if not exists (select from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
end $$;

-- auth.uid() stub (only when Supabase Auth is not present)
do $$
begin
  if to_regprocedure('auth.uid()') is null then
    create schema if not exists auth;
    execute $f$
      create function auth.uid() returns uuid language sql stable as $b$
        select nullif(coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                               nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'), '')::uuid
      $b$ $f$;
    grant usage on schema auth to authenticated, anon;
    grant execute on function auth.uid() to authenticated, anon;
  end if;
end $$;

-- SIM Kerjasama stubs (read-only for Realisasi)
create table if not exists public.units (
  id int primary key, name text not null, parent_id int references public.units(id),
  kind text not null check (kind in ('faculty','prodi','program','up')));
create table if not exists public.countries (code text primary key, name text not null);
create table if not exists public.partners (
  id int primary key, name text not null, country_code text not null references public.countries(code));
create table if not exists public.documents (
  id int primary key, doc_number text not null unique, title text not null,
  kind text not null check (kind in ('MoU','MoA')),
  status text not null check (status in ('active','archived','in_process','rejected')),
  start_date date, end_date date, auto_renewed boolean not null default false,
  predecessor_id int references public.documents(id), parent_id int references public.documents(id),
  archived_reason text, terminated_at timestamptz);
create table if not exists public.document_partners (
  document_id int references public.documents(id), partner_id int references public.partners(id),
  is_lead boolean not null default false, primary key (document_id, partner_id));
create table if not exists public.document_scope_units (
  document_id int references public.documents(id), unit_id int references public.units(id),
  primary key (document_id, unit_id));
create table if not exists public.profiles (
  id uuid primary key, email text not null unique, display_name text not null,
  app_role text not null check (app_role in ('submitter','io_staff','io_admin','viewer')),
  unit_id int references public.units(id));

create index if not exists documents_predecessor_idx on public.documents (predecessor_id);
create index if not exists document_partners_partner_idx on public.document_partners (partner_id);
create index if not exists document_scope_units_unit_idx on public.document_scope_units (unit_id);
create index if not exists profiles_unit_idx on public.profiles (unit_id);

grant usage on schema public to authenticated, anon;
grant select on public.units, public.countries, public.partners, public.documents,
                public.document_partners, public.document_scope_units, public.profiles to authenticated;
