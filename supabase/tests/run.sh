#!/usr/bin/env bash
# Runs every supabase/tests/*.test.sql against the cloud dev DB via psql and
# fails on any `not ok` line or SQL error. Each test file is transaction-wrapped
# (begin … rollback), so runs leave no data behind.
set -euo pipefail
# Read SUPABASE_DB_URL without executing .env (values may contain shell-special chars).
if [ -f .env ]; then
  SUPABASE_DB_URL="$(grep -m1 '^SUPABASE_DB_URL=' .env | cut -d= -f2-)"
fi
: "${SUPABASE_DB_URL:?set SUPABASE_DB_URL in .env}"
PSQL="${PSQL:-/opt/homebrew/opt/libpq/bin/psql}"
# pgTAP lives in the extensions schema; expose it plus public to the tests.
export PGOPTIONS="-c search_path=public,extensions"
shopt -s nullglob
status=0
for f in supabase/tests/*.test.sql; do
  out=$("$PSQL" "$SUPABASE_DB_URL" -X -q -t -A -v ON_ERROR_STOP=1 -f "$f" 2>&1) || {
    echo "FAIL (error): $f"; echo "$out" | sed 's/^/    /'; status=1; continue; }
  if grep -q '^not ok' <<<"$out"; then
    echo "FAIL: $f"; grep -E '^(not ok|# )' <<<"$out" | sed 's/^/    /'; status=1
  else
    echo "PASS: $f ($(grep -c '^ok' <<<"$out") assertions)"
  fi
done
exit $status
