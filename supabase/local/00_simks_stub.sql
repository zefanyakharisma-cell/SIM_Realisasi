-- LOCAL ONLY (never applied to Supabase). Recreates the slice of the SIM Kerjasama (simks-partnership) schema that the
-- Realisasi adapter (migration 0001_kerjasama_adapter) reads, with the same table/column names and types as SIMKS, plus
-- the Supabase pieces that a bare Postgres lacks (roles anon/authenticated/service_role, auth.uid()).
-- scripts/db-reset.sh applies supabase/local/*.sql BEFORE the migrations; scripts/db-deploy-supabase.sh never does.
-- Columns SIMKS has but the adapter does not read are omitted. Idempotent (create … if not exists).

-- Supabase roles ------------------------------------------------------------------------------------------------
do $$
begin
  if not exists (select from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
end $$;

-- auth.uid() stub, same form as Supabase's (tolerates an empty request.jwt.claims GUC) -------------------------
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

-- SIMKS tables (public schema, owned by SIMKS) --------------------------------------------------------------------
do $$
begin
  -- SIMKS stores jenis_kerjasama as a user-defined enum; the adapter only ever reads it as ::text, so the type name
  -- does not matter.
  if to_regtype('public.jenis_kerjasama') is null then
    create type public.jenis_kerjasama as enum ('MoU', 'MoA');
  end if;
end $$;

create table if not exists public.jenis_unit (
  id    integer primary key,
  jenis character varying not null
);

create table if not exists public.unit (
  id             integer primary key,
  nama           character varying not null,
  id_parent_unit integer references public.unit(id),
  id_jenis_unit  integer references public.jenis_unit(id),
  is_active      boolean not null default true
);

create table if not exists public.negara (
  id          integer primary key,
  kode        character varying not null,          -- ISO 3166-1 alpha-3 (IDN, JPN, …)
  nama        character varying not null,
  is_domestic boolean not null default false,
  latitude    numeric,
  longitude   numeric,
  is_active   boolean not null default true
);

create table if not exists public.partner (
  id               integer primary key,
  nama             character varying not null,
  is_international boolean not null default true,
  id_negara        integer references public.negara(id),
  kota             character varying,
  id_merged_into   integer references public.partner(id),
  is_active        boolean not null default true
);

create table if not exists public.proposal_dokumen (
  id                      integer primary key,
  jenis_kerjasama         public.jenis_kerjasama not null,
  periode_kerjasama       character varying,
  sifat_periode_kerjasama character varying,
  status_proposal         character varying,
  tujuan_kerjasama        text,
  id_dokumen_sebelumnya   integer,                  -- the PREDECESSOR'S PROPOSAL id (not dokumen_kerja_sama.no)
  waktu_dibuat            timestamptz default now()
);

create table if not exists public.dokumen_kerja_sama (
  no                  integer primary key,
  id_proposal_dokumen integer references public.proposal_dokumen(id),
  no_dokumen          character varying,           -- null for rejected proposals
  tanggal_mulai       date,
  tanggal_berakhir    date,
  status              character varying,           -- 'Aktif' | 'Akan Berakhir' | 'Diarsipkan'
  alasan_arsip        character varying,           -- null | 'rejected' | 'superseded_by_renewal' | 'expired_without_renewal'
  waktu_dibuat        timestamptz default now()
);
create index if not exists dokumen_kerja_sama_proposal_idx on public.dokumen_kerja_sama (id_proposal_dokumen);

create table if not exists public.partner_pengusul (
  id_partner          integer references public.partner(id),
  id_proposal_dokumen integer references public.proposal_dokumen(id),
  is_lead             boolean,
  primary key (id_proposal_dokumen, id_partner)
);

create table if not exists public.proposal_dokumen_unit (
  id_proposal_dokumen integer references public.proposal_dokumen(id),
  id_unit             integer references public.unit(id),
  primary key (id_proposal_dokumen, id_unit)
);

create table if not exists public.jabatan (
  id        integer primary key,
  nama      character varying not null,
  id_unit   integer references public.unit(id),
  is_active boolean not null default true
);

create table if not exists public.akun (
  id           integer primary key,
  auth_user_id uuid,
  id_jabatan   integer references public.jabatan(id),
  email        character varying not null,
  role         character varying,                  -- SIMKS roles: admin | approver | user | user_staff (not Realisasi roles)
  is_active    boolean not null default true
);

-- SIMKS protects its tables with RLS. Mirror that locally with RLS on and no grants/policies for the API roles, so a
-- Realisasi session (role authenticated) can only reach SIMKS data through the kerjasama adapter views.
do $$
declare t text;
begin
  foreach t in array array['jenis_unit','unit','negara','partner','proposal_dokumen','dokumen_kerja_sama',
                           'partner_pengusul','proposal_dokumen_unit','jabatan','akun'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;
