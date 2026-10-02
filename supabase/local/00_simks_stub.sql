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

-- Agenda Kerjasama (SIMKS master list; Realisasi uses it as Jenis Kegiatan). Rows = the live list as of 2026-10-02.
create table if not exists public.agenda (
  id           integer primary key,
  nama         character varying not null,
  is_amendment boolean not null default false,
  is_active    boolean not null default true
);
insert into public.agenda (id, nama, is_amendment, is_active) values
  (1, 'Adendum/Amandemen', true, true),
  (2, 'Student Exchange', false, true),
  (3, 'Staff/Faculty Exchange', false, false),
  (4, 'Joint Research', false, true),
  (5, 'Joint Publication', false, false),
  (6, 'Joint Degree/Double Degree', false, false),
  (7, 'Guest Lecture', false, false),
  (8, 'Internship/Magang', false, false),
  (9, 'Community Service', false, false),
  (10, 'Conference/Seminar', false, false),
  (11, 'Curriculum Development', false, false),
  (12, 'Scholarship', false, false),
  (13, 'Laboratory/Facility Sharing', false, false),
  (14, 'Tridharma Perguruan Tinggi', false, true),
  (15, 'Kuliah Tamu/Guest Lecturer', false, true),
  (16, 'Gelar Bersama/Joint Degree', false, true),
  (17, 'Gelar Ganda/Double Degree', false, true),
  (18, 'Gelar Percepatan/Fast Track', false, true),
  (20, 'Study Abroad', false, true),
  (21, 'Magang/Internship', false, true),
  (22, 'Immersion', false, true),
  (23, 'Short Program', false, true),
  (24, 'Studi Ekskursi', false, true),
  (25, 'Tugas Akhir', false, true),
  (26, 'Thesis Writing', false, true),
  (27, 'Academic Visit', false, true),
  (28, 'Academic Exchange', false, true),
  (29, 'Cultural Exchange', false, true),
  (30, 'Facilities Exchange', false, true),
  (31, 'Staf/Faculty Exchange', false, true),
  (32, 'Joint Curriculum', false, true),
  (33, 'Credit Transfer', false, true),
  (34, 'Joint Lecturer/ Kuliah Bersama', false, true),
  (35, 'Joint Projects (Konferensi/Seminar/Workshop/Lomba/pameran)', false, true),
  (37, 'Publikasi Jurnal Ilmiah', false, true),
  (38, 'Merdeka Belajar Kampus Merdeka (MBKM)', false, true),
  (39, 'Rekrutmen Lulusan', false, true),
  (40, 'Pengabdian Kepada Masyarakat/ Service Learning', false, true),
  (41, 'Beasiswa', false, true),
  (42, 'Hibah/Donasi', false, true),
  (43, 'Educational and Training Program', false, true),
  (44, 'Sertifikasi', false, true),
  (45, 'Akreditasi', false, true),
  (46, 'Program Sejong Korean', false, true),
  (47, 'Penerimaan mahasiswa baru', false, true),
  (48, 'Pemanfaatan e-AMITRA', false, true),
  (49, 'Penyelenggaraan Pusat Dukungan Teknologi dan Inovasi', false, true),
  (50, 'Penyelenggaraan IELTS Off-site Testing', false, true),
  (51, 'Penyelenggaraan Tax Center', false, true),
  (52, 'Pelaksanaan Asesor BKD Sertifikasi Dosen', false, true),
  (53, 'Pendayagunaan Aparatur Negara dan Pelaksanaan Reformasi Birokrasi', false, true),
  (54, 'Pemberdayaan dan pemanfaatan perpustakaan', false, true),
  (55, 'Website Bursa Informasi Pendidikan Tinggi (BIDikTi)', false, true),
  (56, 'Layanan Transaksi Online', false, true),
  (57, 'Asuransi', false, true),
  (58, 'Penyediaan Layanan Telekomunikasi', false, true),
  (59, 'Promosi Kegiatan', false, true),
  (60, 'Pembuatan Website', false, true),
  (61, 'Proyek pendukung untuk Penelitian', false, true),
  (62, 'Perjanjian Kerahasiaan', false, true),
  (63, 'Pelatihan Guru', false, true),
  (64, 'Pengembangan dan kerahasiaan layanan komputasi, server, perangkat lunak, penyimpanan data, database, dan jaringan modul digital dalam Platform LMS Gamifikasi', false, true),
  (65, 'Pengembangan modul digital ke dalam Platform LMS Gamifikasi', false, true),
  (66, 'Pemanfaatan LMS Gamifikasi sebagai medium pembelajaran di universitas masing-masing.', false, true),
  (67, 'Layanan Digital', false, true),
  (68, 'Pemanfaatan Sistem Pembelajaran Petraverse', false, true),
  (69, 'Pelatihan', false, true),
  (70, 'Program ODP (Officer Development Program)', false, true),
  (71, 'Product & Design Development Center', false, true),
  (72, 'Software Application Development Center', false, true),
  (73, 'Perlindungan anak, kesehatan masyarakat, sosial, ekonomi, lingkungan, kebencanaan', false, true),
  (74, 'Pelayanan pendaftaran HAKI pada lingkup sektor industri yang tersedia', false, true),
  (75, 'Pemanfaatan Vending Machine', false, true),
  (76, 'Joint Project (Pemberian Jasa)', false, true),
  (77, 'Pendirian Fakultas Kedokteran Gigi', false, true),
  (79, 'Online Course', false, true),
  (80, 'Program Darmasiswa', false, true),
  (81, 'Falling Walls Lab Indonesia', false, true),
  (82, 'Business Class with PBS', false, true),
  (83, 'Kegiatan Mata Kuliah Wajib Kurikulum (MKWK)', false, true),
  (84, 'Perekrutan mahasiswa', false, true),
  (85, 'Dual Degree', false, true)
on conflict (id) do nothing;

-- SIMKS protects its tables with RLS. Mirror that locally with RLS on and no grants/policies for the API roles, so a
-- Realisasi session (role authenticated) can only reach SIMKS data through the kerjasama adapter views.
do $$
declare t text;
begin
  foreach t in array array['jenis_unit','unit','negara','partner','proposal_dokumen','dokumen_kerja_sama',
                           'partner_pengusul','proposal_dokumen_unit','jabatan','akun','agenda'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;

-- Marker: scripts/db-reset.sh only drops public SIMKS-shaped tables that carry this comment, so a real SIM Kerjasama
-- database (e.g. a local `supabase start` with SIMKS migrations) is never wiped.
comment on table public.dokumen_kerja_sama is 'sim-realisasi local SIMKS stub';
