#!/usr/bin/env bash
# Deploy SIM Realisasi INTO the SIM Kerjasama Supabase project (simks-partnership).
#
#   DATABASE_URL=postgresql://postgres.<ref>:<pw>@<pooler-host>:5432/postgres scripts/db-deploy-supabase.sh [mode]
#
# Modes:
#   (none)       apply supabase/migrations/*.sql then supabase/seed-supabase/*.sql in ONE transaction (psql -1).
#                Refuses when schema realisasi already exists (migrations are not re-runnable).
#   --dry-run    print the plan (target, files, checks) and exit; connects to nothing.
#   --check      read-only preflight against DATABASE_URL (SIMKS tables, roles, auth.uid, existing schemas, akun ids).
#   --seed-only  re-apply supabase/seed-supabase/*.sql only (idempotent), in one transaction.
#   --rehearse   LOCAL rehearsal: recreate the database named in DATABASE_URL (must be local), load the SIMKS-shaped
#                stub (supabase/local) + the discovered-data fixture (supabase/rehearsal), then run the normal deploy.
#
# Never applies supabase/local/*.sql or supabase/seed/*.sql to Supabase. Use the session pooler (port 5432) or the
# direct connection: DDL + one long transaction do not work through the transaction pooler (6543).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-deploy}"
case "$MODE" in deploy|--dry-run|--check|--seed-only|--rehearse) ;; *) echo "unknown mode: $MODE" >&2; exit 2 ;; esac

shopt -s nullglob
MIGRATIONS=("$ROOT"/supabase/migrations/*.sql)
SEEDS=("$ROOT"/supabase/seed-supabase/*.sql)
masked() { python3 -c 'import sys,urllib.parse as u; p=u.urlparse(sys.argv[1]); n=p.netloc
if p.password: n=n.replace(":"+p.password+"@", ":***@")
print(u.urlunparse(p._replace(netloc=n)))' "$1"; }

if [ "$MODE" = "--dry-run" ]; then
  echo "SIM Realisasi -> SIM Kerjasama Supabase deploy plan"
  echo "target: $( [ -n "${DATABASE_URL:-}" ] && masked "$DATABASE_URL" || echo '<DATABASE_URL not set>')"
  echo
  echo "1. preflight (read-only): roles anon/authenticated/service_role, auth.uid(), SIMKS tables public.unit, jenis_unit,"
  echo "   negara, partner, proposal_dokumen, dokumen_kerja_sama, partner_pengusul, proposal_dokumen_unit, jabatan, akun;"
  echo "   schemas realisasi/kerjasama/mock_baak/mock_hr must NOT exist."
  echo "2. one transaction (psql --single-transaction, ON_ERROR_STOP):"
  for f in "${MIGRATIONS[@]}"; do echo "     migrate  ${f#"$ROOT"/}"; done
  for f in "${SEEDS[@]}"; do echo "     seed     ${f#"$ROOT"/}"; done
  echo "   creates schemas realisasi, kerjasama, mock_baak, mock_hr; nothing in public; no writes to SIMKS tables;"
  echo "   pg_cron job 'realisasi-daily-jobs' (18:00 UTC) when pg_cron is available."
  echo "3. verify: as role authenticated (claims of akun 1), kerjasama.documents/units/partners counts = SIMKS row counts;"
  echo "   kerjasama.profiles lists the 7 seeded accounts; activities seeded."
  echo
  echo "NOT applied: supabase/local/*.sql (stubs), supabase/seed/*.sql (local demo fixtures), supabase/rehearsal/*.sql."
  echo "Rollback after a successful deploy: drop schema realisasi, kerjasama, mock_baak, mock_hr cascade;"
  echo "  select cron.unschedule('realisasi-daily-jobs');   -- SIMKS data is untouched either way"
  exit 0
fi

: "${DATABASE_URL:?DATABASE_URL must point at the target database}"
export PGOPTIONS="${PGOPTIONS:-} -c client_min_messages=warning"
PSQL=(psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -q)

if [ "$MODE" = "--rehearse" ]; then
  case "$DATABASE_URL" in *supabase.co*|*supabase.com*) echo "--rehearse is for a LOCAL scratch database only" >&2; exit 2 ;; esac
  DB_NAME="$(python3 -c 'import sys,urllib.parse as u; print(u.urlparse(sys.argv[1]).path.lstrip("/"))' "$DATABASE_URL")"
  case "$DB_NAME" in ""|postgres|sim_realisasi) echo "--rehearse needs a scratch database name (not '$DB_NAME')" >&2; exit 2 ;; esac
  ADMIN_URL="$(python3 -c 'import sys,urllib.parse as u; p=u.urlparse(sys.argv[1]); print(u.urlunparse(p._replace(path="/postgres")))' "$DATABASE_URL")"
  echo "rehearsal: recreating $DB_NAME with the SIMKS stub + discovered-data fixture"
  psql "$ADMIN_URL" -X -q -v ON_ERROR_STOP=1 -c "drop database if exists \"$DB_NAME\"" -c "create database \"$DB_NAME\""
  for f in "$ROOT"/supabase/local/*.sql "$ROOT"/supabase/rehearsal/*.sql; do
    echo "  load ${f#"$ROOT"/}"; "${PSQL[@]}" -o /dev/null -f "$f"
  done
  MODE=deploy
fi

preflight() {
  "${PSQL[@]}" -tA <<'SQL'
begin transaction read only;
select 'role ' || r || ': ' || case when exists (select from pg_roles where rolname = r) then 'ok' else 'MISSING' end
  from unnest(array['anon','authenticated','service_role']) r;
select 'auth.uid(): ' || case when to_regprocedure('auth.uid()') is not null then 'ok' else 'MISSING' end;
select 'public.' || t || ': ' || coalesce((xpath('/row/n/text()', query_to_xml('select count(*) n from public.' || t, false, true, '')))[1]::text || ' rows', 'MISSING')
  from unnest(array['unit','jenis_unit','negara','partner','proposal_dokumen','dokumen_kerja_sama','partner_pengusul',
                    'proposal_dokumen_unit','jabatan','akun']) t
 where to_regclass('public.' || t) is not null
union all
select 'public.' || t || ': MISSING' from unnest(array['unit','jenis_unit','negara','partner','proposal_dokumen','dokumen_kerja_sama',
       'partner_pengusul','proposal_dokumen_unit','jabatan','akun']) t where to_regclass('public.' || t) is null;
select 'schema ' || s || ': ' || case when exists (select from pg_namespace where nspname = s) then 'EXISTS' else 'absent' end
  from unnest(array['realisasi','kerjasama','mock_baak','mock_hr']) s;
select 'akun ' || x || ': ' || case when to_regclass('public.akun') is null then '?'
         else coalesce((xpath('/row/e/text()', query_to_xml('select email e from public.akun where id = ' || x, false, true, '')))[1]::text, 'MISSING') end
  from unnest(array[1,3,4,6,9,10,11]) x;
select 'pg_cron: ' || case when exists (select from pg_available_extensions where name = 'pg_cron') then 'available' else 'absent' end;
rollback;
SQL
}

echo "target: $(masked "$DATABASE_URL")"
echo "--- preflight"
PRE="$(preflight)"; printf '%s\n' "$PRE" | sed 's/^/  /'
[ "$MODE" = "--check" ] && exit 0
if printf '%s\n' "$PRE" | grep -q 'MISSING'; then echo "preflight failed (MISSING above)" >&2; exit 1; fi

FILES=()
if [ "$MODE" = "deploy" ]; then
  if printf '%s\n' "$PRE" | grep -qE '^schema (realisasi|kerjasama|mock_baak|mock_hr): EXISTS'; then
    echo "Realisasi is already installed (schema exists). Use --seed-only to re-apply the idempotent seeds." >&2; exit 1
  fi
  FILES+=("${MIGRATIONS[@]}")
fi
FILES+=("${SEEDS[@]}")

ARGS=()
for f in "${FILES[@]}"; do echo "  apply ${f#"$ROOT"/}"; ARGS+=(-f "$f"); done
echo "--- applying ${#FILES[@]} files in one transaction"
"${PSQL[@]}" -o /dev/null --single-transaction "${ARGS[@]}"

echo "--- verify"
"${PSQL[@]}" -tA <<'SQL' | sed 's/^/  /'
select 'SIMKS rows: dokumen=' || (select count(*) from public.dokumen_kerja_sama) || ' unit=' || (select count(*) from public.unit)
       || ' partner=' || (select count(*) from public.partner);
begin;
do $$ begin perform set_config('request.jwt.claims', json_build_object('sub', (select id from kerjasama.profiles where akun_id = 1), 'role', 'authenticated')::text, true); end $$;
set local role authenticated;
select 'as authenticated: documents=' || (select count(*) from kerjasama.documents) || ' units=' || (select count(*) from kerjasama.units)
       || ' partners=' || (select count(*) from kerjasama.partners) || ' countries=' || (select count(*) from kerjasama.countries)
       || ' profiles=' || (select count(*) from kerjasama.profiles) || ' my_role=' || coalesce(realisasi.my_role(), 'NULL')
       || ' activities=' || (select count(*) from realisasi.activities);
rollback;
select 'account ' || akun_id || ' ' || email || ' -> ' || coalesce(app_role, 'NO ACCESS') || ' unit ' || coalesce(unit_id::text, '-') || ' id ' || id
  from kerjasama.profiles order by akun_id;
select 'unmapped negara.kode: ' || coalesce(string_agg(kode, ', '), 'none') from public.negara n
 where not exists (select 1 from kerjasama.iso3166 i where i.alpha3 = upper(btrim(n.kode)));
SQL
echo "db-deploy-supabase OK"
