-- seed-supabase/01_config (simks-partnership): same settings/calendar/holidays/Jenis/SDGs as the local demo seed
-- (deployment-agnostic; enables the demo_time_travel deployment flag), plus SIMKS's own public.holidays merged in
-- read-only. Idempotent. Applied by scripts/db-deploy-supabase.sh; never by scripts/db-reset.sh.
\ir ../seed/01_config.sql

-- SIMKS keeps national holidays in public.holidays(tanggal, keterangan); reuse them (read only) for SLA business days.
do $$
begin
  if to_regclass('public.holidays') is not null then
    execute $q$
      insert into realisasi.holidays (day, name)
      select distinct on (h.tanggal) h.tanggal, coalesce(nullif(btrim(h.keterangan), ''), 'Hari libur')
        from public.holidays h
       where h.tanggal between date '2025-01-01' and date '2027-12-31'
       order by h.tanggal, h.id
      on conflict (day) do nothing $q$;
  end if;
end $$;
