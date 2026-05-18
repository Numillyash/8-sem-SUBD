#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE"

export PGPASSWORD="${PGPASSWORD:-lab4pass}"
PGHOST="${PGHOST:-127.0.0.1}"
PGPORT="${PGPORT:-15435}"
PGUSER="${PGUSER:-lab4user}"
PGDATABASE="${PGDATABASE:-subd_lab4_clean}"

echo "=== 30 audit: expected CSV files ==="
for f in \
  report/30_update_index_usage_raw.csv \
  report/30_update_index_usage_aggregated.csv \
  report/30_update_index_usage_checks.csv \
  report/30_update_index_usage_explains.csv
do
  if [[ -s "$f" ]]; then
    echo "OK: $f"
  else
    echo "FAIL: missing or empty $f"
  fi
done

echo
echo "=== 30 audit: expected chart files ==="
for f in \
  charts/30_update_index_search_total_linear.png \
  charts/30_update_index_search_per_row_linear.png \
  charts/30_update_lookup_vs_maintenance_total_linear.png \
  charts/30_update_lookup_vs_maintenance_per_row_linear.png \
  charts/30_update_maintenance_overhead_total_linear.png \
  charts/30_update_maintenance_overhead_per_row_linear.png \
  charts/30_update_simple_btree_lookup_vs_maintenance_total_linear.png \
  charts/30_update_unique_btree_lookup_vs_maintenance_total_linear.png \
  charts/30_update_expression_index_lookup_vs_maintenance_total_linear.png \
  charts/30_update_function_index_lookup_vs_maintenance_total_linear.png
do
  if [[ -s "$f" ]]; then
    echo "OK: $f"
  else
    echo "FAIL: missing or empty $f"
  fi
done

echo
echo "=== 30 audit: measurement counts and affected rows ==="
psql \
  -h "$PGHOST" \
  -p "$PGPORT" \
  -U "$PGUSER" \
  -d "$PGDATABASE" \
  -P pager=off \
  -v ON_ERROR_STOP=1 \
  -c "
WITH expected AS
(
    SELECT
        index_type,
        mode,
        rows_base,
        count(*) AS runs,
        min(affected_rows) AS affected_min,
        max(affected_rows) AS affected_max
    FROM lab4.update_index_usage_measurements
    GROUP BY index_type, mode, rows_base
)
SELECT
    index_type,
    mode,
    count(*) AS tested_sizes,
    min(rows_base) AS min_rows,
    max(rows_base) AS max_rows,
    min(runs) AS runs_min,
    max(runs) AS runs_max,
    min(affected_min) AS affected_min,
    max(affected_max) AS affected_max,
    CASE
        WHEN count(*) <> 9
            THEN 'FAIL: every group must have 9 tested sizes'
        WHEN min(rows_base) <> 5000 OR max(rows_base) <> 2000000
            THEN 'FAIL: expected size range 5000..2000000'
        WHEN min(runs) <> 5 OR max(runs) <> 5
            THEN 'FAIL: every group must have 5 runs'
        WHEN min(affected_min) <> 1000 OR max(affected_max) <> 1000
            THEN 'FAIL: every run must affect 1000 rows'
        ELSE 'OK'
    END AS check_result
FROM expected
GROUP BY index_type, mode
ORDER BY index_type, mode;
"

echo
echo "=== 30 audit: total row counts ==="
psql \
  -h "$PGHOST" \
  -p "$PGPORT" \
  -U "$PGUSER" \
  -d "$PGDATABASE" \
  -P pager=off \
  -v ON_ERROR_STOP=1 \
  -c "
SELECT
    'raw_measurements' AS check_name,
    count(*) AS actual_value,
    CASE WHEN count(*) = 405 THEN 'OK' ELSE 'FAIL: expected 405' END AS check_result
FROM lab4.update_index_usage_measurements

UNION ALL

SELECT
    'aggregated_groups' AS check_name,
    count(*) AS actual_value,
    CASE WHEN count(*) = 81 THEN 'OK' ELSE 'FAIL: expected 81' END AS check_result
FROM (
    SELECT index_type, mode, rows_base
    FROM lab4.update_index_usage_measurements
    GROUP BY index_type, mode, rows_base
) s

UNION ALL

SELECT
    'explain_rows' AS check_name,
    count(*) AS actual_value,
    CASE WHEN count(*) = 81 THEN 'OK' ELSE 'FAIL: expected 81' END AS check_result
FROM lab4.update_index_usage_explains;
"

echo
echo "=== 30 audit: plan checks ==="
psql \
  -h "$PGHOST" \
  -p "$PGPORT" \
  -U "$PGUSER" \
  -d "$PGDATABASE" \
  -P pager=off \
  -v ON_ERROR_STOP=1 \
  -c "
WITH plan_checks AS
(
    SELECT
        index_type,
        mode,
        max(rows_base) AS checked_rows,
        string_agg(explain_plan, E'\n') AS plan_text
    FROM lab4.update_index_usage_explains
    GROUP BY index_type, mode
)
SELECT
    index_type,
    mode,
    checked_rows,
    CASE
        WHEN index_type = 'no_index'
             AND plan_text ILIKE '%Seq Scan%'
            THEN 'OK: no_index uses Seq Scan'
        WHEN index_type <> 'no_index'
             AND (
                    plan_text ILIKE '%Index Scan%'
                 OR plan_text ILIKE '%Bitmap Index Scan%'
                 OR plan_text ILIKE '%Bitmap Heap Scan%'
             )
            THEN 'OK: indexed variant uses index access'
        ELSE 'FAIL: unexpected access method'
    END AS plan_check
FROM plan_checks
ORDER BY index_type, mode;
"

echo
echo "=== 30 audit: CSV FAIL grep ==="
if grep -R "FAIL" report/30_update_index_usage_checks.csv; then
  echo "FAIL: report/30_update_index_usage_checks.csv contains FAIL"
else
  echo "OK: no FAIL in checks CSV"
fi

echo
echo "=== 30 audit done ==="
