#!/usr/bin/env bash
set -euo pipefail

cd /mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4_clean

export PGPASSWORD=lab4pass

PSQL=(
  psql
  -h 127.0.0.1
  -p 15435
  -U lab4user
  -d subd_lab4_clean
  -v ON_ERROR_STOP=1
  -P pager=off
)

echo "=== DENSE AUDIT: measurement counts ==="

"${PSQL[@]}" -c "
SELECT
    operation_name,
    count(*) AS raw_measurements,
    count(DISTINCT rows_base) AS tested_table_sizes,
    min(rows_base) AS min_rows,
    max(rows_base) AS max_rows
FROM lab4.extended_all_sizes_measurements
GROUP BY operation_name
ORDER BY operation_name;
"

echo
echo "=== DENSE AUDIT: expected checks ==="

"${PSQL[@]}" -c "
WITH checks AS (
    SELECT
        'select_raw_rows_expected_180' AS check_name,
        count(*) AS actual_value,
        CASE WHEN count(*) = 180 THEN 'OK' ELSE 'FAIL' END AS check_result
    FROM lab4.extended_all_sizes_measurements
    WHERE operation_name = 'select'

    UNION ALL

    SELECT
        'insert_raw_rows_expected_375',
        count(*),
        CASE WHEN count(*) = 375 THEN 'OK' ELSE 'FAIL' END
    FROM lab4.extended_all_sizes_measurements
    WHERE operation_name = 'insert'

    UNION ALL

    SELECT
        'update_raw_rows_expected_375',
        count(*),
        CASE WHEN count(*) = 375 THEN 'OK' ELSE 'FAIL' END
    FROM lab4.extended_all_sizes_measurements
    WHERE operation_name = 'update'

    UNION ALL

    SELECT
        'select_found_rows_equal_probes',
        count(*),
        CASE WHEN bool_and(found_rows = probes) THEN 'OK' ELSE 'FAIL' END
    FROM lab4.extended_all_sizes_measurements
    WHERE operation_name = 'select'

    UNION ALL

    SELECT
        'insert_affected_rows_equal_batch',
        count(*),
        CASE WHEN bool_and(affected_rows = batch_size) THEN 'OK' ELSE 'FAIL' END
    FROM lab4.extended_all_sizes_measurements
    WHERE operation_name = 'insert'

    UNION ALL

    SELECT
        'update_affected_and_trigger_rows_equal_batch',
        count(*),
        CASE WHEN bool_and(affected_rows = batch_size AND trigger_rows = batch_size) THEN 'OK' ELSE 'FAIL' END
    FROM lab4.extended_all_sizes_measurements
    WHERE operation_name = 'update'
)
SELECT *
FROM checks
ORDER BY check_name;
"

echo
echo "=== DENSE AUDIT: expected CSV files ==="

expected_reports=(
  "report/12_dense_under_1m_raw.csv"
  "report/12_dense_under_1m_aggregated.csv"
  "report/12_dense_under_1m_sizes.csv"
  "report/12_dense_under_1m_checks.csv"
)

for f in "${expected_reports[@]}"; do
  if [[ -s "$f" ]]; then
    echo "OK: $f"
  else
    echo "FAIL: $f"
  fi
done

echo
echo "=== DENSE AUDIT: expected chart files ==="

expected_charts=(
  "charts/12_dense_select_avg_ms.png"
  "charts/12_dense_select_avg_ms_logx.png"
  "charts/12_dense_select_total_seconds.png"
  "charts/12_dense_select_total_seconds_logx.png"
  "charts/12_dense_insert_total_ms.png"
  "charts/12_dense_insert_total_ms_logx.png"
  "charts/12_dense_insert_per_row_ms.png"
  "charts/12_dense_insert_per_row_ms_logx.png"
  "charts/12_dense_update_total_ms.png"
  "charts/12_dense_update_total_ms_logx.png"
  "charts/12_dense_update_per_row_ms.png"
  "charts/12_dense_update_per_row_ms_logx.png"
  "charts/12_dense_relation_bytes.png"
  "charts/12_dense_indexes_bytes.png"
  "charts/12_dense_total_bytes.png"
)

for f in "${expected_charts[@]}"; do
  if [[ -s "$f" ]]; then
    echo "OK: $f"
  else
    echo "FAIL: $f"
  fi
done

echo
echo "=== DENSE AUDIT DONE ==="
