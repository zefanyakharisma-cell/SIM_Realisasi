-- 0017_pg_cron: schedule run_daily_jobs at 18:00 UTC (01:00 WIB) when pg_cron is available.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('realisasi-daily-jobs', '0 18 * * *', $c$select realisasi.run_daily_jobs()$c$);
  end if;
exception when others then
  raise notice 'pg_cron unavailable: %', sqlerrm;
end $$;
