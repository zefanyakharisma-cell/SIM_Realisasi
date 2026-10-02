-- Schema fingerprint printed by scripts/db-deploy-supabase.sh after deploying. A deploy of the same commit must print the
-- same three lines as a local `--rehearse` (function bodies, columns and policies of the Realisasi schemas).
-- Line endings are normalised (CR removed): pasting via the Supabase SQL Editor on Windows stores CRLF in function bodies.
select 'functions' k, count(*)::text n, md5(string_agg(n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')='||md5(replace(p.prosrc, chr(13), '')), ',' order by n.nspname, p.proname, pg_get_function_identity_arguments(p.oid))) h
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('realisasi','kerjasama','mock_baak','mock_hr')
union all
select 'columns', count(*)::text, md5(string_agg(table_schema||'.'||table_name||'.'||column_name||':'||data_type, ',' order by table_schema, table_name, column_name))
  from information_schema.columns where table_schema in ('realisasi','kerjasama','mock_baak','mock_hr')
union all
select 'policies', count(*)::text, md5(string_agg(schemaname||'.'||tablename||'.'||policyname, ',' order by schemaname, tablename, policyname))
  from pg_policies where schemaname in ('realisasi','kerjasama');
