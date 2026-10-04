-- seed-supabase/11_refreeze_tambahan (simks-partnership): re-freezes the AY 2025/2026 snapshots once more after the
-- additional bulk kegiatan (10_kegiatan_tambahan_1..8, R-58), as of their original freeze moments, so Ganjil and Setahun
-- include them; the earlier snapshots stay as superseded. No-op on a fresh install (90_freeze.sql freezes later), when
-- the additional kegiatan are absent, and when already done.
-- Self-contained and idempotent, so it can be run on its own: Supabase SQL Editor or one statement batch.
-- Writes only realisasi.*; SIM Kerjasama tables are only read.

do $$
declare s realisasi.kpi_snapshots; v_reason text := 'Bekukan ulang setelah impor kegiatan tambahan 2025/2026';
begin
  for s in select * from realisasi.kpi_snapshots
            where academic_year_id = 1 and superseded_by is null and refreeze_reason is distinct from v_reason
              and exists (select 1 from realisasi.activities a where a.id = ('b5000000-0000-4000-8000-' || lpad('221', 12, '0'))::uuid)
            order by frozen_at
  loop
    perform realisasi._freeze(s.academic_year_id, s.kind, s.frozen_at, (select id from kerjasama.profiles where akun_id = 1),
                              v_reason, s.id);
  end loop;
end $$;
