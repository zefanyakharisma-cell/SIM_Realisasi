#!/usr/bin/env bash
# LOCAL ONLY. Rebuild the SIM Realisasi database: supabase/local (SIMKS-shaped stub) -> supabase/migrations -> supabase/seed.
# SEED_BULK=0 skips the bulk Kegiatan seed (supabase/seed/04_bulk_*.sql, 200 extra kegiatan RL-2026-0101..0300); the SQL
# acceptance tests (npm run test:db) and the e2e journeys expect only the S-01..S-34 scenarios.
# Idempotent: drops the realisasi/kerjasama/mock schemas (and the local SIMKS stub tables unless RESET_PUBLIC_STUBS=0).
# Never point this at the SIM Kerjasama Supabase project: use scripts/db-deploy-supabase.sh there.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for f in "$ROOT/.env.local" "$ROOT/.env"; do
  if [ -f "$f" ]; then
    # only pick up DATABASE_URL / RESET_PUBLIC_STUBS; ignore everything else
    while IFS='=' read -r k v; do
      case "$k" in
        DATABASE_URL|RESET_PUBLIC_STUBS|SEED_BULK)
          if [ -z "${!k:-}" ]; then v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"; export "$k=$v"; fi ;;
      esac
    done < <(grep -E '^(DATABASE_URL|RESET_PUBLIC_STUBS|SEED_BULK)=' "$f" || true)
  fi
done

DATABASE_URL="${DATABASE_URL:-postgresql://postgres@localhost:54322/sim_realisasi}"
RESET_PUBLIC_STUBS="${RESET_PUBLIC_STUBS:-1}"
SEED_BULK="${SEED_BULK:-1}"
export PGOPTIONS="${PGOPTIONS:-} -c client_min_messages=warning"

# --- create the database if missing (connect to the same server's "postgres" DB)
DB_NAME="$(python3 -c 'import sys,urllib.parse as u; print(u.urlparse(sys.argv[1]).path.lstrip("/") or "postgres")' "$DATABASE_URL")"
ADMIN_URL="$(python3 -c 'import sys,urllib.parse as u; p=u.urlparse(sys.argv[1]); print(u.urlunparse(p._replace(path="/postgres")))' "$DATABASE_URL")"
if ! psql "$ADMIN_URL" -tAc "select 1 from pg_database where datname = '$DB_NAME'" | grep -q 1; then
  echo "Creating database $DB_NAME"
  psql "$ADMIN_URL" -v ON_ERROR_STOP=1 -qc "create database \"$DB_NAME\""
fi

case "$DATABASE_URL" in
  *supabase.co*|*supabase.com*|*pooler.supabase*)
    if [ "${I_KNOW_THIS_DROPS_SIMKS:-}" != "yes" ]; then
      echo "db-reset.sh refuses to run against Supabase ($DATABASE_URL): it drops schemas and the SIMKS tables." >&2
      echo "Use scripts/db-deploy-supabase.sh for the simks-partnership project." >&2
      exit 2
    fi ;;
esac

PSQL=(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -X -o /dev/null)

# Never wipe a real SIM Kerjasama schema: the public SIMKS tables may only be dropped/seeded when they are absent or
# are this repo's local stub (marked by a table comment in supabase/local/00_simks_stub.sql).
# (Stubs created before the marker existed are recognised by the demo accounts' @demo.petra.ac.id emails.)
SIMKS_MARK="$(psql "$DATABASE_URL" -X -tAc "select case
    when obj_description('public.dokumen_kerja_sama'::regclass, 'pg_class') = 'sim-realisasi local SIMKS stub'
      or (to_regclass('public.akun') is not null
          and exists (select 1 from public.akun where email like '%@demo.petra.ac.id'))
    then 'sim-realisasi local SIMKS stub' else '<real>' end
  where to_regclass('public.dokumen_kerja_sama') is not null" 2>/dev/null || true)"
if [ -n "$SIMKS_MARK" ] && [ "$SIMKS_MARK" != "sim-realisasi local SIMKS stub" ] && [ "${I_KNOW_THIS_DROPS_SIMKS:-}" != "yes" ]; then
  echo "db-reset.sh refuses: $DATABASE_URL already has real SIM Kerjasama tables (public.dokumen_kerja_sama is not the local stub)." >&2
  echo "Resetting would drop and overwrite SIMKS data. To install Realisasi on top of it use:" >&2
  echo "  DATABASE_URL=... scripts/db-deploy-supabase.sh --check   (then without --check)" >&2
  exit 2
fi

echo "Dropping schemas realisasi, kerjasama, mock_baak, mock_hr"
"${PSQL[@]}" -c "drop schema if exists realisasi, kerjasama, mock_baak, mock_hr cascade"
if [ "$RESET_PUBLIC_STUBS" != "0" ]; then
  echo "Dropping local SIMKS stub tables (and pre-adapter Realisasi stubs)"
  "${PSQL[@]}" -c "drop table if exists public.akun, public.jabatan, public.proposal_dokumen_unit, public.partner_pengusul,
                   public.dokumen_kerja_sama, public.proposal_dokumen, public.partner, public.negara, public.unit,
                   public.jenis_unit, public.agenda cascade;
                   drop type if exists public.jenis_kerjasama;
                   drop table if exists public.document_scope_units, public.document_partners, public.profiles,
                   public.documents, public.partners, public.countries, public.units cascade"
fi

shopt -s nullglob
for f in "$ROOT"/supabase/local/*.sql; do
  echo "local   $(basename "$f")"
  "${PSQL[@]}" -f "$f"
done
for f in "$ROOT"/supabase/migrations/*.sql; do
  echo "migrate $(basename "$f")"
  "${PSQL[@]}" -f "$f"
done
for f in "$ROOT"/supabase/seed/*.sql; do
  case "$(basename "$f")" in 04_bulk_*) if [ "$SEED_BULK" = "0" ]; then continue; fi ;; esac
  echo "seed    $(basename "$f")"
  "${PSQL[@]}" -f "$f"
done
echo "db-reset OK ($DATABASE_URL)"
