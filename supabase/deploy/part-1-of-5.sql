-- SIM Realisasi Supabase install, PART 1 OF 5 (commit 86b945f).
-- Run parts 1..5 in order in Supabase Dashboard -> SQL Editor. If any part fails, start again from part 1.
begin;

-- >>> supabase/deploy/00_reset_realisasi.sql
-- Used only by `scripts/db-deploy-supabase.sh --reset-realisasi`, inside the same transaction as the redeploy.
-- Removes ONLY objects owned by SIM Realisasi (its four schemas, its pg_cron job, its migration-history rows), e.g. to
-- clean up a partial install. SIM Kerjasama tables in schema public are never touched.
drop schema if exists realisasi, kerjasama, mock_baak, mock_hr cascade;

do $$
begin
  -- dynamic SQL: these objects only exist on Supabase / with pg_cron
  if to_regclass('cron.job') is not null then
    execute $q$select cron.unschedule(jobid) from cron.job where jobname = 'realisasi-daily-jobs'$q$;
  end if;
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    execute $q$delete from supabase_migrations.schema_migrations where name like 'realisasi\_%'$q$;
  end if;
end $$;

-- >>> supabase/migrations/0000_bootstrap.sql
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
                           'partner_pengusul','proposal_dokumen_unit','jabatan','akun','agenda'] loop
    if to_regclass('public.' || t) is null then missing := missing || ('table public.' || t); end if;
  end loop;
  if cardinality(missing) > 0 then
    raise exception 'SIM Realisasi needs the SIM Kerjasama (Supabase) database; missing: %', array_to_string(missing, ', ')
      using hint = 'Locally, apply supabase/local/*.sql first (scripts/db-reset.sh does this).';
  end if;
end $$;

-- >>> supabase/migrations/0001_enums.sql
-- 0001_enums
create schema if not exists realisasi;

create type realisasi.activity_status   as enum ('draft','in_verification','revision_requested','verified');
create type realisasi.track_status      as enum ('not_required','pending','revision_requested','approved');
create type realisasi.direction         as enum ('inbound','outbound');
create type realisasi.mobility_category as enum ('jd_dd','student_exchange','short_summer','other_mobility');
create type realisasi.activity_mode     as enum ('offline','online','hybrid');
create type realisasi.file_kind         as enum ('ia','ir','mobility_bundle','evidence');
create type realisasi.person_role       as enum ('speaker','visiting_lecturer','researcher','staff_visitor','other');
create type realisasi.student_section   as enum ('internal','inbound');
create type realisasi.pset_status       as enum ('draft','pending','revision_requested','approved','superseded');
create type realisasi.semester_term     as enum ('ganjil','genap');
create type realisasi.snapshot_kind     as enum ('ganjil_ytd','genap_full_year');
create type realisasi.conflict_status   as enum ('open','resolved');
create type realisasi.log_kind          as enum ('verification','revision','update','system');
create type realisasi.team              as enum ('mobility');

-- >>> supabase/migrations/0001_kerjasama_adapter.sql
-- 0001_kerjasama_adapter: read-only adapter from the live SIM Kerjasama (SIMKS) schema to the Schema §1.1 shapes.
--
-- SIMKS owns schema `public` (Indonesian table names, integer ids, ISO alpha-3 country codes, akun/jabatan accounts,
-- proposal-based partners/scope/renewal links). Realisasi never writes SIMKS tables and never creates objects in
-- `public`. Every Realisasi object reads SIMKS only through the views in schema `kerjasama` created here:
--   kerjasama.units, countries, partners, documents, document_partners, document_scope_units, profiles, agendas
-- (exact Schema §1.1 columns, plus a few additive columns at the end of each view).
--
-- Access model: the views are ordinary (security_invoker = false) views owned by the migration owner (postgres on
-- Supabase, the owner of the SIMKS tables), so they read SIMKS with the owner's rights while `authenticated` gets
-- SELECT on the views only — never on any SIMKS table. Chosen over SECURITY DEFINER set-returning functions because
-- plain views stay inlinable (predicates such as `id = $1` / joins push down into the SIMKS tables), and they are
-- read-only by construction (multi-table joins, SELECT-only grants). The cost is the Supabase advisor's
-- "security definer view" notice for schema kerjasama, which is intended; kerjasama is not an exposed API schema.
--
-- Realisasi-owned tables that the adapter joins (both RLS-enabled by 0006 and granted to nobody by 0016):
--   realisasi.account_roles      — which SIMKS accounts use Realisasi, with which role (+ optional unit override)
--   realisasi.document_overrides — Realisasi-only document facts SIMKS lacks (auto-renewal, termination timestamp)

create schema if not exists kerjasama;
comment on schema kerjasama is 'SIM Realisasi read-only adapter views over the SIM Kerjasama (SIMKS) public schema.';

-- ISO 3166-1 alpha-3 -> alpha-2 (SIMKS negara.kode is alpha-3; Realisasi uses alpha-2 everywhere) ----------------
create table kerjasama.iso3166 (
  alpha2 char(2) primary key,
  alpha3 char(3) not null unique,
  name   text    not null
);
insert into kerjasama.iso3166 (alpha2, alpha3, name) values
  ('AD', 'AND', 'Andorra'),
  ('AE', 'ARE', 'United Arab Emirates'),
  ('AF', 'AFG', 'Afghanistan'),
  ('AG', 'ATG', 'Antigua and Barbuda'),
  ('AI', 'AIA', 'Anguilla'),
  ('AL', 'ALB', 'Albania'),
  ('AM', 'ARM', 'Armenia'),
  ('AO', 'AGO', 'Angola'),
  ('AQ', 'ATA', 'Antarctica'),
  ('AR', 'ARG', 'Argentina'),
  ('AS', 'ASM', 'American Samoa'),
  ('AT', 'AUT', 'Austria'),
  ('AU', 'AUS', 'Australia'),
  ('AW', 'ABW', 'Aruba'),
  ('AX', 'ALA', 'Åland Islands'),
  ('AZ', 'AZE', 'Azerbaijan'),
  ('BA', 'BIH', 'Bosnia and Herzegovina'),
  ('BB', 'BRB', 'Barbados'),
  ('BD', 'BGD', 'Bangladesh'),
  ('BE', 'BEL', 'Belgium'),
  ('BF', 'BFA', 'Burkina Faso'),
  ('BG', 'BGR', 'Bulgaria'),
  ('BH', 'BHR', 'Bahrain'),
  ('BI', 'BDI', 'Burundi'),
  ('BJ', 'BEN', 'Benin'),
  ('BL', 'BLM', 'Saint Barthélemy'),
  ('BM', 'BMU', 'Bermuda'),
  ('BN', 'BRN', 'Brunei Darussalam'),
  ('BO', 'BOL', 'Bolivia'),
  ('BQ', 'BES', 'Bonaire, Sint Eustatius and Saba'),
  ('BR', 'BRA', 'Brazil'),
  ('BS', 'BHS', 'Bahamas'),
  ('BT', 'BTN', 'Bhutan'),
  ('BV', 'BVT', 'Bouvet Island'),
  ('BW', 'BWA', 'Botswana'),
  ('BY', 'BLR', 'Belarus'),
  ('BZ', 'BLZ', 'Belize'),
  ('CA', 'CAN', 'Canada'),
  ('CC', 'CCK', 'Cocos (Keeling) Islands'),
  ('CD', 'COD', 'Congo, The Democratic Republic of the'),
  ('CF', 'CAF', 'Central African Republic'),
  ('CG', 'COG', 'Congo'),
  ('CH', 'CHE', 'Switzerland'),
  ('CI', 'CIV', 'Côte d''Ivoire'),
  ('CK', 'COK', 'Cook Islands'),
  ('CL', 'CHL', 'Chile'),
  ('CM', 'CMR', 'Cameroon'),
  ('CN', 'CHN', 'China'),
  ('CO', 'COL', 'Colombia'),
  ('CR', 'CRI', 'Costa Rica'),
  ('CU', 'CUB', 'Cuba'),
  ('CV', 'CPV', 'Cabo Verde'),
  ('CW', 'CUW', 'Curaçao'),
  ('CX', 'CXR', 'Christmas Island'),
  ('CY', 'CYP', 'Cyprus'),
  ('CZ', 'CZE', 'Czechia'),
  ('DE', 'DEU', 'Germany'),
  ('DJ', 'DJI', 'Djibouti'),
  ('DK', 'DNK', 'Denmark'),
  ('DM', 'DMA', 'Dominica'),
  ('DO', 'DOM', 'Dominican Republic'),
  ('DZ', 'DZA', 'Algeria'),
  ('EC', 'ECU', 'Ecuador'),
  ('EE', 'EST', 'Estonia'),
  ('EG', 'EGY', 'Egypt'),
  ('EH', 'ESH', 'Western Sahara'),
  ('ER', 'ERI', 'Eritrea'),
  ('ES', 'ESP', 'Spain'),
  ('ET', 'ETH', 'Ethiopia'),
  ('FI', 'FIN', 'Finland'),
  ('FJ', 'FJI', 'Fiji'),
  ('FK', 'FLK', 'Falkland Islands (Malvinas)'),
  ('FM', 'FSM', 'Micronesia, Federated States of'),
  ('FO', 'FRO', 'Faroe Islands'),
  ('FR', 'FRA', 'France'),
  ('GA', 'GAB', 'Gabon'),
  ('GB', 'GBR', 'United Kingdom'),
  ('GD', 'GRD', 'Grenada'),
  ('GE', 'GEO', 'Georgia'),
  ('GF', 'GUF', 'French Guiana'),
  ('GG', 'GGY', 'Guernsey'),
  ('GH', 'GHA', 'Ghana'),
  ('GI', 'GIB', 'Gibraltar'),
  ('GL', 'GRL', 'Greenland'),
  ('GM', 'GMB', 'Gambia'),
  ('GN', 'GIN', 'Guinea'),
  ('GP', 'GLP', 'Guadeloupe'),
  ('GQ', 'GNQ', 'Equatorial Guinea'),
  ('GR', 'GRC', 'Greece'),
  ('GS', 'SGS', 'South Georgia and the South Sandwich Islands'),
  ('GT', 'GTM', 'Guatemala'),
  ('GU', 'GUM', 'Guam'),
  ('GW', 'GNB', 'Guinea-Bissau'),
  ('GY', 'GUY', 'Guyana'),
  ('HK', 'HKG', 'Hong Kong'),
  ('HM', 'HMD', 'Heard Island and McDonald Islands'),
  ('HN', 'HND', 'Honduras'),
  ('HR', 'HRV', 'Croatia'),
  ('HT', 'HTI', 'Haiti'),
  ('HU', 'HUN', 'Hungary'),
  ('ID', 'IDN', 'Indonesia'),
  ('IE', 'IRL', 'Ireland'),
  ('IL', 'ISR', 'Israel'),
  ('IM', 'IMN', 'Isle of Man'),
  ('IN', 'IND', 'India'),
  ('IO', 'IOT', 'British Indian Ocean Territory'),
  ('IQ', 'IRQ', 'Iraq'),
  ('IR', 'IRN', 'Iran'),
  ('IS', 'ISL', 'Iceland'),
  ('IT', 'ITA', 'Italy'),
  ('JE', 'JEY', 'Jersey'),
  ('JM', 'JAM', 'Jamaica'),
  ('JO', 'JOR', 'Jordan'),
  ('JP', 'JPN', 'Japan'),
  ('KE', 'KEN', 'Kenya'),
  ('KG', 'KGZ', 'Kyrgyzstan'),
  ('KH', 'KHM', 'Cambodia'),
  ('KI', 'KIR', 'Kiribati'),
  ('KM', 'COM', 'Comoros'),
  ('KN', 'KNA', 'Saint Kitts and Nevis'),
  ('KP', 'PRK', 'North Korea'),
  ('KR', 'KOR', 'South Korea'),
  ('KW', 'KWT', 'Kuwait'),
  ('KY', 'CYM', 'Cayman Islands'),
  ('KZ', 'KAZ', 'Kazakhstan'),
  ('LA', 'LAO', 'Laos'),
  ('LB', 'LBN', 'Lebanon'),
  ('LC', 'LCA', 'Saint Lucia'),
  ('LI', 'LIE', 'Liechtenstein'),
  ('LK', 'LKA', 'Sri Lanka'),
  ('LR', 'LBR', 'Liberia'),
  ('LS', 'LSO', 'Lesotho'),
  ('LT', 'LTU', 'Lithuania'),
  ('LU', 'LUX', 'Luxembourg'),
  ('LV', 'LVA', 'Latvia'),
  ('LY', 'LBY', 'Libya'),
  ('MA', 'MAR', 'Morocco'),
  ('MC', 'MCO', 'Monaco'),
  ('MD', 'MDA', 'Moldova'),
  ('ME', 'MNE', 'Montenegro'),
  ('MF', 'MAF', 'Saint Martin (French part)'),
  ('MG', 'MDG', 'Madagascar'),
  ('MH', 'MHL', 'Marshall Islands'),
  ('MK', 'MKD', 'North Macedonia'),
  ('ML', 'MLI', 'Mali'),
  ('MM', 'MMR', 'Myanmar'),
  ('MN', 'MNG', 'Mongolia'),
  ('MO', 'MAC', 'Macao'),
  ('MP', 'MNP', 'Northern Mariana Islands'),
  ('MQ', 'MTQ', 'Martinique'),
  ('MR', 'MRT', 'Mauritania'),
  ('MS', 'MSR', 'Montserrat'),
  ('MT', 'MLT', 'Malta'),
  ('MU', 'MUS', 'Mauritius'),
  ('MV', 'MDV', 'Maldives'),
  ('MW', 'MWI', 'Malawi'),
  ('MX', 'MEX', 'Mexico'),
  ('MY', 'MYS', 'Malaysia'),
  ('MZ', 'MOZ', 'Mozambique'),
  ('NA', 'NAM', 'Namibia'),
  ('NC', 'NCL', 'New Caledonia'),
  ('NE', 'NER', 'Niger'),
  ('NF', 'NFK', 'Norfolk Island'),
  ('NG', 'NGA', 'Nigeria'),
  ('NI', 'NIC', 'Nicaragua'),
  ('NL', 'NLD', 'Netherlands'),
  ('NO', 'NOR', 'Norway'),
  ('NP', 'NPL', 'Nepal'),
  ('NR', 'NRU', 'Nauru'),
  ('NU', 'NIU', 'Niue'),
  ('NZ', 'NZL', 'New Zealand'),
  ('OM', 'OMN', 'Oman'),
  ('PA', 'PAN', 'Panama'),
  ('PE', 'PER', 'Peru'),
  ('PF', 'PYF', 'French Polynesia'),
  ('PG', 'PNG', 'Papua New Guinea'),
  ('PH', 'PHL', 'Philippines'),
  ('PK', 'PAK', 'Pakistan'),
  ('PL', 'POL', 'Poland'),
  ('PM', 'SPM', 'Saint Pierre and Miquelon'),
  ('PN', 'PCN', 'Pitcairn'),
  ('PR', 'PRI', 'Puerto Rico'),
  ('PS', 'PSE', 'Palestine, State of'),
  ('PT', 'PRT', 'Portugal'),
  ('PW', 'PLW', 'Palau'),
  ('PY', 'PRY', 'Paraguay'),
  ('QA', 'QAT', 'Qatar'),
  ('RE', 'REU', 'Réunion'),
  ('RO', 'ROU', 'Romania'),
  ('RS', 'SRB', 'Serbia'),
  ('RU', 'RUS', 'Russian Federation'),
  ('RW', 'RWA', 'Rwanda'),
  ('SA', 'SAU', 'Saudi Arabia'),
  ('SB', 'SLB', 'Solomon Islands'),
  ('SC', 'SYC', 'Seychelles'),
  ('SD', 'SDN', 'Sudan'),
  ('SE', 'SWE', 'Sweden'),
  ('SG', 'SGP', 'Singapore'),
  ('SH', 'SHN', 'Saint Helena, Ascension and Tristan da Cunha'),
  ('SI', 'SVN', 'Slovenia'),
  ('SJ', 'SJM', 'Svalbard and Jan Mayen'),
  ('SK', 'SVK', 'Slovakia'),
  ('SL', 'SLE', 'Sierra Leone'),
  ('SM', 'SMR', 'San Marino'),
  ('SN', 'SEN', 'Senegal'),
  ('SO', 'SOM', 'Somalia'),
  ('SR', 'SUR', 'Suriname'),
  ('SS', 'SSD', 'South Sudan'),
  ('ST', 'STP', 'Sao Tome and Principe'),
  ('SV', 'SLV', 'El Salvador'),
  ('SX', 'SXM', 'Sint Maarten (Dutch part)'),
  ('SY', 'SYR', 'Syria'),
  ('SZ', 'SWZ', 'Eswatini'),
  ('TC', 'TCA', 'Turks and Caicos Islands'),
  ('TD', 'TCD', 'Chad'),
  ('TF', 'ATF', 'French Southern Territories'),
  ('TG', 'TGO', 'Togo'),
  ('TH', 'THA', 'Thailand'),
  ('TJ', 'TJK', 'Tajikistan'),
  ('TK', 'TKL', 'Tokelau'),
  ('TL', 'TLS', 'Timor-Leste'),
  ('TM', 'TKM', 'Turkmenistan'),
  ('TN', 'TUN', 'Tunisia'),
  ('TO', 'TON', 'Tonga'),
  ('TR', 'TUR', 'Türkiye'),
  ('TT', 'TTO', 'Trinidad and Tobago'),
  ('TV', 'TUV', 'Tuvalu'),
  ('TW', 'TWN', 'Taiwan'),
  ('TZ', 'TZA', 'Tanzania'),
  ('UA', 'UKR', 'Ukraine'),
  ('UG', 'UGA', 'Uganda'),
  ('UM', 'UMI', 'United States Minor Outlying Islands'),
  ('US', 'USA', 'United States'),
  ('UY', 'URY', 'Uruguay'),
  ('UZ', 'UZB', 'Uzbekistan'),
  ('VA', 'VAT', 'Holy See (Vatican City State)'),
  ('VC', 'VCT', 'Saint Vincent and the Grenadines'),
  ('VE', 'VEN', 'Venezuela'),
  ('VG', 'VGB', 'Virgin Islands, British'),
  ('VI', 'VIR', 'Virgin Islands, U.S.'),
  ('VN', 'VNM', 'Vietnam'),
  ('VU', 'VUT', 'Vanuatu'),
  ('WF', 'WLF', 'Wallis and Futuna'),
  ('WS', 'WSM', 'Samoa'),
  ('XK', 'XKX', 'Kosovo'),
  ('YE', 'YEM', 'Yemen'),
  ('YT', 'MYT', 'Mayotte'),
  ('ZA', 'ZAF', 'South Africa'),
  ('ZM', 'ZMB', 'Zambia'),
  ('ZW', 'ZWE', 'Zimbabwe');

-- Realisasi-owned authorisation for SIMKS accounts ------------------------------------------------------------------
-- A SIMKS account (public.akun) is a Realisasi user only when it has a row here. SIMKS roles (admin/approver/user/
-- user_staff) are not used. unit_id overrides the unit of the account's jabatan (null = use jabatan.id_unit).
create table realisasi.account_roles (
  akun_id    int primary key,
  app_role   text not null check (app_role in ('submitter','io_staff','io_admin','viewer')),
  unit_id    int,
  updated_at timestamptz not null default now()
);
comment on table realisasi.account_roles is
  'Realisasi role per SIMKS account (public.akun.id). Accounts without a row cannot use SIM Realisasi.';

-- Document facts SIMKS does not model (no auto-renew concept, no termination timestamp). Maintained by IO/DBA.
create table realisasi.document_overrides (
  document_id   int primary key,                 -- = public.dokumen_kerja_sama.no
  auto_renewed  boolean not null default false,
  terminated_at timestamptz,
  note          text,
  updated_at    timestamptz not null default now()
);
comment on table realisasi.document_overrides is
  'Realisasi-only overrides LEFT JOINed by kerjasama.documents (auto_renewed, terminated_at).';

-- Views ---------------------------------------------------------------------------------------------------------
-- units: kind from jenis_unit / hierarchy. jenis 2 (Unit Pembantu) -> up. Academic units (jenis 1): a top-level
-- academic unit with academic grandchildren is the university itself -> up; one with academic children -> faculty;
-- a leaf under an academic parent -> prodi; a leaf without an academic parent -> faculty. ('program' is never produced.)
create view kerjasama.units as
select u.id,
       u.nama::text as name,
       u.id_parent_unit as parent_id,
       case
         when u.id_jenis_unit is distinct from 1 then 'up'
         when u.id_parent_unit is null and exists (
                select 1 from public.unit c join public.unit g on g.id_parent_unit = c.id
                 where c.id_parent_unit = u.id and c.id_jenis_unit = 1 and g.id_jenis_unit = 1) then 'up'
         when exists (select 1 from public.unit c where c.id_parent_unit = u.id and c.id_jenis_unit = 1) then 'faculty'
         when pu.id_jenis_unit = 1 then 'prodi'
         else 'faculty'
       end as kind,
       coalesce(u.is_active, true) as is_active,
       (u.id_jenis_unit = 1) is true as is_academic   -- jenis_unit 1 = Unit Akademik (Revisi V.1: only these submit)
  from public.unit u
  left join public.unit pu on pu.id = u.id_parent_unit;

-- agendas: SIMKS "Agenda Kerjasama" list, used by Realisasi as Jenis Kegiatan (Revisi V.1). The amendment agenda is a
-- document-level concept, not an activity, so it is left out. Mobility/counting rules live in realisasi.agenda_rules.
create view kerjasama.agendas as
select a.id, a.nama::text as name, coalesce(a.is_active, true) as is_active
  from public.agenda a
 where not coalesce(a.is_amendment, false);

-- countries: one row per ISO alpha-2 code found in SIMKS negara. Unmappable kode values are left out.
create view kerjasama.countries as
select distinct on (i.alpha2)
       i.alpha2::text as code,
       n.nama::text as name,
       i.alpha3::text as alpha3,
       n.id as negara_id,
       coalesce(n.is_domestic, false) as is_domestic
  from public.negara n
  join kerjasama.iso3166 i on i.alpha3 = upper(btrim(n.kode))
 order by i.alpha2, coalesce(n.is_active, true) desc, n.id;

-- partners: country via negara (alpha-3 -> alpha-2). A partner without a mappable country is 'ID' when SIMKS marks it
-- domestic, otherwise null (such a partner is skipped by the activity partner snapshot). Merged/inactive partners are
-- kept (documents still reference them); merged_into_id exposes SIMKS's id_merged_into.
create view kerjasama.partners as
select p.id,
       p.nama::text as name,
       coalesce(i.alpha2::text, case when p.is_international is false then 'ID' end) as country_code,
       p.id_merged_into as merged_into_id,
       coalesce(p.is_active, true) as is_active
  from public.partner p
  left join public.negara n on n.id = p.id_negara
  left join kerjasama.iso3166 i on i.alpha3 = upper(btrim(n.kode));

-- documents: one row per dokumen_kerja_sama (id = no), kind from its proposal.
--   status: alasan_arsip 'rejected' -> rejected; 'Aktif'/'Akan Berakhir' -> active; 'Diarsipkan' -> archived;
--           anything else (a dokumen row still being processed) -> in_process.
--   predecessor_id: proposal_dokumen.id_dokumen_sebelumnya holds the predecessor's PROPOSAL id, so the predecessor is
--           the dokumen whose id_proposal_dokumen = that id.
--   archived_reason: SIMKS alasan_arsip verbatim (rejected | superseded_by_renewal | expired_without_renewal).
--   auto_renewed / terminated_at: SIMKS has neither -> realisasi.document_overrides (default false / null).
--   title: SIMKS has no title column -> first line of tujuan_kerjasama (<= 160 chars), else "<kind> <lead partner>".
create view kerjasama.documents as
select d.no as id,
       coalesce(nullif(btrim(d.no_dokumen), ''), 'Tanpa nomor #' || d.no)::text as doc_number,
       coalesce(left(nullif(btrim(split_part(p.tujuan_kerjasama, E'\n', 1)), ''), 160),
                p.jenis_kerjasama::text || ' ' ||
                coalesce((select string_agg(pa.nama, ', ' order by pp.is_lead desc nulls last, pa.nama)
                            from public.partner_pengusul pp join public.partner pa on pa.id = pp.id_partner
                           where pp.id_proposal_dokumen = p.id), 'tanpa mitra'))::text as title,
       p.jenis_kerjasama::text as kind,
       case when d.alasan_arsip = 'rejected' then 'rejected'
            when d.status in ('Aktif', 'Akan Berakhir') then 'active'
            when d.status = 'Diarsipkan' then 'archived'
            else 'in_process' end as status,
       d.tanggal_mulai as start_date,
       d.tanggal_berakhir as end_date,
       coalesce(o.auto_renewed, false) as auto_renewed,
       nullif(prev.no, d.no) as predecessor_id,
       d.alasan_arsip::text as archived_reason,
       o.terminated_at,
       d.id_proposal_dokumen as proposal_id,
       d.status::text as simks_status
  from public.dokumen_kerja_sama d
  join public.proposal_dokumen p on p.id = d.id_proposal_dokumen
  -- one predecessor per proposal, as a join (hashable in the recursive chain walks; a correlated subquery was ~10x slower)
  left join (select id_proposal_dokumen, min(no) as no from public.dokumen_kerja_sama group by id_proposal_dokumen) prev
         on prev.id_proposal_dokumen = p.id_dokumen_sebelumnya
  left join realisasi.document_overrides o on o.document_id = d.no;

create view kerjasama.document_partners as
select d.no as document_id, pp.id_partner as partner_id, bool_or(coalesce(pp.is_lead, false)) as is_lead
  from public.dokumen_kerja_sama d
  join public.partner_pengusul pp on pp.id_proposal_dokumen = d.id_proposal_dokumen
 where pp.id_partner is not null
 group by d.no, pp.id_partner;

-- no DISTINCT (keeps the view inlinable): SIMKS keys proposal_dokumen_unit by (proposal, unit) and each proposal has one
-- dokumen; every caller uses exists()/distinct anyway.
create view kerjasama.document_scope_units as
select d.no as document_id, pu.id_unit as unit_id
  from public.dokumen_kerja_sama d
  join public.proposal_dokumen_unit pu on pu.id_proposal_dokumen = d.id_proposal_dokumen
 where pu.id_unit is not null;

-- profiles: SIMKS accounts that have a realisasi.account_roles row. id is the Supabase Auth user id when the account
-- has one, else a stable uuid derived from the akun id. app_role is null (= no access) when the akun is inactive.
-- unit_id = account_roles.unit_id override, else the unit of the account's jabatan.
create view kerjasama.profiles as
select coalesce(a.auth_user_id, md5('simks-akun:' || a.id)::uuid) as id,
       a.email::text as email,
       coalesce(nullif(btrim(j.nama), ''), a.email)::text as display_name,
       case when coalesce(a.is_active, true) then r.app_role end as app_role,
       coalesce(r.unit_id, j.id_unit) as unit_id,
       a.id as akun_id,
       a.auth_user_id
  from realisasi.account_roles r
  join public.akun a on a.id = r.akun_id
  left join public.jabatan j on j.id = a.id_jabatan;

-- Grants: SELECT on the views only. Nothing on SIMKS tables, nothing on iso3166 / the realisasi tables above.
revoke all on all tables in schema kerjasama from public, anon, authenticated;
revoke all on schema kerjasama from public;
grant usage on schema kerjasama to authenticated;
grant select on kerjasama.units, kerjasama.countries, kerjasama.partners, kerjasama.documents,
                kerjasama.document_partners, kerjasama.document_scope_units, kerjasama.profiles,
                kerjasama.agendas to authenticated;

-- >>> supabase/migrations/0002_tables.sql
-- 0002_tables: Schema §3/§4 with CONTRACTS §2.3 deltas. Extra indexes cover FKs and RLS/helper predicates.
-- SIM Kerjasama ids (units, countries, documents, profiles) point at kerjasama.* adapter views, which cannot be FK
-- targets: the RPCs validate them instead (CONTRACTS "Contract amendments (SIMKS integration)").

-- 3.1 Configuration --------------------------------------------------------
create table realisasi.team_members (
  account_id uuid,  -- kerjasama.profiles.id (no FK: adapter view)
  team       realisasi.team,
  primary key (account_id, team)
);

-- Deployment flags: written only by the DBA / seeds (no RPC writes them, no grant). See M9 in docs/reviews/database-review.md.
--   demo_time_travel: when enabled, settings.demo_today shifts today()/now_ts(). Absent or false = production (real clock).
create table realisasi.deployment_flags (
  key     text primary key,
  enabled boolean not null
);

create table realisasi.settings (
  key        text primary key,
  value      jsonb not null,
  updated_by uuid,  -- kerjasama.profiles.id (no FK: adapter view)
  updated_at timestamptz default now()
);

create table realisasi.academic_years (
  id         serial primary key,
  label      text unique not null,
  start_date date not null,
  end_date   date not null,
  check (end_date > start_date)
);

create table realisasi.semesters (
  id               serial primary key,
  academic_year_id int not null references realisasi.academic_years(id),
  term             realisasi.semester_term not null,
  start_date       date not null,
  end_date         date not null,
  cutoff_date      date not null,
  unique (academic_year_id, term),
  check (cutoff_date >= end_date)
);

-- Counting rules per SIMKS agenda (Jenis Kegiatan = kerjasama.agendas, Revisi V.1). An agenda without a row, or with a
-- null mobility_category, is not a mobility activity: no participants required, verified on submit.
create table realisasi.agenda_rules (
  agenda_id         int primary key,  -- kerjasama.agendas.id (no FK: adapter view)
  mobility_category realisasi.mobility_category,
  counts_for_s1     boolean not null default true,
  updated_by        uuid,  -- kerjasama.profiles.id (no FK: adapter view)
  updated_at        timestamptz default now()
);

create table realisasi.sdgs (
  id   smallint primary key check (id between 1 and 17),
  name text not null
);

-- 3.2 Activities -----------------------------------------------------------
create sequence realisasi.activity_code_seq;

create table realisasi.event_groups (
  id         uuid primary key default gen_random_uuid(),
  created_by uuid,  -- kerjasama.profiles.id (no FK: adapter view)
  created_at timestamptz default now()
);
create index on realisasi.event_groups (created_by);

create table realisasi.activities (
  id                  uuid primary key default gen_random_uuid(),
  code                text unique not null
                      default 'RL-' || to_char(now(),'YYYY') || '-' || lpad(nextval('realisasi.activity_code_seq')::text,4,'0'),
  name                text not null,
  agenda_id           int not null,  -- kerjasama.agendas.id (no FK: adapter view); rules in realisasi.agenda_rules
  direction           realisasi.direction not null,
  start_date          date not null,
  end_date            date not null,
  academic_year_id    int references realisasi.academic_years(id),
  semester_id         int references realisasi.semesters(id),
  mode                realisasi.activity_mode not null,
  venue               text,
  country_code        text check (country_code ~ '^[A-Z]{2}$'),  -- kerjasama.countries.code (no FK: adapter view)
  sks_recognized      numeric(4,1),
  description         text not null,
  submitter_unit_id   int not null,  -- kerjasama.units.id (no FK: adapter view)
  created_by          uuid not null,  -- kerjasama.profiles.id (no FK: adapter view)
  submitted_at        timestamptz,
  verified_at         timestamptz,
  status              realisasi.activity_status not null default 'draft',
  mobility_status     realisasi.track_status not null default 'not_required',
  mobility_since      timestamptz,  -- when the mobility track last changed (revision reminders)
  event_group_id      uuid not null references realisasi.event_groups(id),
  reporting_deadline  date,
  is_late             boolean not null default false,
  created_at          timestamptz default now(),
  updated_at          timestamptz default now(),
  check (end_date >= start_date)
);
create index on realisasi.activities (status, start_date);
create index on realisasi.activities (event_group_id);
create index on realisasi.activities (submitter_unit_id);
create index on realisasi.activities (agenda_id);
create index on realisasi.activities (semester_id);
create index on realisasi.activities (academic_year_id);
create index on realisasi.activities (created_by);
create index activities_name_trgm on realisasi.activities using gin (lower(name) gin_trgm_ops);

create table realisasi.activity_units (
  activity_id  uuid references realisasi.activities(id),
  unit_id      int ,  -- kerjasama.units.id (no FK: adapter view)
  is_submitter boolean not null default false,
  primary key (activity_id, unit_id)
);
create index on realisasi.activity_units (unit_id, activity_id);

create table realisasi.activity_documents (
  activity_id           uuid references realisasi.activities(id),
  original_document_id  int  not null,  -- kerjasama.documents.id (no FK: adapter view)
  chain_id              int  not null,
  out_of_scope_warning  boolean not null default false,
  primary key (activity_id, original_document_id)
);
create unique index one_agreement_per_activity on realisasi.activity_documents (activity_id);  -- Revisi V.1 item 7
create index on realisasi.activity_documents (chain_id);
create index on realisasi.activity_documents (original_document_id);

create table realisasi.activity_partner_snapshot (
  id            bigserial primary key,
  activity_id   uuid not null references realisasi.activities(id),
  document_id   int  not null,
  partner_id    int  not null,
  partner_name  text not null,
  country_code  text not null check (country_code ~ '^[A-Z]{2}$'),  -- alpha-2 from kerjasama.partners
  captured_at   timestamptz default now()
);
create index on realisasi.activity_partner_snapshot (activity_id, document_id);

create table realisasi.activity_sdgs (
  activity_id uuid references realisasi.activities(id),
  sdg_id      smallint references realisasi.sdgs(id),
  primary key (activity_id, sdg_id)
);
create index on realisasi.activity_sdgs (sdg_id);

create table realisasi.activity_external_persons (
  id           bigserial primary key,
  activity_id  uuid not null references realisasi.activities(id),
  full_name    text not null,
  institution  text not null,
  country_code text not null check (country_code ~ '^[A-Z]{2}$'),  -- kerjasama.countries.code (no FK: adapter view)
  role         realisasi.person_role not null,
  notes        text
);
create index on realisasi.activity_external_persons (activity_id);
create index on realisasi.activity_external_persons (country_code);

create table realisasi.activity_files (
  id           bigserial primary key,
  activity_id  uuid not null references realisasi.activities(id),
  kind         realisasi.file_kind not null,
  version      int not null default 1,
  storage_path text,
  url          text,
  filename     text,
  size_bytes   int,
  mime         text,
  is_current   boolean not null default true,
  uploaded_by  uuid,  -- kerjasama.profiles.id (no FK: adapter view)
  uploaded_at  timestamptz default now(),
  check (storage_path is not null or url is not null)
);
create unique index one_current_ia_ir
  on realisasi.activity_files (activity_id, kind)
  where is_current and kind in ('ia','ir','mobility_bundle');
create index on realisasi.activity_files (activity_id, kind);
create index on realisasi.activity_files (storage_path);
create index on realisasi.activity_files (uploaded_by);

-- 3.3 Participants -----------------------------------------------------------
create table realisasi.participant_set_versions (
  id           uuid primary key default gen_random_uuid(),
  activity_id  uuid not null references realisasi.activities(id),
  version      int  not null,
  status       realisasi.pset_status not null default 'draft',
  submitted_by uuid,  -- kerjasama.profiles.id (no FK: adapter view)
  submitted_at timestamptz default null,
  reviewed_by  uuid,  -- kerjasama.profiles.id (no FK: adapter view)
  reviewed_at  timestamptz,
  review_note  text,
  unique (activity_id, version)
);
create unique index one_approved_pset
  on realisasi.participant_set_versions (activity_id) where status = 'approved';
create unique index one_draft_pset
  on realisasi.participant_set_versions (activity_id) where status = 'draft';
create unique index one_pending_pset
  on realisasi.participant_set_versions (activity_id) where status = 'pending';
create index on realisasi.participant_set_versions (submitted_by);
create index on realisasi.participant_set_versions (reviewed_by);

create table realisasi.participant_students (
  id                  bigserial primary key,
  set_version_id      uuid not null references realisasi.participant_set_versions(id),
  section             realisasi.student_section not null,
  nrp                 text not null,
  full_name           text not null,
  faculty_name        text,
  prodi_name          text,
  home_institution    text,
  home_student_number text,
  home_country_code   text,
  unique (set_version_id, nrp),
  check (section = 'internal' or home_institution is not null)
);
create index on realisasi.participant_students (nrp);

create table realisasi.participant_staff (
  id             bigserial primary key,
  set_version_id uuid not null references realisasi.participant_set_versions(id),
  employee_id    text not null,
  full_name      text not null,
  unit_name      text,
  unique (set_version_id, employee_id)
);

-- 3.4 Duplicates, logs, known activities, notifications ---------------------
-- One student (NRP) claimed by activities of two different units with overlapping dates (Revisi V.1, rule 2.1).
-- Mobility picks the activity that keeps the student (kept_activity_id); the other one does not count them. While open,
-- the student counts for neither. The same unit claiming a student in two activities is never a conflict (rule 2.2).
create table realisasi.participant_conflicts (
  id               bigserial primary key,
  nrp              text not null,
  activity_a       uuid not null references realisasi.activities(id),
  activity_b       uuid not null references realisasi.activities(id),
  status           realisasi.conflict_status not null default 'open',
  kept_activity_id uuid references realisasi.activities(id),
  note             text,
  resolved_by      uuid,  -- kerjasama.profiles.id (no FK: adapter view)
  resolved_at      timestamptz,
  created_at       timestamptz default now(),
  check (activity_a < activity_b),
  check ((status = 'resolved') = (kept_activity_id is not null)),
  check (kept_activity_id is null or kept_activity_id in (activity_a, activity_b)),
  unique (nrp, activity_a, activity_b)
);
create index on realisasi.participant_conflicts (activity_b);
create index on realisasi.participant_conflicts (status);
create index on realisasi.participant_conflicts (kept_activity_id);

create table realisasi.activity_log (
  id          bigserial primary key,
  activity_id uuid not null references realisasi.activities(id),
  kind        realisasi.log_kind not null,
  track       realisasi.team,
  action      text not null,
  actor_id    uuid,  -- kerjasama.profiles.id (no FK: adapter view)
  note        text,
  diff        jsonb,
  in_frozen_period boolean not null default false,
  created_at  timestamptz default now()
);
create index on realisasi.activity_log (activity_id, created_at);
create index on realisasi.activity_log (activity_id, action, created_at);
create index on realisasi.activity_log (actor_id);
create index activity_log_frozen_idx on realisasi.activity_log (created_at) where in_frozen_period;

create table realisasi.notifications (
  id           bigserial primary key,
  recipient_id uuid not null,  -- kerjasama.profiles.id (no FK: adapter view)
  kind         text not null,
  title        text not null,
  body         text,
  link         text,
  read_at      timestamptz,
  created_at   timestamptz default now()
);
create index on realisasi.notifications (recipient_id, created_at desc);

create table realisasi.email_outbox (
  id         bigserial primary key,
  to_email   text not null,
  subject    text not null,
  body       text not null,
  created_at timestamptz default now(),
  sent_at    timestamptz
);

create table realisasi.export_log (
  id          bigserial primary key,
  actor_id    uuid,  -- kerjasama.profiles.id (no FK: adapter view)
  export_kind text not null,
  filters     jsonb,
  row_count   int,
  contains_personal_data boolean not null,
  created_at  timestamptz default now()
);
create index on realisasi.export_log (actor_id);

-- 3.5 Snapshots ------------------------------------------------------------
create table realisasi.kpi_snapshots (
  id               uuid primary key default gen_random_uuid(),
  academic_year_id int not null references realisasi.academic_years(id),
  kind             realisasi.snapshot_kind not null,
  window_start     date not null,
  window_end       date not null,
  cutoff_date      date not null,
  values           jsonb not null,
  settings_used    jsonb not null,
  frozen_at        timestamptz not null default now(),
  frozen_by        uuid,  -- kerjasama.profiles.id (no FK: adapter view)
  superseded_by    uuid references realisasi.kpi_snapshots(id) deferrable initially deferred,
  refreeze_reason  text
);
create unique index one_live_snapshot
  on realisasi.kpi_snapshots (academic_year_id, kind) where superseded_by is null;
create index on realisasi.kpi_snapshots (frozen_at);
create index on realisasi.kpi_snapshots (frozen_by);

create table realisasi.kpi_snapshot_items (
  snapshot_id     uuid references realisasi.kpi_snapshots(id),
  kpi_code        text not null,
  bucket          text not null,
  ref_type        text not null,
  ref_id          text not null,
  is_late_addition boolean not null default false,
  primary key (snapshot_id, kpi_code, bucket, ref_type, ref_id)
);

-- Storage emulation + job bookkeeping (CONTRACTS §2.3) ---------------------
create table realisasi.file_blobs (
  path       text primary key,
  bucket     text not null check (bucket in ('realisasi-files','realisasi-transcripts')),
  data       bytea not null,
  mime       text not null,
  size_bytes int  not null check (size_bytes <= 10485760),
  created_by uuid,  -- kerjasama.profiles.id (no FK: adapter view)
  created_at timestamptz not null default now(),
  check (split_part(path,'/',1) = bucket)
);
create table realisasi.job_marks (key text primary key, created_at timestamptz not null default now());

-- 4. Mock external systems ---------------------------------------------------
create schema if not exists mock_baak;
create schema if not exists mock_hr;

create table mock_baak.students (
  nrp             text primary key,
  full_name       text not null,
  faculty_code    char(1) not null,
  faculty_name    text not null,
  prodi_name      text not null,
  category        text not null check (category in ('regular','inbound_exchange')),
  home_institution text,
  home_country_code text,
  intake_year     int not null,
  status          text not null check (status in ('active','graduated','inactive'))
);

create table mock_hr.employees (
  employee_id text primary key,
  full_name   text not null,
  unit_name   text not null,
  position    text,
  status      text not null check (status in ('active','inactive'))
);

-- >>> supabase/migrations/0003_core.sql
-- 0003_core: time, settings, errors, business days, chains, labels, role helpers, logging, notifications.

-- Time --------------------------------------------------------------------
-- demo_today (time travel) only applies when the deployment flag demo_time_travel is enabled (M9).
-- The flag lives in realisasi.deployment_flags, which no RPC writes; the demo seed enables it, production leaves it absent/false.
create function realisasi.demo_time_travel_enabled() returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce((select f.enabled from realisasi.deployment_flags f where f.key = 'demo_time_travel'), false)
$$;

create function realisasi._demo_today() returns date
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select (s.value #>> '{}')::date from realisasi.settings s
   where s.key = 'demo_today' and jsonb_typeof(s.value) = 'string' and realisasi.demo_time_travel_enabled()
$$;

create function realisasi.today() returns date
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce(realisasi._demo_today(), (now() at time zone 'Asia/Jakarta')::date)
$$;

create function realisasi.now_ts() returns timestamptz
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce((select (d + (now() at time zone 'Asia/Jakarta')::time) at time zone 'Asia/Jakarta'
                     from realisasi._demo_today() d where d is not null), now())
$$;

-- System caller = no JWT subject AND not running as the API roles (pg_cron, seeds, psql as owner).
-- An `authenticated` connection whose claims are empty is NOT the system (M4).
create function realisasi._is_system_caller() returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select auth.uid() is null
     and coalesce(nullif(current_setting('role', true), ''), 'none') not in ('authenticated', 'anon')
$$;

-- Settings ----------------------------------------------------------------
create function realisasi.setting_int(p_key text) returns int
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select (value #>> '{}')::numeric::int from realisasi.settings where key = p_key
$$;

create function realisasi.setting_num(p_key text) returns numeric
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select (value #>> '{}')::numeric from realisasi.settings where key = p_key
$$;

create function realisasi.settings_json() returns jsonb
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce(jsonb_object_agg(key, value order by key), '{}'::jsonb)
    from realisasi.settings where key <> 'demo_today'
$$;

-- Errors ------------------------------------------------------------------
create function realisasi._raise(p_code text, p_message text, p_detail jsonb default null) returns void
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
begin
  raise exception using errcode = 'P0001', message = p_code || ': ' || p_message,
                        detail = coalesce(p_detail::text, '');
end $$;

create function realisasi._require_uid() returns uuid
language plpgsql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v uuid := auth.uid();
begin
  -- a Realisasi user = a SIMKS account with an active realisasi.account_roles row (kerjasama.profiles.app_role not null)
  if v is null or not exists (select 1 from kerjasama.profiles where id = v and app_role is not null) then
    perform realisasi._raise('AUTH_REQUIRED', 'Sesi tidak valid. Silakan masuk kembali.');
  end if;
  return v;
end $$;

create function realisasi._forbidden() returns void
language sql security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select realisasi._raise('AUTH_FORBIDDEN', 'Anda tidak memiliki akses untuk tindakan ini.')
$$;

create function realisasi._not_found() returns void
language sql security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select realisasi._raise('NOT_FOUND', 'Data tidak ditemukan.')
$$;

create function realisasi._state_invalid() returns void
language sql security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select realisasi._raise('STATE_INVALID', 'Tindakan tidak dapat dilakukan pada status kegiatan saat ini.')
$$;

-- Renewal chains (Schema §5.1) -------------------------------------------
create function realisasi.chain_root(p_doc int) returns int
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  with recursive up as (
    select id, predecessor_id, 0 as depth from kerjasama.documents where id = p_doc
    union all
    select d.id, d.predecessor_id, up.depth + 1 from kerjasama.documents d join up on d.id = up.predecessor_id
    where up.depth < 100
  )
  select id from up where predecessor_id is null limit 1
$$;

create function realisasi.chain_current(p_doc int) returns int
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  with recursive down as (
    select id, 0 as depth from kerjasama.documents where id = p_doc
    union all
    select d.id, down.depth + 1 from kerjasama.documents d join down on d.predecessor_id = down.id
    where down.depth < 100
  )
  select id from down order by depth desc, id desc limit 1
$$;

-- every document with its chain root and depth, in one recursive pass (H6; chain_root() per document is O(docs x depth))
create function realisasi._chain_map() returns table(doc_id int, root_id int, depth int)
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  with recursive m as (
    select d.id as doc_id, d.id as root_id, 0 as depth from kerjasama.documents d where d.predecessor_id is null
    union all
    select d.id, m.root_id, m.depth + 1 from kerjasama.documents d join m on d.predecessor_id = m.doc_id where m.depth < 100
  )
  select doc_id, root_id, depth from m
$$;

-- Labels ------------------------------------------------------------------
create function realisasi.semester_label(p_semester_id int) returns text
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select initcap(s.term::text) || ' ' || ay.label
    from realisasi.semesters s join realisasi.academic_years ay on ay.id = s.academic_year_id
   where s.id = p_semester_id
$$;

create function realisasi._snapshot_label(p_kind realisasi.snapshot_kind, p_ay_label text) returns text
language sql immutable set search_path = realisasi, extensions, public, pg_temp as $$
  select case p_kind when 'ganjil_ytd' then 'Ganjil ' || p_ay_label
                     else 'Setahun ' || p_ay_label end
$$;

create function realisasi._fmt_date(p_d date) returns text
language sql immutable set search_path = realisasi, extensions, public, pg_temp as $$
  select to_char(p_d, 'DD') || ' ' ||
         (array['Jan','Feb','Mar','Apr','Mei','Jun','Jul','Agu','Sep','Okt','Nov','Des'])[extract(month from p_d)::int]
         || ' ' || to_char(p_d, 'YYYY')
$$;

create function realisasi._profile_name(p_id uuid) returns text
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select display_name from kerjasama.profiles where id = p_id
$$;

-- Role helpers ------------------------------------------------------------
create function realisasi.my_role() returns text
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select app_role from kerjasama.profiles where id = auth.uid()
$$;

create function realisasi.my_unit() returns int
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select unit_id from kerjasama.profiles where id = auth.uid()
$$;

create function realisasi.in_team(p_team realisasi.team) returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce(realisasi.my_role() = 'io_admin', false)
      or exists (select 1 from realisasi.team_members tm
                  join kerjasama.profiles p on p.id = tm.account_id and p.app_role in ('io_staff','io_admin')
                 where tm.account_id = auth.uid() and tm.team = p_team)
$$;

create function realisasi.is_io() returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce(realisasi.my_role() in ('io_staff','io_admin'), false)
$$;

create function realisasi.can_view_activity(p_activity uuid) returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select case realisasi.my_role()
    when 'io_admin' then true
    when 'io_staff' then true
    when 'viewer' then exists (select 1 from realisasi.activities a where a.id = p_activity and a.status = 'verified')
    when 'submitter' then exists (select 1 from realisasi.activity_units au
                                   where au.activity_id = p_activity and au.unit_id = realisasi.my_unit())
    else false end
$$;

create function realisasi.can_view_participants(p_activity uuid) returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select case
    when realisasi.my_role() = 'io_admin' then true
    when realisasi.my_role() = 'io_staff' then realisasi.in_team('mobility')
    when realisasi.my_role() = 'submitter' then exists (select 1 from realisasi.activity_units au
                                   where au.activity_id = p_activity and au.unit_id = realisasi.my_unit())
    else false end
$$;

-- Set-returning helpers for RLS policies: evaluated once per statement as hashed subplans (M10)
-- activities of the caller's unit (submitter only; own + co-unit)
create function realisasi.my_activity_ids() returns setof uuid
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select au.activity_id from realisasi.activity_units au
   where au.unit_id = (select realisasi.my_unit()) and (select realisasi.my_role()) = 'submitter'
$$;

-- activities visible to a non-IO caller (viewer: verified; submitter: own + co-unit). IO is handled by is_io() in the policy.
create function realisasi.visible_activity_ids() returns setof uuid
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select a.id from realisasi.activities a where (select realisasi.my_role()) = 'viewer' and a.status = 'verified'
  union all
  select realisasi.my_activity_ids()
$$;

-- participant set versions whose rows a submitter may read
create function realisasi.my_pset_ids() returns setof uuid
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select v.id from realisasi.participant_set_versions v where v.activity_id in (select realisasi.my_activity_ids())
$$;

-- caller may read participant identifiers of every activity they can see (io_admin, mobility team, submitters for own/co-unit)
create function realisasi.sees_participant_identifiers() returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce(realisasi.my_role() in ('io_admin','submitter'), false) or realisasi.in_team('mobility')
$$;

-- participant identifiers in log diffs replaced by counts (viewers see counts only)
create function realisasi._mask_log_diff(p jsonb) returns jsonb
language sql immutable set search_path = realisasi, extensions, public, pg_temp as $$
  select case when p is null or jsonb_typeof(p) <> 'object' then p else
    (p - 'students' - 'staff' - 'row_notes')
    || case when jsonb_typeof(p -> 'students') = 'object' then jsonb_build_object('students', jsonb_build_object(
           'added', coalesce(jsonb_array_length(nullif(p -> 'students' -> 'added', 'null')), 0),
           'removed', coalesce(jsonb_array_length(nullif(p -> 'students' -> 'removed', 'null')), 0))) else '{}'::jsonb end
    || case when jsonb_typeof(p -> 'staff') = 'object' then jsonb_build_object('staff', jsonb_build_object(
           'added', coalesce(jsonb_array_length(nullif(p -> 'staff' -> 'added', 'null')), 0),
           'removed', coalesce(jsonb_array_length(nullif(p -> 'staff' -> 'removed', 'null')), 0))) else '{}'::jsonb end
    || case when jsonb_typeof(p -> 'row_notes') = 'array' then jsonb_build_object('row_notes', jsonb_array_length(p -> 'row_notes')) else '{}'::jsonb end
  end
$$;

-- participant set version that counted for an activity at p_as_of (M2): the latest approved/superseded version
-- reviewed (approved) by then; falls back to the current approved version. p_as_of null = current approved.
create function realisasi._pset_as_of(p_activity uuid, p_as_of timestamptz) returns uuid
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce(
    (select v.id from realisasi.participant_set_versions v
      where p_as_of is not null and v.activity_id = p_activity and v.status in ('approved','superseded')
        and v.reviewed_at is not null and v.reviewed_at <= p_as_of
      order by v.version desc limit 1),
    (select v.id from realisasi.participant_set_versions v where v.activity_id = p_activity and v.status = 'approved'))
$$;

create function realisasi._is_unit_editor(p_activity uuid) returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce(realisasi.my_role() = 'io_admin', false)
      or (coalesce(realisasi.my_role() = 'submitter', false)
          and exists (select 1 from realisasi.activities a
                       where a.id = p_activity and a.submitter_unit_id = realisasi.my_unit()))
$$;

create function realisasi.in_frozen_period(p_activity uuid) returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select exists (select 1 from realisasi.activities a
                   join realisasi.kpi_snapshots s on s.superseded_by is null
                    and a.start_date between s.window_start and s.window_end
                  where a.id = p_activity)
$$;

create function realisasi.is_late_addition(p_activity uuid) returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select exists (select 1 from realisasi.activities a
                   join realisasi.kpi_snapshots s on s.superseded_by is null
                    and a.start_date between s.window_start and s.window_end
                  where a.id = p_activity and a.status = 'verified' and a.verified_at > s.frozen_at)
$$;

-- Permission predicates shared by RPCs and activity_detail.permissions (internal)
-- participant-edit permission (CONTRACTS §3.2 ensure_participant_draft)
create function realisasi._can_edit_participants(p_activity uuid, p_include_io boolean default true) returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select exists (select 1 from realisasi.activities a where a.id = p_activity and (
           (realisasi._is_unit_editor(a.id) and (a.status = 'draft' or a.mobility_status = 'revision_requested'))
        or (p_include_io and a.status = 'verified' and realisasi.in_team('mobility'))))
$$;

-- file write permission (CONTRACTS §3.3)
create function realisasi._can_write_files(p_activity uuid) returns boolean
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select exists (select 1 from realisasi.activities a where a.id = p_activity and (
           (realisasi._is_unit_editor(a.id) and (a.status = 'draft' or a.mobility_status = 'revision_requested'))
        or (a.status = 'verified' and realisasi.my_role() = 'io_admin')))
$$;

-- View helpers (definer, counts only; granted so security_invoker views can call them)
-- open student conflicts of an activity (count only; Revisi V.1 rule 2.1)
create function realisasi.activity_open_conflicts(p_activity uuid) returns int
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select count(*)::int from realisasi.participant_conflicts c
   where c.status = 'open' and (c.activity_a = p_activity or c.activity_b = p_activity)
$$;

create function realisasi.activity_participant_total(p_activity uuid) returns int
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce((select (select count(*) from realisasi.participant_students s where s.set_version_id = v.id)
                        + (select count(*) from realisasi.participant_staff st where st.set_version_id = v.id)
                     from realisasi.participant_set_versions v
                    where v.activity_id = p_activity and v.status <> 'draft'
                    order by v.version desc limit 1), 0)::int
$$;

-- Logging -----------------------------------------------------------------
create function realisasi._log(p_activity uuid, p_kind realisasi.log_kind, p_track realisasi.team, p_action text,
                               p_note text default null, p_diff jsonb default null) returns bigint
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_id bigint;
begin
  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (p_activity, p_kind, p_track, p_action, auth.uid(), p_note, p_diff,
          case when p_kind = 'update' then realisasi.in_frozen_period(p_activity) else false end,
          realisasi.now_ts())
  returning id into v_id;
  return v_id;
end $$;

-- Notifications -------------------------------------------------------------
create function realisasi._notify(p_recipient uuid, p_kind text, p_title text, p_body text, p_link text) returns void
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare v_email text;
begin
  select email into v_email from kerjasama.profiles where id = p_recipient and app_role is not null;
  if v_email is null then return; end if;
  insert into realisasi.notifications (recipient_id, kind, title, body, link, created_at)
  values (p_recipient, p_kind, p_title, p_body, p_link, realisasi.now_ts());
  insert into realisasi.email_outbox (to_email, subject, body, created_at)
  values (v_email, p_title, coalesce(p_body, '') || E'\n\n' || coalesce(p_link, ''), realisasi.now_ts());
end $$;

create function realisasi._notify_many(p_recipients uuid[], p_kind text, p_title text, p_body text, p_link text) returns int
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare r uuid; n int := 0;
begin
  for r in select distinct x from unnest(p_recipients) x where x is not null order by 1 loop
    perform realisasi._notify(r, p_kind, p_title, p_body, p_link);
    n := n + 1;
  end loop;
  return n;
end $$;

create function realisasi._team_ids(p_team realisasi.team) returns uuid[]
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce(array_agg(distinct tm.account_id), '{}') from realisasi.team_members tm where tm.team = p_team
$$;

create function realisasi._admin_ids() returns uuid[]
language sql stable security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select coalesce(array_agg(id order by id), '{}') from kerjasama.profiles where app_role = 'io_admin'
$$;

create function realisasi._notify_team(p_team realisasi.team, p_kind text, p_title text, p_body text, p_link text) returns void
language sql security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select realisasi._notify_many(realisasi._team_ids(p_team), p_kind, p_title, p_body, p_link);
  select null::void
$$;

create function realisasi._notify_admins(p_kind text, p_title text, p_body text, p_link text) returns void
language sql security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select realisasi._notify_many(realisasi._admin_ids(), p_kind, p_title, p_body, p_link);
  select null::void
$$;

create function realisasi._notify_unit(p_unit_id int, p_kind text, p_title text, p_body text, p_link text) returns void
language sql security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select realisasi._notify_many((select coalesce(array_agg(id), '{}') from kerjasama.profiles
                                  where app_role = 'submitter' and unit_id = p_unit_id),
                                p_kind, p_title, p_body, p_link);
  select null::void
$$;

create function realisasi._notify_viewers(p_kind text, p_title text, p_body text, p_link text) returns void
language sql security definer set search_path = realisasi, extensions, public, pg_temp as $$
  select realisasi._notify_many((select coalesce(array_agg(id), '{}') from kerjasama.profiles where app_role = 'viewer'),
                                p_kind, p_title, p_body, p_link);
  select null::void
$$;

commit;
select 'part 1 of 5 OK - now run part 2' as status;
