#!/usr/bin/env bash
# Run supabase/tests/*.sql (each wrapped in begin … rollback). Exit non-zero if any file fails.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for f in "$ROOT/.env.local" "$ROOT/.env"; do
  if [ -f "$f" ] && [ -z "${DATABASE_URL:-}" ]; then
    v="$(grep -E '^DATABASE_URL=' "$f" | tail -n1 | cut -d= -f2-)"; v="${v%\"}"; v="${v#\"}"
    [ -n "$v" ] && export DATABASE_URL="$v"
  fi
done
DATABASE_URL="${DATABASE_URL:-postgresql://postgres@localhost:54322/sim_realisasi}"

pass=0; fail=0; checks=0; failed=()

# The acceptance tests count on the S-01..S-34 scenarios only; the bulk Kegiatan seed (RL-2026-0101..0300) shifts them.
if [ "$(psql "$DATABASE_URL" -X -tAc "select count(*) from realisasi.activities where code between 'RL-2026-0101' and 'RL-2026-0300'" 2>/dev/null)" != "0" ]; then
  echo "db-test: the database holds the bulk Kegiatan seed; run 'SEED_BULK=0 npm run db:reset' first." >&2
  exit 2
fi

# Lint (SIMKS integration): Realisasi migrations never create/alter objects in SIMKS's schema public, and only the
# bootstrap precondition check (0000) and the adapter (0001_kerjasama_adapter) may mention public.* at all.
lint="$( { grep -nHiE '^[^-]*\b(create|alter|drop|comment on|grant|revoke|insert into|update|delete from|truncate)\b[^;]*\bpublic\.' \
             "$ROOT"/supabase/migrations/*.sql | grep -viE 'revoke [a-z, ]+ from public|grant [a-z, ]+ to public'
           grep -nHE '\bpublic\.' "$ROOT"/supabase/migrations/*.sql | grep -vE '/(0000_bootstrap|0001_kerjasama_adapter)\.sql:' \
             | grep -vE 'search_path *=|^[^:]+:[0-9]+: *--'; } || true)"
if [ -z "$lint" ]; then
  echo "PASS migration-lint (no Realisasi objects in public; public.* only in 0000/0001)"; pass=$((pass + 1))
else
  echo "FAIL migration-lint"; printf '%s\n' "$lint" | sed 's/^/    /'; fail=$((fail + 1)); failed+=("migration-lint")
fi
for f in "$ROOT"/supabase/tests/*.sql; do
  name="$(basename "$f")"
  out="$(psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -q -f "$f" 2>&1)"
  rc=$?
  n="$(printf '%s\n' "$out" | grep -c 'NOTICE:  ok - ' || true)"
  checks=$((checks + n))
  if [ $rc -eq 0 ]; then
    echo "PASS $name ($n checks)"; pass=$((pass + 1))
  else
    echo "FAIL $name ($n checks passed before failure)"; fail=$((fail + 1)); failed+=("$name")
    printf '%s\n' "$out" | grep -v 'NOTICE:  ok - ' | sed 's/^/    /' | tail -n 25
  fi
  if [ -n "${VERBOSE:-}" ]; then printf '%s\n' "$out" | sed 's/^/    /'; fi
done
echo "db-test: $pass passed, $fail failed, $checks checks"
[ $fail -eq 0 ]
