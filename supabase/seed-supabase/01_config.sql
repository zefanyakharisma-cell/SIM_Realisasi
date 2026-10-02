-- seed-supabase/01_config (simks-partnership): same settings/calendar/Jenis Kegiatan rules/SDGs as the local demo seed
-- (deployment-agnostic; enables the demo_time_travel deployment flag). Idempotent. Applied by
-- scripts/db-deploy-supabase.sh; never by scripts/db-reset.sh. (Revisi V.1: no SLA, so SIMKS holidays are not needed.)
\ir ../seed/01_config.sql
