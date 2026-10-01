-- 0001_kerjasama_adapter: read-only adapter from the live SIM Kerjasama (SIMKS) schema to the Schema §1.1 shapes.
--
-- SIMKS owns schema `public` (Indonesian table names, integer ids, ISO alpha-3 country codes, akun/jabatan accounts,
-- proposal-based partners/scope/renewal links). Realisasi never writes SIMKS tables and never creates objects in
-- `public`. Every Realisasi object reads SIMKS only through the views in schema `kerjasama` created here:
--   kerjasama.units, countries, partners, documents, document_partners, document_scope_units, profiles
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
       coalesce(u.is_active, true) as is_active
  from public.unit u
  left join public.unit pu on pu.id = u.id_parent_unit;

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
                kerjasama.document_partners, kerjasama.document_scope_units, kerjasama.profiles to authenticated;
