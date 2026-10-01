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
