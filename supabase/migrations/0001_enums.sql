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
