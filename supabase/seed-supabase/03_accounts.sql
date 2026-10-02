-- seed-supabase/03_accounts (simks-partnership): which REAL SIMKS accounts (public.akun) use SIM Realisasi, and their
-- verification teams. Written only into realisasi.*; SIMKS roles are untouched. Idempotent: re-running resets these
-- accounts to the roles below (other account_roles rows are left alone). Revisi V.1: one verification team (Mobility).
--   akun  1 kepala-kui@petra.ac.id          io_admin   (mobility)
--   akun 11 staff-partnership@petra.ac.id   io_staff   (mobility)
--   akun 10 head-partnership@petra.ac.id    io_staff   (mobility)
--   akun  3 dekan-sbm@petra.ac.id           submitter  unit 4 (School of Business and Management)
--   akun  4 kaprodi-manajemen@petra.ac.id   submitter  unit 5 (Prodi Manajemen)
--   akun  9 viewer@petra.ac.id              viewer
--   akun  6 rektor@petra.ac.id              viewer
do $$
declare missing int[];
begin
  select array_agg(x order by x) into missing from unnest(array[1, 3, 4, 6, 9, 10, 11]) x
   where not exists (select 1 from public.akun a where a.id = x);
  if missing is not null then
    raise exception 'SIMKS akun % not found; adjust supabase/seed-supabase/03_accounts.sql', missing;
  end if;
end $$;

insert into realisasi.account_roles (akun_id, app_role, unit_id) values
  (1, 'io_admin', null), (11, 'io_staff', null), (10, 'io_staff', null),
  (3, 'submitter', 4), (4, 'submitter', 5),
  (9, 'viewer', null), (6, 'viewer', null)
on conflict (akun_id) do update set app_role = excluded.app_role, unit_id = excluded.unit_id, updated_at = now();

insert into realisasi.team_members (account_id, team)
select p.id, t.team::realisasi.team
  from (values (1, 'mobility'), (11, 'mobility'), (10, 'mobility')) t(akun_id, team)
  join kerjasama.profiles p on p.akun_id = t.akun_id
on conflict do nothing;
