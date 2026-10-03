-- seed-supabase/02b_registry_more (simks-partnership): a mock BAAK registry big enough for realistic participant
-- lists (used by 05_activities_history and 06_participants). Mockup only; written into mock_baak.* only. Idempotent
-- (existing NRPs are skipped).
--   + 735 PETRA students: 15 prodi x intakes 2020-2026, NRP <prefix><yy>8<nnn> (e.g. D31238001); intakes older than
--     the prodi length are 'graduated', every 13th student 'inactive'.
--   + 378 inbound exchange students: 12 per real SIMKS partner per intake 2024-2026 (30 for Kyoto Sangyo University),
--     NRP X<1x><yy>8<nnn>, home institution = the partner's SIMKS name (R-17: every inbound student holds an NRP).

drop table if exists pg_temp.h6_prodi;
create temp table h6_prodi (prefix text, fcode text, fname text, prodi text, per_intake int, years int);
insert into h6_prodi values
  ('A11', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Teknik Sipil', 6, 4),
  ('A12', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Arsitektur', 8, 4),
  ('B11', 'B', 'Fakultas Teknologi Industri', 'Informatika', 10, 4),
  ('B12', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 6, 4),
  ('B13', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 8, 4),
  ('C21', 'C', 'Fakultas Seni dan Desain', 'Desain Komunikasi Visual', 10, 4),
  ('E41', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Sastra Inggris', 5, 4),
  ('E42', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Ilmu Komunikasi', 5, 4),
  ('D31', 'D', 'Fakultas Bisnis dan Ekonomi', 'Manajemen', 12, 4),
  ('D32', 'D', 'Fakultas Bisnis dan Ekonomi', 'Akuntansi', 8, 4),
  ('D33', 'D', 'Fakultas Bisnis dan Ekonomi', 'International Business Management', 8, 4),
  ('D34', 'D', 'Fakultas Bisnis dan Ekonomi', 'Hotel Management', 8, 4),
  ('F51', 'F', 'Fakultas Keguruan dan Ilmu Pendidikan', 'Pendidikan Guru Sekolah Dasar', 5, 4),
  ('G61', 'G', 'Fakultas Kedokteran', 'Kedokteran', 3, 4),
  ('H71', 'H', 'Program Pascasarjana', 'Magister Manajemen', 3, 2);

with names as (
  select array['Adrian','Agnes','Albert','Amanda','Andreas','Angela','Bryan','Calvin','Catherine','Christian','Clara',
               'Daniel','Debora','Edward','Elisabeth','Evelyn','Felix','Florencia','Gabriel','Gloria','Hans','Hana',
               'Ivan','Jessica','Jonathan','Josephine','Kevin','Kezia','Leonardo','Lidya','Matthew','Michelle','Nathan',
               'Natalia','Patrick','Priscilla','Rafael','Rebecca','Samuel','Stefani','Timothy','Vanessa','Vincent',
               'Yohana','Yosua','Zefanya'] f,
         array['Gunawan','Halim','Hartono','Hidayat','Kurniawan','Kusuma','Lesmana','Liem','Pranoto','Prasetyo',
               'Purnomo','Salim','Santoso','Saputra','Setiawan','Sugianto','Susanto','Sutanto','Tanjung','Tanoto',
               'Tjahjono','Wibowo','Widjaja','Wijaya','Winata','Yulianto','Budiman','Chandra','Darmawan','Effendi'] l)
insert into mock_baak.students (nrp, full_name, faculty_code, faculty_name, prodi_name, category, home_institution,
                                home_country_code, intake_year, status)
select p.prefix || right(y::text, 2) || '8' || lpad(i::text, 3, '0'),
       n.f[1 + abs(hashtext(p.prefix || y || i || 'f')) % cardinality(n.f)] || ' ' ||
       n.l[1 + abs(hashtext(p.prefix || y || i || 'l')) % cardinality(n.l)],
       p.fcode, p.fname, p.prodi, 'regular', null, null, y,
       case when y <= 2026 - p.years then 'graduated' when i % 13 = 0 then 'inactive' else 'active' end
  from h6_prodi p cross join generate_series(2020, 2026) y cross join generate_series(1, p.per_intake) i cross join names n
on conflict (nrp) do nothing;

drop table if exists pg_temp.h6_partner;
create temp table h6_partner (idx int, name text, cc text, f text[], l text[], per_year int);
insert into h6_partner values
  (11, 'Kyoto Sangyo University', 'JP', '{Haruto,Yui,Sota,Hina,Ren,Aoi,Yuto,Mio,Kaito,Sakura,Riku,Yuna}',
       '{Sato,Suzuki,Takahashi,Tanaka,Watanabe,Ito,Yamamoto,Nakamura,Kobayashi,Kato}', 30),
  (12, 'Yonsei University', 'KR', '{Min-jun,Seo-yeon,Ji-ho,Ha-eun,Do-yun,Ji-woo,Seo-jun,Su-ah,Ye-jun,Chae-won}',
       '{Kim,Lee,Park,Choi,Jung,Kang,Cho,Yoon,Jang,Lim}', 12),
  (13, 'National Taiwan University', 'TW', '{Chia-hao,Yu-ting,Po-han,Hsin-yi,Cheng-en,Pei-shan,Tzu-yang,Wan-ting}',
       '{Chen,Lin,Huang,Chang,Lee,Wang,Wu,Liu,Tsai,Yang}', 12),
  (14, 'National University of Singapore', 'SG', '{Wei Jie,Xin Yi,Jun Hao,Hui Min,Ryan,Sarah,Marcus,Nur Aisyah,Arjun,Chloe}',
       '{Tan,Lim,Lee,Ng,Ong,Wong,Goh,Chua,Rahman,Nair}', 12),
  (15, 'Chulalongkorn University', 'TH', '{Kittipong,Napat,Siriporn,Thanawat,Pimchanok,Chayanin,Warut,Kanokwan}',
       '{Srisuk,Wongsa,Chaiyaporn,Rattanakul,Saengthong,Phromma,Boonmee,Kaewkla}', 12),
  (16, 'Ateneo de Manila University', 'PH', '{Maria,Jose,Angelica,Miguel,Patricia,Gabriel,Bianca,Rafael,Andrea,Carlo}',
       '{Santos,Reyes,Cruz,Bautista,Garcia,Mendoza,Torres,Villanueva,Ramos,Aquino}', 12),
  (17, 'University of Amsterdam', 'NL', '{Daan,Sanne,Lucas,Emma,Sem,Julia,Milan,Lotte,Thijs,Fleur}',
       '{de Vries,Jansen,de Jong,Bakker,Visser,Smit,Meijer,Mulder,de Boer,Bos}', 12),
  (18, 'Ludwig Maximilian University of Munich', 'DE', '{Lukas,Lea,Felix,Anna,Jonas,Lena,Leon,Marie,Paul,Sophie}',
       '{Müller,Schmidt,Schneider,Fischer,Weber,Meyer,Wagner,Becker,Hoffmann,Schulz}', 12),
  (19, 'University of Sydney', 'AU', '{Oliver,Charlotte,Jack,Olivia,William,Amelia,Noah,Isla,Thomas,Mia}',
       '{Smith,Jones,Williams,Brown,Wilson,Taylor,Nguyen,Johnson,Martin,White}', 12);

insert into mock_baak.students (nrp, full_name, faculty_code, faculty_name, prodi_name, category, home_institution,
                                home_country_code, intake_year, status)
select 'X' || p.idx || right(y::text, 2) || '8' || lpad(i::text, 3, '0'),
       p.f[1 + abs(hashtext(p.name || y || i || 'f')) % cardinality(p.f)] || ' ' ||
       p.l[1 + abs(hashtext(p.name || y || i || 'l')) % cardinality(p.l)],
       'D', 'Fakultas Bisnis dan Ekonomi', 'Program Pertukaran (Inbound)', 'inbound_exchange', p.name, p.cc, y,
       case when y < 2026 then 'graduated' else 'active' end
  from h6_partner p cross join generate_series(2024, 2026) y cross join generate_series(1, p.per_year) i
on conflict (nrp) do nothing;
