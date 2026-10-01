-- 0001_enums
create schema if not exists realisasi;

create type realisasi.activity_status   as enum ('draft','in_verification','revision_requested','verified','rejected');
create type realisasi.track_status      as enum ('not_required','pending','revision_requested','approved','rejected');
create type realisasi.direction         as enum ('inbound','outbound','none');
create type realisasi.activity_mode     as enum ('offline','online','hybrid');
create type realisasi.funding_source    as enum ('pcu','partner','government','participant','mixed','none');
create type realisasi.file_kind         as enum ('ia','ir','evidence');
create type realisasi.person_role       as enum ('speaker','visiting_lecturer','researcher','staff_visitor','other');
create type realisasi.student_section   as enum ('internal','inbound');
create type realisasi.pset_status       as enum ('draft','pending','revision_requested','approved','superseded');
create type realisasi.known_source      as enum ('surat_tugas','news','faculty_report','loa_visa_letter','email','other');
create type realisasi.known_status      as enum ('unmatched','matched','dismissed');
create type realisasi.semester_term     as enum ('ganjil','genap');
create type realisasi.snapshot_kind     as enum ('ganjil_ytd','genap_full_year');
create type realisasi.dup_status        as enum ('open','linked','dismissed');
create type realisasi.log_kind          as enum ('verification','revision','update','system');
create type realisasi.team              as enum ('partnership','mobility');
