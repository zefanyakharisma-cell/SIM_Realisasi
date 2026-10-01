-- Used only by `scripts/db-deploy-supabase.sh --reset-realisasi`, inside the same transaction as the redeploy.
-- Removes ONLY objects owned by SIM Realisasi (its four schemas, its pg_cron job, its migration-history rows), e.g. to
-- clean up a partial install. SIM Kerjasama tables in schema public are never touched.
drop schema if exists realisasi, kerjasama, mock_baak, mock_hr cascade;

do $$
begin
  -- dynamic SQL: these objects only exist on Supabase / with pg_cron
  if to_regclass('cron.job') is not null then
    execute $q$select cron.unschedule(jobid) from cron.job where jobname = 'realisasi-daily-jobs'$q$;
  end if;
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    execute $q$delete from supabase_migrations.schema_migrations where name like 'realisasi\_%'$q$;
  end if;
end $$;
