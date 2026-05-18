#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE"

mkdir -p logs report charts

export PGPASSWORD="${PGPASSWORD:-lab4pass}"
PGHOST="${PGHOST:-127.0.0.1}"
PGPORT="${PGPORT:-15435}"
PGUSER="${PGUSER:-lab4user}"
PGDATABASE="${PGDATABASE:-subd_lab4_clean}"

LOG="logs/30_update_index_usage.log"
: > "$LOG"

run_sql() {
  local file="$1"
  echo "=== RUN $file ===" | tee -a "$LOG"
  psql \
    -h "$PGHOST" \
    -p "$PGPORT" \
    -U "$PGUSER" \
    -d "$PGDATABASE" \
    -P pager=off \
    -v ON_ERROR_STOP=1 \
    -f "$file" 2>&1 | tee -a "$LOG"
}

run_sql sql/30a_update_index_usage_setup.sql
run_sql sql/30b_update_no_index.sql
run_sql sql/30c_update_simple_btree.sql
run_sql sql/30d_update_unique_btree.sql
run_sql sql/30e_update_expression_index.sql
run_sql sql/30f_update_function_index.sql
run_sql sql/30g_update_index_usage_export.sql

echo "=== BUILD CHARTS ===" | tee -a "$LOG"
python3 scripts/30_make_update_index_usage_charts.py 2>&1 | tee -a "$LOG"

echo "=== AUDIT ===" | tee -a "$LOG"
scripts/30_audit_update_index_usage.sh 2>&1 | tee logs/30_update_index_usage_audit.log | tee -a "$LOG"

echo "=== DONE ===" | tee -a "$LOG"
echo "Log: $LOG"
echo "Audit: logs/30_update_index_usage_audit.log"
