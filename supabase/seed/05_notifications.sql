-- 05_notifications: a few read/unread notifications per account (+ matching email_outbox rows). Idempotent per (recipient, kind, title).
with n (recipient, kind, title, body, link, created_at, read_at) as (values
  ('00000000-0000-4000-8000-000000000001'::uuid, 'conflict_found', 'Duplikat mahasiswa: RL-2026-0018', '2 mahasiswa pada kegiatan RL-2026-0018 juga diklaim unit lain pada tanggal yang sama. Pilih kegiatan yang diakui.', '/realisasi/verifikasi/mobilitas#duplikat', '2026-09-28 08:05+07'::timestamptz, null::timestamptz),
  ('00000000-0000-4000-8000-000000000002', 'submission_received', 'Perlu diverifikasi: RL-2026-0030', 'Kegiatan menunggu Verifikasi Mobilitas.', '/realisasi/verifikasi/mobilitas', '2026-09-29 08:00+07', null),
  ('00000000-0000-4000-8000-000000000003', 'submission_received', 'Perlu diverifikasi: RL-2026-0029', 'Kegiatan menunggu Verifikasi Mobilitas.', '/realisasi/verifikasi/mobilitas', '2026-09-21 08:00+07', null),
  ('00000000-0000-4000-8000-000000000003', 'conflict_found', 'Duplikat mahasiswa: RL-2026-0018', '2 mahasiswa pada kegiatan RL-2026-0018 juga diklaim unit lain pada tanggal yang sama. Pilih kegiatan yang diakui.', '/realisasi/verifikasi/mobilitas#duplikat', '2026-09-28 08:05+07', null),
  ('00000000-0000-4000-8000-000000000003', 'submission_received', 'Perlu diverifikasi: RL-2026-0014', 'Kegiatan menunggu Verifikasi Mobilitas.', '/realisasi/verifikasi/mobilitas', '2026-08-29 08:00+07', '2026-08-29 10:00+07'),
  ('00000000-0000-4000-8000-000000000004', 'revision_requested', 'Perlu revisi: RL-2026-0016', 'Satu NRP tidak sesuai surat tugas; mohon perbarui data peserta.', '/realisasi/kegiatan/a0000000-0000-4000-8000-000000000016/revisi', '2026-09-16 09:00+07', null),
  ('00000000-0000-4000-8000-000000000004', 'activity_verified', 'Kegiatan terverifikasi: RL-2026-0013', 'Kegiatan telah terverifikasi.', '/realisasi/kegiatan/a0000000-0000-4000-8000-000000000013', '2026-09-10 14:00+07', '2026-09-10 15:00+07'),
  ('00000000-0000-4000-8000-000000000005', 'activity_verified', 'Kegiatan tercatat: RL-2026-0017', 'Kegiatan "Joint Seminar Pemasaran Digital Asia" sudah tercatat dan dihitung dalam capaian Renstra.', '/realisasi/kegiatan/a0000000-0000-4000-8000-000000000017', '2026-09-21 10:00+07', null),
  ('00000000-0000-4000-8000-000000000006', 'conflict_resolved', 'Mahasiswa dihitung di unit lain: RL-2026-0014', 'Tim Mobilitas menetapkan 12 mahasiswa dihitung pada kegiatan RL-2026-0013 (FTI).', '/realisasi/kegiatan/a0000000-0000-4000-8000-000000000014', '2026-08-31 10:00+07', null),
  ('00000000-0000-4000-8000-000000000007', 'deadline_weekly', 'Batas pelaporan 13 Sep 2026: RL-2026-0023', 'Draf kegiatan harus diajukan paling lambat 13 Sep 2026.', '/realisasi/kegiatan/baru?draft=a0000000-0000-4000-8000-000000000023', '2026-09-27 07:00+07', null)
), ins as (
  insert into realisasi.notifications (recipient_id, kind, title, body, link, created_at, read_at)
  select n.recipient, n.kind, n.title, n.body, n.link, n.created_at, n.read_at from n
   where not exists (select 1 from realisasi.notifications x where x.recipient_id = n.recipient and x.kind = n.kind and x.title = n.title)
  returning recipient_id, title, body, link, created_at)
insert into realisasi.email_outbox (to_email, subject, body, created_at, sent_at)
select p.email, ins.title, coalesce(ins.body, '') || E'\n\n' || coalesce(ins.link, ''), ins.created_at, null
  from ins join kerjasama.profiles p on p.id = ins.recipient_id;
