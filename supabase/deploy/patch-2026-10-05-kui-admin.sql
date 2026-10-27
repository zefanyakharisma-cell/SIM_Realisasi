-- LIVE PATCH for simks-partnership (2026-10-05), same data as supabase/seed-supabase/03_accounts.sql of this commit:
--   every KUI account becomes io_admin (all features unlocked):
--   akun 1 Kepala Kantor Kerja Sama dan Urusan Internasional, akun 10 Head of Partnership and Global Alliance,
--   akun 11 Staff of Partnership and Global Alliance. Mobility team membership is kept. Idempotent. One transaction.
begin;
update realisasi.account_roles set app_role = 'io_admin', unit_id = null, updated_at = now()
 where akun_id in (1, 10, 11) and app_role is distinct from 'io_admin';
insert into realisasi.team_members (account_id, team)
select p.id, 'mobility'::realisasi.team from kerjasama.profiles p where p.akun_id in (1, 10, 11)
on conflict do nothing;
select akun_id, app_role from realisasi.account_roles where akun_id in (1, 10, 11) order by akun_id;
commit;
