#!/usr/bin/env bash
# LOCAL ONLY. Rebuild the SIM Realisasi database: supabase/local (SIMKS-shaped stub) -> supabase/migrations -> supabase/seed.
# Idempotent: drops the realisasi/kerjasama/mock schemas (and the local SIMKS stub tables unless RESET_PUBLIC_STUBS=0).
# Never point this at the SIM Kerjasama Supabase project: use scripts/db-deploy-supabase.sh there.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for f in "$ROOT/.env.local" "$ROOT/.env"; do
  if [ -f "$f" ]; then
    # only pick up DATABASE_URL / RESET_PUBLIC_STUBS; ignore everything else
    while IFS='=' read -r k v; do
      case "$k" in
        DATABASE_URL|RESET_PUBLIC_STUBS)
          if [ -z "${!k:-}" ]; then v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"; export "$k=$v"; fi ;;
      esac
    done < <(grep -E '^(DATABASE_URL|RESET_PUBLIC_STUBS)=' "$f" || true)
  fi
done

DATABASE_URL="${DATABASE_URL:-postgresql://postgres@localhost:54322/sim_realisasi}"
RESET_PUBLIC_STUBS="${RESET_PUBLIC_STUBS:-1}"
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

echo "Dropping schemas realisasi, kerjasama, mock_baak, mock_hr"
"${PSQL[@]}" -c "drop schema if exists realisasi, kerjasama, mock_baak, mock_hr cascade"
if [ "$RESET_PUBLIC_STUBS" != "0" ]; then
  echo "Dropping local SIMKS stub tables (and pre-adapter Realisasi stubs)"
  "${PSQL[@]}" -c "drop table if exists public.akun, public.jabatan, public.proposal_dokumen_unit, public.partner_pengusul,
                   public.dokumen_kerja_sama, public.proposal_dokumen, public.partner, public.negara, public.unit,
                   public.jenis_unit cascade;
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
  echo "seed    $(basename "$f")"
  "${PSQL[@]}" -f "$f"
done
echo "db-reset OK ($DATABASE_URL)"
